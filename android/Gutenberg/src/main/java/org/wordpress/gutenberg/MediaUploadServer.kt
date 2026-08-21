package org.wordpress.gutenberg

import android.util.Log
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
import org.wordpress.gutenberg.http.HeaderValue
import org.wordpress.gutenberg.http.MultipartPart
import org.wordpress.gutenberg.http.HTTPRequestParseError
import org.wordpress.gutenberg.http.MultipartParseException
import java.io.File
import java.io.IOException
import java.util.UUID
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.RequestBody.Companion.asRequestBody
import okhttp3.RequestBody.Companion.toRequestBody
import okio.source

/**
 * A raw response from the WordPress REST API media endpoint.
 *
 * GutenbergKit relays this to the editor verbatim — it does not interpret the
 * body. The editor receives the exact attachment object (on success) or
 * WordPress REST error object (on failure) it would get from a direct upload,
 * so every consumer — image sub-sizes, attachment links, error notices —
 * behaves identically to a non-native upload.
 */
class MediaUploadResponse(
    /** The HTTP status code WordPress (or the host's upload service) returned. */
    val statusCode: Int,
    /**
     * The raw response body — a WordPress REST attachment on success, or a
     * WordPress REST error object (`{ "code", "message", "data" }`) on failure.
     */
    val body: ByteArray,
    /**
     * The response headers to relay to the editor.
     *
     * `x-wp-upload-attachment-id` is the one that carries behavior: WordPress
     * sets it on a failed upload whose attachment row was created before
     * metadata generation fataled, and the editor's api-fetch middleware reads
     * it to retry `post-process` and clean up the orphan. Dropping it turns a
     * recoverable upload into a permanent failure.
     */
    val headers: Map<String, String> = emptyMap()
)

/**
 * The result of a delegate's [MediaUploadDelegate.processFile].
 */
sealed class ProcessedProxyFile {
    /** The delegate did not modify the file; the original upload is forwarded unchanged. */
    data object Original : ProcessedProxyFile()

    /**
     * The delegate produced a file to upload, along with its MIME type and
     * filename. Both are used verbatim, so a format change (e.g. transcoding MOV
     * to MP4, or an in-place EXIF strip) must report the resulting type and
     * filename for WordPress to store the file correctly.
     */
    data class Processed(val file: File, val mimeType: String, val filename: String) : ProcessedProxyFile()
}

/**
 * Interface for customizing media upload behavior.
 *
 * The native host app can provide an implementation to resize images,
 * transcode video, or use its own upload service.
 */
interface MediaUploadDelegate {
    /**
     * Whether this delegate might handle a file with the given metadata — either
     * processing it ([processFile]) or uploading it itself ([uploadFile]).
     *
     * A cheap, metadata-only gate the server consults *before* materializing the
     * upload to a temp file. Return false to decline a file by type — e.g. an
     * image-only delegate returning false for a video — so the server forwards
     * the original upload to WordPress without first copying a file the delegate
     * won't touch. Because it gates the temp-file copy needed by *both*
     * [processFile] and [uploadFile], return true for any file the delegate will
     * either process or upload itself.
     *
     * Defaults to true: every file is materialized and the full pipeline runs. A
     * true here is not a commitment — [processFile] may still return
     * [ProcessedProxyFile.Original] after inspecting the file's contents.
     */
    fun handlesFile(mimeType: String, filename: String): Boolean = true

    /**
     * Process a file before upload (e.g., resize image, transcode video).
     *
     * Return [ProcessedProxyFile.Original] to upload the file unchanged, or
     * [ProcessedProxyFile.Processed] with the processed file and its metadata.
     * When the format changes, report the new mimeType and filename so WordPress
     * stores it with the correct extension and type.
     */
    suspend fun processFile(file: File, mimeType: String, filename: String): ProcessedProxyFile = ProcessedProxyFile.Original

    /**
     * Upload a processed file to the remote WordPress site.
     *
     * Return the raw WordPress response (status code + body), which GutenbergKit
     * relays to the editor unchanged, or null to use the default uploader. A host
     * that uploads to WordPress should return the exact response it received so
     * the editor sees a complete attachment object.
     */
    suspend fun uploadFile(file: File, mimeType: String, filename: String): MediaUploadResponse? = null

