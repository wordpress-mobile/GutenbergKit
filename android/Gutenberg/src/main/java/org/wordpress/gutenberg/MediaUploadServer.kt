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
internal class MediaUploadResponse(
    /** The HTTP status code WordPress returned. */
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
 * The result of a [MediaProcessor.processFile].
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
 * Transforms media before GutenbergKit delivers it.
 *
 * A processor only changes *bytes* — GutenbergKit still uploads the result to the
 * configured site and owns the whole lifecycle (retries, cleanup). Because it
 * never performs the upload itself, a processor cannot deliver media to the wrong
 * place. Set [GutenbergView.mediaProcessor] to resize images, transcode video,
 * strip EXIF, etc. This is the safe, common extension point: most hosts want only
 * this.
 */
interface MediaProcessor {
    /**
     * Whether this processor might transform a file with the given metadata. A
     * cheap, metadata-only gate consulted *before* the upload is materialized to a
     * temp file; return false to pass a file straight through untouched — e.g. an
     * image-only processor returning false for a video. Defaults to true; not a
     * commitment, since [processFile] may still return [ProcessedProxyFile.Original]
     * after inspecting the file's contents.
     */
    fun handlesFile(mimeType: String, filename: String): Boolean = true

    /**
     * Transform a file before upload (e.g., resize image, transcode video). Return
     * [ProcessedProxyFile.Original] to upload it unchanged, or
     * [ProcessedProxyFile.Processed] with the new file and its metadata (report the
     * new mimeType and filename when the format changes, so WordPress stores it
     * with the correct extension and type).
     */
    suspend fun processFile(file: File, mimeType: String, filename: String): ProcessedProxyFile = ProcessedProxyFile.Original
}

/**
 * Everything a [MediaUploader] needs to reproduce a native upload: the file to send,
 * its metadata, the editor's non-file form fields, and the request's query.
 *
 * @property file The file to upload — already processed, if a [MediaProcessor] ran.
 * @property mimeType The file's MIME type.
 * @property filename The file's name.
 * @property fields The editor's non-file form fields, in order, each decoded as UTF-8 —
 *   most importantly `post`, the parent post's ID, without which the attachment is
 *   created unattached. A list of `(name, value)` pairs, not a map, so repeated field
 *   names (e.g. a `field[]` array) survive verbatim. Send each as a form part on your
 *   `POST /wp/v2/media`, in the given order.
 * @property query The request's query string (leading `?`, e.g. `?_embed=...`), or
 *   empty. Carry it on your request so the editor gets the response it expects.
 */
data class MediaUpload(
    val file: File,
    val mimeType: String,
    val filename: String,
    val fields: List<Pair<String, String>>,
    val query: String
)

/**
 * Takes over performing a media upload — on the host's own stack: its own
 * networking (say, to log every request), a background service, an offline queue,
 * a resumable transport, its own retry policy.
 *
 * This is a choice of who executes the requests, not where they go: an uploader
 * and GutenbergKit's built-in default both target the same configured site.
 * Setting [GutenbergView.mediaUploader] makes the host own that upload end-to-end —
 * the request, its own retries, and its recovery and cleanup — with GutenbergKit
 * out of the network entirely. Because the host does the retries itself, there's no
 * raw response left for core to retry behind it. The attachment you return lives on
 * that same configured site, where the editor reads and updates it by ID.
 */
interface MediaUploader {
    /**
     * Upload a (possibly processed) file and return the finished WordPress
     * attachment JSON the editor inserts — the same object a direct
     * `POST /wp/v2/media` returns. Return only once the upload is genuinely done, or
     * throw on terminal failure: a returned value is taken as a completed attachment,
     * and there is no GutenbergKit recovery behind you.
     *
     * The [MediaUpload] carries the file plus the editor's form fields (e.g. `post`)
     * and query — send them all so the created attachment matches a native upload
     * rather than landing as an unattached orphan.
     *
     * That recovery is yours to run. When `POST /wp/v2/media` fatals in server-side
     * post-processing it returns a 5xx carrying the attachment's ID in
     * `x-wp-upload-attachment-id` — the attachment exists but is unfinished. Don't
     * re-upload; drive `POST /wp/v2/media/<id>/post-process` to completion, the way
     * core recovers its own uploads (up to 5 attempts), then return the finished
     * attachment.
     *
     * Owning the upload means owning cleanup on the server too: if post-process
     * can't be recovered, force-delete the orphan (`DELETE /wp/v2/media/<id>?force=true`)
     * before you throw, or it stays on the site — neither GutenbergKit nor core
     * cleans up behind you.
     */
    suspend fun upload(upload: MediaUpload): ByteArray
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
    private val processor: MediaProcessor?,
    private val uploader: MediaUploader?,
    private val internalClient: InternalMediaClient,
    cacheDir: File,
    scope: CoroutineScope? = null,
    ioDispatcher: CoroutineDispatcher = Dispatchers.IO
) : HttpServerDelegate {
    /** The port the server is listening on. */
    val port: Int get() = server.port

    /** Per-session auth token for validating incoming requests. */
    val token: String get() = server.token

    private val server: HttpServer

    /**
     * Directory for staging uploaded files, under the injected cache dir so orphans
     * share the app's managed cache lifecycle.
     */
    private val uploadsTempDir: File = File(cacheDir, "gutenbergkit-uploads")

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
     * Relays a media deletion.
     *
     * The editor deletes an attachment when the user removes it, and core deletes
     * an upload's orphan when every `post-process` retry fails. A cross-origin
     * editor cannot issue `DELETE` directly — api-fetch tunnels it as a `POST`
     * carrying `X-HTTP-Method-Override`, which core's CORS allow-list omits, so the
     * browser blocks it at preflight; relaying it here lets the deletion run.
     *
     * Every attachment lives on the configured site — even one a host uploader
     * delivered — so its deletion is relayed to the internal media client there. See
     * the accepted-risk note in the body.
     */
    @Suppress("TooGenericExceptionCaught")
    private suspend fun handleMediaDelete(attachmentId: String, query: String): HttpResponse {
        return try {
            // Relay to the internal media client (the configured site) — every attachment
            // lives there, even one a host uploader delivered. Core issues this only
            // as orphan cleanup after failed recovery, but the relay can't tell that
            // from any other DELETE the WebView sends: a compromised editor script
            // holding the loopback token could force-delete arbitrary media on the
            // configured site. Accepted risk — such a script already has broad write
            // access, and a server-side compromise (a malicious plugin) deletes media
            // directly without the editor, so scoping this with a per-session ledger
            // buys little for the cost.
            relayResponse(internalClient.deleteMedia(attachmentId, query))
        } catch (e: kotlin.coroutines.cancellation.CancellationException) {
            throw e // Never swallow coroutine cancellation.
        } catch (e: Exception) {
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

        // Materialize a temp file only if someone will touch it: a processor that
        // claims this file, or an uploader (which always delivers the file itself).
        // If GutenbergKit will deliver (no uploader) and no processor wants the
        // file, forward the original request body directly, skipping a temp copy of
        // a file nobody will process (e.g. a video handed to an image-only processor).
        val processorWantsFile = processor?.handlesFile(mimeType, filename) == true
        if (uploader == null && !processorWantsFile) {
            return passthroughResponse(request, query)
        }

        val tempFile = writePartToTempFile(filePart)
            ?: return errorResponse(500, "Failed to save file")

        return processAndRespond(request, tempFile, filePart, extraParts, query, processorWantsFile)
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
     *
     * The relayed body is always WordPress REST JSON — an attachment, or a
     * `{code, message, data}` error — so the response is always `application/json`.
     * The relayed headers are a content-type-free allowlist (`RELAYABLE_HEADER_NAMES`),
     * so prepending the JSON default never collides with them.
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
        extraParts: List<MultipartPart>, query: String, processorWantsFile: Boolean
    ): HttpResponse {
        try {
            val uploadResult = processAndUpload(
                tempFile, filePart.contentType, filePart.filename ?: "upload",
                extraParts, query, processorWantsFile
            )
            val response = when (uploadResult) {
                is UploadResult.Uploaded -> {
                    Log.d(TAG, "Uploaded file to WordPress")
                    uploadResult.response
                }
                is UploadResult.Passthrough -> {
                    // No uploader is set and the processor left the file unmodified —
                    // forward the original request body without re-encoding.
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

    // MARK: - Process + Deliver Pipeline

    private sealed class UploadResult {
        data class Uploaded(val response: MediaUploadResponse) : UploadResult()
        data object Passthrough : UploadResult()
    }

    private suspend fun performPassthroughUpload(request: HttpRequest, query: String): MediaUploadResponse {
        val body = request.body
        val contentType = request.header("Content-Type")
        if (body == null || contentType == null) {
            throw MediaUploadException("Passthrough upload requires a request body and Content-Type")
        }
        return internalClient.passthroughUpload(body, contentType, query)
    }

    private suspend fun processAndUpload(
        file: File, mimeType: String, filename: String,
        extraParts: List<MultipartPart>, query: String, processorWantsFile: Boolean
    ): UploadResult {
        // Transform (resize, transcode, …) if a processor claims the file. Reuse the
        // gate's handlesFile decision from handleUpload rather than asking again — one
        // metadata call per upload, and the admit and transform steps can't disagree.
        val processed = if (processorWantsFile && processor != null) {
            processor.processFile(file, mimeType, filename)
        } else {
            ProcessedProxyFile.Original
        }

        // Resolve the file to upload and its metadata. Processed uses the
        // processor's values verbatim, so a format change is reported to WordPress.
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
            // An uploader owns delivery on the host's own stack and returns the
            // finished attachment JSON (or throws); GutenbergKit relays that as a
            // success and never runs its own recovery behind it.
            uploader?.let { up ->
                // Hand the host the editor's non-file fields (e.g. `post`) and query
                // too, so its own POST can reproduce a native upload — otherwise the
                // attachment is created unattached and `?_embed` is lost.
                val fields = extraParts.map { part ->
                    part.name to String(part.body.readBytes(), Charsets.UTF_8)
                }
                val upload = MediaUpload(targetFile, targetMimeType, targetFilename, fields, query)
                return UploadResult.Uploaded(MediaUploadResponse(201, up.upload(upload)))
            }

            // Unmodified — forward the original request body directly, skipping
            // multipart re-encoding.
            if (processed is ProcessedProxyFile.Original) {
                return UploadResult.Passthrough
            }

            val result = internalClient.upload(targetFile, targetMimeType, targetFilename, extraParts, query)
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
internal open class InternalMediaClient(
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
