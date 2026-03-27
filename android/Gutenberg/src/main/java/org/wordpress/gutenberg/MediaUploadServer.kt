package org.wordpress.gutenberg

import android.util.Log
import org.wordpress.gutenberg.http.HeaderValue
import org.wordpress.gutenberg.http.MultipartPart
import org.wordpress.gutenberg.http.MultipartParseException
import java.io.File
import java.io.IOException
import java.util.UUID
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.RequestBody.Companion.asRequestBody

/**
 * Result of a successful media upload to the remote WordPress server.
 *
 * Matches the format expected by Gutenberg's `onFileChange` callback.
 */
data class MediaUploadResult(
    val id: Int,
    val url: String,
    val alt: String = "",
    val caption: String = "",
    val title: String,
    val mime: String,
    val type: String,
    val width: Int? = null,
    val height: Int? = null
)

/**
 * Interface for customizing media upload behavior.
 *
 * The native host app can provide an implementation to resize images,
 * transcode video, or use its own upload service.
 */
interface MediaUploadDelegate {
    /**
     * Process a file before upload (e.g., resize image, transcode video).
     * Return the path of the processed file, or the original path for passthrough.
     */
    suspend fun processFile(file: File, mimeType: String): File = file

    /**
     * Upload a processed file to the remote WordPress site.
     * Return the Gutenberg-compatible media result, or null to use the default uploader.
     */
    suspend fun uploadFile(file: File, mimeType: String, filename: String): MediaUploadResult? = null
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
    cacheDir: File? = null
) {
    /** The port the server is listening on. */
    val port: Int get() = server.port

    /** Per-session auth token for validating incoming requests. */
    val token: String get() = server.token

    private val server: HttpServer

    init {
        server = HttpServer(
            name = "media-upload",
            externallyAccessible = false,
            requiresAuthentication = true,
            cacheDir = cacheDir,
            handler = { request -> handleRequest(request) }
        )
        server.start()
    }

    /** Stops the server and releases resources. */
    fun stop() {
        server.stop()
    }

    // MARK: - Request Handling

    private suspend fun handleRequest(request: HttpRequest): HttpResponse {
        // CORS preflight — the library exempts OPTIONS from auth, so this is
        // reached without a token.
        if (request.method.uppercase() == "OPTIONS") {
            return corsPreflightResponse()
        }

        // Route: only POST /upload is handled.
        if (request.method.uppercase() != "POST" || request.target != "/upload") {
            return errorResponse(404, "Not found")
        }

        return handleUpload(request)
    }

    private suspend fun handleUpload(request: HttpRequest): HttpResponse {
        val filePart = parseFilePart(request)
            ?: return errorResponse(400, "Expected multipart/form-data with a file")

        val tempFile = writePartToTempFile(filePart)
            ?: return errorResponse(500, "Failed to save file")

        return processAndRespond(tempFile, filePart)
    }

    private fun parseFilePart(request: HttpRequest): MultipartPart? {
        val contentType = request.header("Content-Type") ?: return null
        val boundary = HeaderValue.extractParameter("boundary", contentType) ?: return null
        val body = request.body ?: return null

        val parts = try {
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
            return null
        }

        return parts.firstOrNull { it.filename != null }
    }

    private fun writePartToTempFile(filePart: MultipartPart): File? {
        val filename = sanitizeFilename(filePart.filename ?: "upload")
        val tempDir = File(System.getProperty("java.io.tmpdir"), "gutenbergkit-uploads").apply { mkdirs() }
        val tempFile = File(tempDir, "${UUID.randomUUID()}-$filename")

        return try {
            filePart.body.inputStream().use { input ->
                tempFile.outputStream().use { output ->
                    input.copyTo(output)
                }
            }
            tempFile
        } catch (e: IOException) {
            Log.e(TAG, "Failed to write upload to disk", e)
            null
        }
    }

    private suspend fun processAndRespond(tempFile: File, filePart: MultipartPart): HttpResponse {
        var processedFile: File? = null
        try {
            val (media, processed) = processAndUpload(
                tempFile, filePart.contentType, filePart.filename ?: "upload"
            )
            processedFile = processed
            return successResponse(media)
        } catch (e: MediaUploadException) {
            Log.e(TAG, "Upload processing failed", e)
            return errorResponse(500, e.message ?: "Upload failed")
        } finally {
            tempFile.delete()
            processedFile?.let { if (it != tempFile) it.delete() }
        }
    }

    // MARK: - Delegate Pipeline

    private suspend fun processAndUpload(
        file: File, mimeType: String, filename: String
    ): Pair<MediaUploadResult, File> {
        val processedFile = uploadDelegate?.processFile(file, mimeType) ?: file

        val result = uploadDelegate?.uploadFile(processedFile, mimeType, filename)
            ?: defaultUploader?.upload(processedFile, mimeType, filename)
            ?: error("No upload delegate or default uploader configured")

        return Pair(result, processedFile)
    }

    // MARK: - Response Building

    private val corsHeaders: Map<String, String> = mapOf(
        "Access-Control-Allow-Origin" to "*",
        "Access-Control-Allow-Headers" to "Relay-Authorization, Content-Type"
    )

    private fun corsPreflightResponse(): HttpResponse = HttpResponse(
        status = 204,
        headers = mapOf(
            "Access-Control-Allow-Origin" to "*",
            "Access-Control-Allow-Methods" to "POST, OPTIONS",
            "Access-Control-Allow-Headers" to "Relay-Authorization, Content-Type",
            "Access-Control-Max-Age" to "86400"
        ),
        body = ByteArray(0)
    )

    private fun successResponse(media: MediaUploadResult): HttpResponse {
        val json = org.json.JSONObject().apply {
            put("id", media.id)
            put("url", media.url)
            put("alt", media.alt)
            put("caption", media.caption)
            put("title", media.title)
            put("mime", media.mime)
            put("type", media.type)
            media.width?.let { put("width", it) }
            media.height?.let { put("height", it) }
        }.toString()

        return HttpResponse(
            status = 200,
            headers = corsHeaders + mapOf("Content-Type" to "application/json"),
            body = json.toByteArray()
        )
    }

    private fun errorResponse(status: Int, body: String): HttpResponse = HttpResponse(
        status = status,
        headers = corsHeaders + mapOf("Content-Type" to "text/plain"),
        body = body.toByteArray()
    )

    // MARK: - Helpers

    /** Sanitizes a filename to prevent path traversal. */
    private fun sanitizeFilename(name: String): String {
        val safe = File(name).name.replace(Regex("[/\\\\]"), "")
        return safe.ifEmpty { "upload" }
    }

    companion object {
        private const val TAG = "MediaUploadServer"
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
    open suspend fun upload(file: File, mimeType: String, filename: String): MediaUploadResult {
        val mediaType = mimeType.toMediaType()
        val requestBody = okhttp3.MultipartBody.Builder()
            .setType(okhttp3.MultipartBody.FORM)
            .addFormDataPart("file", filename, file.asRequestBody(mediaType))
            .build()

        // When a site API namespace is configured (e.g. "sites/12345/"), insert
        // it into the media endpoint path so the request reaches the correct site.
        val namespace = siteApiNamespace.firstOrNull() ?: ""
        val request = okhttp3.Request.Builder()
            .url("${siteApiRoot}wp/v2/${namespace}media")
            .addHeader("Authorization", authHeader)
            .post(requestBody)
            .build()

        val response = httpClient.newCall(request).execute()
        val body = response.body?.string()

        if (!response.isSuccessful) {
            // Try to extract the human-readable message from a WordPress error
            // response ({"code":"...","message":"..."}) before falling back to
            // the raw body.
            val errorMessage = body?.let {
                try { org.json.JSONObject(it).optString("message", null) } catch (_: org.json.JSONException) { null }
            } ?: body ?: response.message
            throw MediaUploadException(errorMessage)
        }

        if (body == null) {
            throw MediaUploadException("Empty response body from server")
        }

        return parseMediaResponse(body)
    }

    private fun parseMediaResponse(body: String): MediaUploadResult {
        val json = try {
            org.json.JSONObject(body)
        } catch (e: org.json.JSONException) {
            throw MediaUploadException("Unexpected response: ${body.take(500)}", e)
        }
        val mediaDetails = json.optJSONObject("media_details")
        return MediaUploadResult(
            id = json.getInt("id"),
            url = json.getString("source_url"),
            alt = json.optString("alt_text", ""),
            caption = json.optJSONObject("caption")?.optString("rendered", "") ?: "",
            title = json.getJSONObject("title").getString("rendered"),
            mime = json.getString("mime_type"),
            type = json.getString("media_type"),
            width = mediaDetails?.optInt("width"),
            height = mediaDetails?.optInt("height")
        )
    }
}