    /**
     * Delete a previously uploaded attachment.
     *
     * The editor deletes the attachment when an upload's server-side
     * post-processing fails past recovery, so it does not leave an orphan
     * behind. A delegate that uploaded the attachment itself via [uploadFile]
     * owns an ID only it can resolve, so it must delete the attachment itself
     * too — the default uploader would address the wrong site.
     *
     * Return the raw response (status code + body), which GutenbergKit relays
     * to the editor unchanged, or null to use the default uploader.
     */
    suspend fun deleteFile(attachmentId: String): MediaUploadResponse? = null
}

/**
 * A local HTTP server that receives file uploads from the WebView and routes
 * them through the native media processing pipeline.
 *
 * Built on [HttpServer], which handles TCP binding, HTTP parsing, bearer token
 * authentication, and connection management. This class provides the upload-
 * specific handler: receiving a file, delegating to the host app for
 * processing/upload, and returning the result as JSON.
 *
 * Lifecycle is tied to [GutenbergView] — start when the editor loads,
 * stop on detach.
 */
internal class MediaUploadServer(
    private val uploadDelegate: MediaUploadDelegate?,
    private val defaultUploader: DefaultMediaUploader?,
    cacheDir: File? = null,
    scope: CoroutineScope? = null,
    ioDispatcher: CoroutineDispatcher = Dispatchers.IO
) : HttpServerDelegate {
    /** The port the server is listening on. */
    val port: Int get() = server.port

    /** Per-session auth token for validating incoming requests. */
    val token: String get() = server.token

    private val server: HttpServer

    /**
     * Directory for staging uploaded files, under the injected cache dir (with a
     * system-temp fallback) so orphans share the app's managed cache lifecycle.
     */
    private val uploadsTempDir: File =
        File(cacheDir ?: File(System.getProperty("java.io.tmpdir")), "gutenbergkit-uploads")

    /**
     * The scope MediaUploadServer created itself because the caller supplied none.
     * It is cancelled in [stop]; a caller-supplied scope is left to the caller's
     * lifecycle (cancelling it here would tear down state the caller still owns).
     */
    private val ownedScope: CoroutineScope? =
        if (scope == null) CoroutineScope(Dispatchers.IO) else null

    /**
     * Sweeps crash-orphaned temp files off the caller's thread. Exposed so tests
     * can await it; injecting `Dispatchers.Unconfined` for [ioDispatcher] runs the
     * sweep synchronously.
     */
    @Suppress("TooGenericExceptionCaught")
    val cleanupJob: Job = (scope ?: ownedScope!!).launch(ioDispatcher) {
        try {
            cleanOrphanedUploads()
        } catch (e: Exception) {
            Log.w(TAG, "Failed to sweep orphaned uploads", e)
        }
    }

    init {
        server = HttpServer(
            name = "media-upload",
            externallyAccessible = false,
            requiresAuthentication = true,
            bodyReadTimeoutMs = UPLOAD_BODY_READ_TIMEOUT_MS,
            cacheDir = cacheDir,
            cors = CorsPolicy.Permissive,
            delegate = this,
            handler = { request -> handleRequest(request) }
        )
        server.start()
    }

    /** Stops the server and releases resources. */
    fun stop() {
        cleanupJob.cancel()
        server.stop()
        // Cancel the scope only if we created it; a caller-supplied scope is theirs.
        ownedScope?.cancel()
    }

    /**
     * Deletes upload temp files left behind by a prior crash. Files still in
     * flight (only seconds old) are preserved by the age threshold, so this is
     * safe even if another editor instance is mid-upload.
     */
    private fun cleanOrphanedUploads() {
        val cutoff = System.currentTimeMillis() - 60 * 60 * 1000L // 1 hour
        uploadsTempDir.listFiles()?.forEach { file ->
            if (file.lastModified() < cutoff) {
                file.delete()
            }
        }
    }

    // MARK: - Request Handling

    /**
     * Answers the server's recoverable parse errors (e.g. an over-limit body) with
     * the same JSON `{code, message}` shape the editor expects, so the middleware
     * surfaces a real message ("The file is too large…") instead of a generic
     * parse-failure. See [HttpServerDelegate].
     */
    override fun responseForRecoverableParseError(error: HTTPRequestParseError): HttpResponse {
        val message = when (error) {
            HTTPRequestParseError.PAYLOAD_TOO_LARGE -> "The file is too large to upload in the editor."
            else -> error.errorId
        }
        return errorResponse(error.httpStatus, message)
    }

    private suspend fun handleRequest(request: HttpRequest): HttpResponse {
        // Routes: POST /upload, and DELETE /media/<id> for the editor's orphan
        // cleanup. (OPTIONS preflight is answered by the HTTP library under its
        // permissive CORS policy.) Match on the path alone — the target carries
        // a query string (e.g. `?_embed`, `?force=true`) relayed to WordPress.
        val method = request.method.uppercase()

        if (method == "POST" && request.path == "/upload") {
            return handleUpload(request)
        }

        if (method == "DELETE") {
            attachmentIdFromPath(request.path)?.let { attachmentId ->
                return handleMediaDelete(attachmentId, request.query)
            }
        }

        return errorResponse(404, "Not found")
    }

    /**
     * The attachment ID in a `/media/<id>` path, or `null` if the path is not one.
     *
     * Deliberately narrow: this server relays media operations, not arbitrary
     * REST requests, so only a numeric attachment ID under `/media/` matches.
     */
    private fun attachmentIdFromPath(path: String): String? {
        val components = path.split("/").filter { it.isNotEmpty() }
        if (components.size != 2 || components[0] != "media") return null
        val id = components[1]
        return if (id.isNotEmpty() && id.all { it.isDigit() }) id else null
    }

    /**
     * Relays the editor's orphan cleanup.
     *
     * Core's media upload middleware deletes the attachment when every
     * `post-process` retry fails. A cross-origin editor cannot issue that
     * request directly — api-fetch tunnels `DELETE` as a `POST` carrying
     * `X-HTTP-Method-Override`, which core's CORS allow-list omits, so the
     * browser blocks it at preflight. Relaying it here lets the cleanup run.
     *
     * Offers the deletion to the delegate first, as [handleUpload] does, so a
     * host that uploaded the attachment itself deletes it from the same place.
     */
    private suspend fun handleMediaDelete(attachmentId: String, query: String): HttpResponse {
        return try {
            uploadDelegate?.deleteFile(attachmentId)?.let { return relayResponse(it) }

            val uploader = defaultUploader ?: return errorResponse(500, "No uploader configured")
            relayResponse(uploader.deleteMedia(attachmentId, query))
        } catch (e: IOException) {
            Log.e(TAG, "Media deletion failed", e)
            errorResponse(500, e.message ?: "Deletion failed")
        }
    }

    private suspend fun handleUpload(request: HttpRequest): HttpResponse {
        val parts = parseParts(request)
            ?: return errorResponse(400, "Expected multipart/form-data with a file")
        val filePart = parts.firstOrNull { it.filename != null }
            ?: return errorResponse(400, "Expected multipart/form-data with a file")

        // The non-file parts (post, additionalData) and the original query
        // (e.g. ?_embed) must reach WordPress too — relay them alongside the file.
        val extraParts = parts.filter { it.filename == null }
        val query = request.query
        val mimeType = filePart.contentType
        val filename = filePart.filename ?: "upload"

        // Ask the delegate — from metadata alone — whether it will touch a file
        // like this. If not, forward the original upload to WordPress directly,
        // skipping a full temp-file copy of a file the delegate won't process or
        // upload (e.g. a video handed to an image-only delegate).
        if (uploadDelegate?.handlesFile(mimeType, filename) != true) {
            return passthroughResponse(request, query)
        }

        val tempFile = writePartToTempFile(filePart)
            ?: return errorResponse(500, "Failed to save file")

        return processAndRespond(request, tempFile, filePart, extraParts, query)
    }

    @Suppress("TooGenericExceptionCaught")
    private suspend fun passthroughResponse(request: HttpRequest, query: String): HttpResponse {
        return try {
            Log.d(TAG, "Passthrough: forwarding original request body to WordPress")
            relayResponse(performPassthroughUpload(request, query))
        } catch (e: kotlin.coroutines.cancellation.CancellationException) {
            throw e // Never swallow coroutine cancellation.
        } catch (e: Exception) {
            Log.e(TAG, "Passthrough upload failed", e)
            errorResponse(500, e.message ?: "Upload failed")
        }
    }

    /**
     * Relays WordPress's exact status, body, and relayable headers to the editor
     * so it sees the same attachment object (or error) as a direct upload.
     *
     * The headers matter for recovery: `x-wp-upload-attachment-id` is what lets
     * the editor retry `post-process` for an upload whose metadata generation
     * fataled server-side, rather than surfacing a permanent failure and leaving
     * an orphaned attachment behind.
     */
    private fun relayResponse(response: MediaUploadResponse): HttpResponse {
        return HttpResponse(
            status = response.statusCode,
            headers = mapOf("Content-Type" to "application/json") + response.headers,
            body = response.body
        )
    }

    private fun parseParts(request: HttpRequest): List<MultipartPart>? {
        val contentType = request.header("Content-Type") ?: return null
        val boundary = HeaderValue.extractParameter("boundary", contentType) ?: return null
        val body = request.body ?: return null

        return try {
            val inMemory = body.inMemoryData
            if (inMemory != null) {
                MultipartPart.parse(body, inMemory, 0L, boundary)
            } else {
                @Suppress("UNCHECKED_CAST")
                MultipartPart.parseChunked(
                    body as org.wordpress.gutenberg.http.RequestBody.FileBacked,
                    boundary
                )
            }
        } catch (e: MultipartParseException) {
            Log.e(TAG, "Multipart parse failed", e)
            null
        }
    }

    private fun writePartToTempFile(filePart: MultipartPart): File? {
        val filename = sanitizeFilename(filePart.filename ?: "upload")
        uploadsTempDir.mkdirs()
        val tempFile = File(uploadsTempDir, "${UUID.randomUUID()}-$filename")

        return try {
            filePart.body.inputStream().use { input ->
                tempFile.outputStream().use { output ->
                    input.copyTo(output)
                }
            }
            tempFile
        } catch (e: IOException) {
            tempFile.delete()
            Log.e(TAG, "Failed to write upload to disk", e)
            null
        }
    }

    @Suppress("TooGenericExceptionCaught")
    private suspend fun processAndRespond(
        request: HttpRequest, tempFile: File, filePart: MultipartPart,
        extraParts: List<MultipartPart>, query: String
    ): HttpResponse {
        try {
            val uploadResult = processAndUpload(
                tempFile, filePart.contentType, filePart.filename ?: "upload", extraParts, query
            )
            val response = when (uploadResult) {
                is UploadResult.Uploaded -> {
                    Log.d(TAG, "Uploaded file to WordPress")
                    uploadResult.response
                }
                is UploadResult.Passthrough -> {
                    // Delegate didn't modify the file — forward the original
                    // request body to WordPress without re-encoding.
                    Log.d(TAG, "Passthrough: forwarding original request body to WordPress")
                    performPassthroughUpload(request, query)
                }
            }
            return relayResponse(response)
        } catch (e: MediaUploadException) {
            Log.e(TAG, "Upload processing failed", e)
            return errorResponse(500, e.message ?: "Upload failed")
        } catch (e: kotlin.coroutines.cancellation.CancellationException) {
            throw e // Never swallow coroutine cancellation.
        } catch (e: Exception) {
            // Any other failure — IOException from the upload call, JSON parse
            // errors, a throwing host delegate, or "no uploader configured" —
            // must still be answered WITH CORS headers. Otherwise it escapes to
            // HttpServer's header-less 500 fallback and the browser rejects the
            // preflighted cross-origin fetch with an opaque "Failed to fetch",
            // hiding the real error from the editor (mirrors the iOS catch-all).
            Log.e(TAG, "Upload failed", e)
            return errorResponse(500, e.message ?: "Upload failed")
        } finally {
            tempFile.delete()
        }
    }

    // MARK: - Delegate Pipeline

    private sealed class UploadResult {
        data class Uploaded(val response: MediaUploadResponse) : UploadResult()
        data object Passthrough : UploadResult()
    }

    private suspend fun performPassthroughUpload(request: HttpRequest, query: String): MediaUploadResponse {
        val body = request.body
        val contentType = request.header("Content-Type")
        val uploader = defaultUploader
        if (body == null || contentType == null || uploader == null) {
            throw MediaUploadException("Passthrough upload requires a request body, Content-Type, and default uploader")
        }
        return uploader.passthroughUpload(body, contentType, query)
    }

    private suspend fun processAndUpload(
        file: File, mimeType: String, filename: String,
        extraParts: List<MultipartPart>, query: String
    ): UploadResult {
        val processed = uploadDelegate?.processFile(file, mimeType, filename) ?: ProcessedProxyFile.Original

        // Resolve the file to upload and its metadata. Processed uses the
        // delegate's values verbatim, so a format change is reported to WordPress.
        val targetFile: File
        val targetMimeType: String
        val targetFilename: String
        when (processed) {
            is ProcessedProxyFile.Original -> {
                targetFile = file
                targetMimeType = mimeType
                targetFilename = filename
            }
            is ProcessedProxyFile.Processed -> {
                targetFile = processed.file
                targetMimeType = processed.mimeType
                targetFilename = processed.filename
            }
        }

        try {
            // If the delegate provided its own upload, use that.
            uploadDelegate?.uploadFile(targetFile, targetMimeType, targetFilename)?.let {
                return UploadResult.Uploaded(it)
            }

            // Unmodified — forward the original request body directly, skipping
            // multipart re-encoding.
            if (processed is ProcessedProxyFile.Original) {
                return UploadResult.Passthrough
            }

            val result = defaultUploader?.upload(targetFile, targetMimeType, targetFilename, extraParts, query)
                ?: error("No upload delegate or default uploader configured")
            return UploadResult.Uploaded(result)
        } finally {
            // The processed file (if the delegate produced a new one) is ours to
            // clean up — covers the success and throw paths alike.
            if (targetFile != file) {
                targetFile.delete()
            }
        }
    }

    // MARK: - Response Building

    private fun errorResponse(status: Int, message: String): HttpResponse {
        // Emit a WordPress-REST-style error object so the JS middleware normalizes
        // it (and surfaces `message`) the same way it does a relayed WordPress
        // error — the local server's own errors need no special-casing.
        val json = org.json.JSONObject()
            .put("code", "upload_error")
            .put("message", message)
            .toString()
        return HttpResponse(
            status = status,
            headers = mapOf("Content-Type" to "application/json"),
            body = json.toByteArray()
        )
    }

    // MARK: - Helpers

    /** Sanitizes a filename to prevent path traversal. */
    private fun sanitizeFilename(name: String): String {
        val safe = File(name).name.replace(Regex("[/\\\\]"), "")
        return safe.ifEmpty { "upload" }
    }

    companion object {
        private const val TAG = "MediaUploadServer"

        /**
         * A generous ceiling for receiving the upload body. The body read is
         * primarily bounded by the per-read idle timeout (which reaps a stalled
         * connection in seconds); this absolute backstop ensures a slow-but-steady
         * client can't hold a connection slot indefinitely. Ten minutes is far
         * beyond any realistic media upload over loopback while still bounding a
         * wedged one.
         */
        private const val UPLOAD_BODY_READ_TIMEOUT_MS: Int = 10 * 60 * 1000
    }
}

