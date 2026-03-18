package org.wordpress.gutenberg

import android.util.Log
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.RequestBody.Companion.asRequestBody
import org.wordpress.gutenberg.http.ParsedHTTPRequest
import java.io.File
import java.util.UUID

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
 * A lightweight local HTTP server that receives file uploads from the WebView
 * and routes them through the native media processing pipeline.
 *
 * Wraps [HttpServer] to provide a media-upload-specific API.
 */
internal class MediaUploadServer(
    private val uploadDelegate: MediaUploadDelegate?,
    private val defaultUploader: DefaultMediaUploader?,
    private val cacheDir: File? = null
) {
    // requiresAuthentication = false because HttpServer checks auth on every request,
    // including CORS preflight (OPTIONS). We handle auth in the handler ourselves,
    // skipping it for OPTIONS so the browser's preflight succeeds.
    // We use X-Upload-Token rather than Proxy-Authorization because WebKit's fetch()
    // treats Proxy-Authorization as a forbidden header and silently strips it.
    private val httpServer = HttpServer(
        name = "media-upload",
        externallyAccessible = false,
        requiresAuthentication = false,
        maxBodySize = 250L * 1024 * 1024,
        cacheDir = cacheDir,
        handler = { request -> handleRequest(request) }
    )

    /** The port the server is listening on. */
    val port: Int get() = httpServer.port

    /** Per-session auth token for validating incoming requests. */
    val token: String get() = httpServer.token

    init {
        httpServer.start()
        Log.i(TAG, "Upload server started on port $port")
    }

    /** Stops the server and releases resources. */
    fun stop() {
        httpServer.stop()
        Log.i(TAG, "Upload server stopped")
    }

    private suspend fun handleRequest(request: HttpRequest): HttpResponse {
        // CORS preflight — exempt from auth so the browser's OPTIONS request succeeds.
        if (request.method == "OPTIONS") {
            return HttpResponse(204, corsHeaders, ByteArray(0))
        }

        // Auth check for all non-OPTIONS requests.
        if (request.header("X-Upload-Token") != httpServer.token) {
            return HttpResponse(
                status = 401,
                headers = corsHeaders + mapOf("Content-Type" to "text/plain"),
                body = "Unauthorized".toByteArray()
            )
        }

        // Route
        if (request.method != "POST" || request.target != "/upload") {
            return HttpResponse(
                status = 404,
                headers = corsHeaders + mapOf("Content-Type" to "text/plain"),
                body = "Not found".toByteArray()
            )
        }

        return handleUpload(request)
    }

    private suspend fun handleUpload(request: HttpRequest): HttpResponse {
        // Parse multipart body using ParsedHTTPRequest.multipartParts()
        val parsed = ParsedHTTPRequest(
            method = request.method,
            target = request.target,
            httpVersion = "HTTP/1.1",
            headers = request.headers,
            body = request.body,
            isComplete = true
        )

        val parts = try {
            parsed.multipartParts()
        } catch (e: Exception) {
            Log.e(TAG, "Multipart parse failed", e)
            return HttpResponse(
                status = 400,
                headers = corsHeaders + mapOf("Content-Type" to "text/plain"),
                body = "Expected multipart/form-data".toByteArray()
            )
        }

        val filePart = parts.firstOrNull { it.filename != null } ?: run {
            Log.e(TAG, "No file found in multipart request")
            return HttpResponse(
                status = 400,
                headers = corsHeaders + mapOf("Content-Type" to "text/plain"),
                body = "No file found in request".toByteArray()
            )
        }

        val filename = filePart.filename!!
        val mimeType = filePart.contentType

        // Sanitize the filename to prevent path traversal from malicious Content-Disposition values.
        val safeFilename = File(filename).name.replace(Regex("[/\\\\]"), "").ifEmpty { "upload" }
        val tempDir = File(System.getProperty("java.io.tmpdir"), "gutenbergkit-uploads").apply { mkdirs() }
        val tempFile = File(tempDir, "${UUID.randomUUID()}-$safeFilename")
        try {
            tempFile.writeBytes(filePart.body.readBytes())
        } catch (e: Exception) {
            Log.e(TAG, "Failed to write upload to disk", e)
            return HttpResponse(
                status = 500,
                headers = corsHeaders + mapOf("Content-Type" to "text/plain"),
                body = "Failed to save file".toByteArray()
            )
        }

        // Process and upload
        var processedFile: File? = null
        try {
            val processed = uploadDelegate?.processFile(tempFile, mimeType) ?: tempFile
            processedFile = processed
            val result = uploadDelegate?.uploadFile(processed, mimeType, filename)
                ?: defaultUploader?.upload(processed, mimeType, filename)
                ?: throw IllegalStateException("No upload delegate or default uploader configured")

            val json = org.json.JSONObject().apply {
                put("id", result.id)
                put("url", result.url)
                put("alt", result.alt)
                put("caption", result.caption)
                put("title", result.title)
                put("mime", result.mime)
                put("type", result.type)
                result.width?.let { put("width", it) }
                result.height?.let { put("height", it) }
            }.toString()

            return HttpResponse(
                status = 200,
                headers = corsHeaders + mapOf("Content-Type" to "application/json"),
                body = json.toByteArray()
            )
        } catch (e: Exception) {
            Log.e(TAG, "Upload processing failed", e)
            return HttpResponse(
                status = 500,
                headers = corsHeaders + mapOf("Content-Type" to "text/plain"),
                body = (e.message ?: "Upload failed").toByteArray()
            )
        } finally {
            tempFile.delete()
            processedFile?.let { if (it != tempFile) it.delete() }
        }
    }

    companion object {
        private const val TAG = "MediaUploadServer"

        private val corsHeaders = mapOf(
            "Access-Control-Allow-Origin" to "*",
            "Access-Control-Allow-Methods" to "POST, OPTIONS",
            "Access-Control-Allow-Headers" to "X-Upload-Token, Authorization, Content-Type",
            "Access-Control-Max-Age" to "86400"
        )
    }
}

/**
 * Uploads files to the WordPress REST API using OkHttp.
 */
internal open class DefaultMediaUploader(
    private val httpClient: okhttp3.OkHttpClient,
    private val siteApiRoot: String,
    private val authHeader: String
) {
    open suspend fun upload(file: File, mimeType: String, filename: String): MediaUploadResult {
        val mediaType = mimeType.toMediaType()
        val requestBody = okhttp3.MultipartBody.Builder()
            .setType(okhttp3.MultipartBody.FORM)
            .addFormDataPart("file", filename, file.asRequestBody(mediaType))
            .build()

        val request = okhttp3.Request.Builder()
            .url("${siteApiRoot}wp/v2/media")
            .addHeader("Authorization", authHeader)
            .post(requestBody)
            .build()

        val response = httpClient.newCall(request).execute()
        if (!response.isSuccessful) {
            throw RuntimeException("Upload failed (${response.code}): ${response.body?.string() ?: response.message}")
        }

        val responseBody = response.body?.string()
            ?: throw RuntimeException("Empty response body from WordPress")
        val json = try {
            org.json.JSONObject(responseBody)
        } catch (e: org.json.JSONException) {
            throw RuntimeException("WordPress returned unexpected response: ${responseBody.take(500)}", e)
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