/** Exception thrown when a media upload fails. */
internal class MediaUploadException(message: String, cause: Throwable? = null) : Exception(message, cause)

/**
 * Uploads files to the WordPress REST API using OkHttp.
 */
internal open class DefaultMediaUploader(
    private val httpClient: okhttp3.OkHttpClient,
    private val siteApiRoot: String,
    private val authHeader: String,
    private val siteApiNamespace: List<String> = emptyList()
) {
    /**
     * The WordPress media endpoint URL, built through the shared [RestUrlBuilder]
     * namespacing (so it matches every other REST URL) and carrying the original
     * request query (e.g. `?_embed`) through to WordPress.
     */
    private fun mediaEndpointUrl(query: String, attachmentId: String? = null): String {
        val path = if (attachmentId != null) "/wp/v2/media/$attachmentId" else "/wp/v2/media"
        return RestUrlBuilder.namespaced(siteApiRoot, siteApiNamespace.firstOrNull(), path) + query
    }

    /**
     * Deletes an attachment, relaying WordPress's response verbatim.
     *
     * Carries the editor's query through unchanged — core's cleanup sends
     * `?force=true`, without which WordPress trashes rather than deletes.
     */
    open suspend fun deleteMedia(attachmentId: String, query: String): MediaUploadResponse {
        val request = okhttp3.Request.Builder()
            .url(mediaEndpointUrl(query, attachmentId))
            .addHeader("Authorization", authHeader)
            .delete()
            .build()

        return performUpload(request)
    }

    open suspend fun upload(
        file: File, mimeType: String, filename: String,
        extraParts: List<MultipartPart>, query: String
    ): MediaUploadResponse {
        val mediaType = mimeType.toMediaType()
        val builder = okhttp3.MultipartBody.Builder().setType(okhttp3.MultipartBody.FORM)
        // Preserve the non-file parts (post, additionalData) through the re-encode.
        // Append each field's raw bytes (not via String) so a non-UTF-8 value is
        // forwarded verbatim rather than coerced. filename=null makes it a plain
        // field, matching okhttp's String overload byte-for-byte.
        for (part in extraParts) {
            builder.addFormDataPart(part.name, null, part.body.readBytes().toRequestBody())
        }
        builder.addFormDataPart("file", filename, file.asRequestBody(mediaType))

        val request = okhttp3.Request.Builder()
            .url(mediaEndpointUrl(query))
            .addHeader("Authorization", authHeader)
            .post(builder.build())
            .build()

        return performUpload(request)
    }

    /**
     * Forwards the original request body to WordPress without re-encoding.
     *
     * Used when the delegate's `processFile` returned the file unchanged —
     * the incoming multipart body is already valid for WordPress.
     */
    open suspend fun passthroughUpload(
        body: org.wordpress.gutenberg.http.RequestBody,
        contentType: String,
        query: String
    ): MediaUploadResponse {
        val streamBody = object : okhttp3.RequestBody() {
            override fun contentType() = contentType.toMediaType()
            override fun contentLength() = body.size
            override fun writeTo(sink: okio.BufferedSink) {
                body.inputStream().use { sink.writeAll(it.source()) }
            }
        }

        val request = okhttp3.Request.Builder()
            .url(mediaEndpointUrl(query))
            .addHeader("Authorization", authHeader)
            .post(streamBody)
            .build()

        return performUpload(request)
    }

    private suspend fun performUpload(request: okhttp3.Request): MediaUploadResponse {
        // Relay WordPress's response verbatim — including non-2xx statuses — so
        // the editor sees WordPress's real status and error body, exactly as a
        // direct upload would.
        //
        // Enqueue rather than execute() so coroutine cancellation can tear down
        // the outbound call: when the editor aborts the upload the server cancels
        // this handler, and the in-flight POST /wp/v2/media must be cancelled
        // rather than run to completion and orphan an attachment that a retry
        // then duplicates.
        val call = httpClient.newCall(request)
        return suspendCancellableCoroutine { continuation ->
            continuation.invokeOnCancellation { call.cancel() }
            call.enqueue(object : okhttp3.Callback {
                override fun onResponse(call: okhttp3.Call, response: okhttp3.Response) {
                    // Read the body inside a try/catch and resume the continuation
                    // ourselves on failure. OkHttp marks the callback as signalled
                    // before invoking onResponse, so a throw while reading the body
                    // — a truncated/reset stream, or the read timeout firing mid-body
                    // after WordPress already sent its 201 headers — is swallowed
                    // rather than routed to onFailure. Without this the continuation
                    // would never resume and the upload coroutine would hang forever,
                    // holding a connection permit.
                    val result = try {
                        response.use {
                            MediaUploadResponse(
                                it.code,
                                it.body?.bytes() ?: ByteArray(0),
                                relayableHeaders(it)
                            )
                        }
                    } catch (e: IOException) {
                        if (!continuation.isCancelled) continuation.resumeWithException(e)
                        return
                    }
                    continuation.resume(result)
                }

                override fun onFailure(call: okhttp3.Call, e: IOException) {
                    // A cancelled call also surfaces here; the continuation is
                    // already resumed via cancellation, so don't resume again.
                    if (continuation.isCancelled) return
                    continuation.resumeWithException(e)
                }
            })
        }
    }

    /** Picks the headers to relay out of an upstream response. */
    private fun relayableHeaders(response: okhttp3.Response): Map<String, String> =
        RELAYABLE_HEADER_NAMES.mapNotNull { name ->
            response.header(name)?.let { name to it }
        }.toMap()

    companion object {
        /**
         * The upstream headers worth relaying to the editor.
         *
         * Deliberately an allowlist rather than a filtered passthrough: the body
         * is re-sent with a recomputed length, so relaying upstream entity or
         * transport headers wholesale would risk contradicting what the server
         * actually sends.
         */
        private val RELAYABLE_HEADER_NAMES = listOf("x-wp-upload-attachment-id")
    }
}
