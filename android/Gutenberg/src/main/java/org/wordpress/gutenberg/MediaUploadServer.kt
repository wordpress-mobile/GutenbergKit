package org.wordpress.gutenberg

import android.util.Log
import kotlinx.coroutines.Dispatchers
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.RequestBody.Companion.asRequestBody
import kotlinx.coroutines.runBlocking
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.InputStream
import java.net.InetAddress
import java.net.ServerSocket
import java.net.Socket
import java.util.UUID
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

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
    val type: String
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
 * Binds to `127.0.0.1` on a random available port and validates all requests
 * using a per-session Bearer token.
 */
internal class MediaUploadServer(
    private val uploadDelegate: MediaUploadDelegate?,
    private val defaultUploader: DefaultMediaUploader?
) {
    /** The port the server is listening on. */
    val port: Int

    /** Per-session auth token for validating incoming requests. */
    val token: String = UUID.randomUUID().toString()

    private val serverSocket: ServerSocket
    private val executor: ExecutorService = Executors.newCachedThreadPool()
    @Volatile private var running = true

    init {
        serverSocket = ServerSocket(0, 50, InetAddress.getLoopbackAddress())
        port = serverSocket.localPort

        executor.submit {
            while (running) {
                try {
                    val socket = serverSocket.accept()
                    executor.submit { handleConnection(socket) }
                } catch (e: Exception) {
                    if (running) {
                        Log.e(TAG, "Error accepting connection", e)
                    }
                }
            }
        }

        Log.i(TAG, "Upload server started on port $port")
    }

    /** Stops the server and releases resources. */
    fun stop() {
        running = false
        try {
            serverSocket.close()
        } catch (_: Exception) {}
        executor.shutdownNow()
        Log.i(TAG, "Upload server stopped")
    }

    private fun handleConnection(socket: Socket) {
        try {
            socket.use { sock ->
                val input = sock.getInputStream()
                val requestData = readHttpRequest(input) ?: run {
                    sendResponse(sock, 400, "Bad Request", "Malformed HTTP request")
                    return
                }

                // CORS preflight
                if (requestData.method == "OPTIONS") {
                    sendCORSResponse(sock)
                    return
                }

                // Auth validation
                val expectedAuth = "Bearer $token"
                if (requestData.headers["authorization"] != expectedAuth) {
                    sendResponse(sock, 401, "Unauthorized", "Invalid or missing token")
                    return
                }

                // Route
                if (requestData.method != "POST" || requestData.path != "/upload") {
                    sendResponse(sock, 404, "Not Found", "Not found")
                    return
                }

                handleUpload(sock, requestData)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error handling connection", e)
        }
    }

    private fun handleUpload(socket: Socket, request: HttpRequestData) {
        val contentType = request.headers["content-type"] ?: run {
            sendResponse(socket, 400, "Bad Request", "Expected multipart/form-data")
            return
        }

        if (!contentType.contains("multipart/form-data")) {
            sendResponse(socket, 400, "Bad Request", "Expected multipart/form-data")
            return
        }

        val boundary = extractBoundary(contentType) ?: run {
            sendResponse(socket, 400, "Bad Request", "Missing boundary")
            return
        }

        val file = parseMultipartFile(request.body, boundary) ?: run {
            sendResponse(socket, 400, "Bad Request", "No file found in request")
            return
        }

        // Write to temp file
        val tempDir = File(System.getProperty("java.io.tmpdir"), "gutenbergkit-uploads").apply { mkdirs() }
        val tempFile = File(tempDir, file.filename)
        try {
            tempFile.writeBytes(file.data)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to write upload to disk", e)
            sendResponse(socket, 500, "Internal Server Error", "Failed to save file")
            return
        }

        // Process and upload
        try {
            val result = runBlocking(Dispatchers.IO) {
                processAndUpload(tempFile, file.mimeType, file.filename)
            }

            val json = """{"id":${result.id},"url":"${result.url.escapeJson()}","alt":"${result.alt.escapeJson()}","caption":"${result.caption.escapeJson()}","title":"${result.title.escapeJson()}","mime":"${result.mime.escapeJson()}","type":"${result.type.escapeJson()}"}"""
            sendResponse(socket, 200, "OK", json, "application/json")
        } catch (e: Exception) {
            Log.e(TAG, "Upload processing failed", e)
            sendResponse(socket, 500, "Internal Server Error", e.message ?: "Upload failed")
        }
    }

    private suspend fun processAndUpload(file: File, mimeType: String, filename: String): MediaUploadResult {
        val processedFile = uploadDelegate?.processFile(file, mimeType) ?: file
        return uploadDelegate?.uploadFile(processedFile, mimeType, filename)
            ?: defaultUploader?.upload(processedFile, mimeType, filename)
            ?: throw IllegalStateException("No upload delegate or default uploader configured")
    }

    // MARK: - HTTP Parsing

    private data class HttpRequestData(
        val method: String,
        val path: String,
        val headers: Map<String, String>,
        val body: ByteArray
    )

    private fun readHttpRequest(input: InputStream): HttpRequestData? {
        val headerBytes = ByteArrayOutputStream()
        var prev = 0
        var prevPrev = 0
        var prevPrevPrev = 0

        // Read until we find \r\n\r\n
        while (true) {
            val b = input.read()
            if (b == -1) break
            headerBytes.write(b)

            if (prevPrevPrev == '\r'.code && prevPrev == '\n'.code && prev == '\r'.code && b == '\n'.code) {
                break
            }
            prevPrevPrev = prevPrev
            prevPrev = prev
            prev = b
        }

        val headerString = headerBytes.toString("UTF-8")
        val lines = headerString.split("\r\n")
        if (lines.isEmpty()) return null

        val requestLine = lines[0].split(" ")
        if (requestLine.size < 2) return null

        val method = requestLine[0]
        val path = requestLine[1]

        val headers = mutableMapOf<String, String>()
        for (line in lines.drop(1)) {
            val colonIndex = line.indexOf(':')
            if (colonIndex > 0) {
                val key = line.substring(0, colonIndex).trim().lowercase()
                val value = line.substring(colonIndex + 1).trim()
                headers[key] = value
            }
        }

        // Read body based on Content-Length
        val contentLength = headers["content-length"]?.toIntOrNull() ?: 0
        val body = if (contentLength > 0) {
            val bodyBytes = ByteArray(contentLength)
            var totalRead = 0
            while (totalRead < contentLength) {
                val read = input.read(bodyBytes, totalRead, contentLength - totalRead)
                if (read == -1) break
                totalRead += read
            }
            bodyBytes
        } else {
            ByteArray(0)
        }

        return HttpRequestData(method, path, headers, body)
    }

    private data class UploadedFile(
        val filename: String,
        val mimeType: String,
        val data: ByteArray
    )

    private fun extractBoundary(contentType: String): String? {
        val idx = contentType.indexOf("boundary=")
        if (idx < 0) return null
        var boundary = contentType.substring(idx + 9)
        if (boundary.startsWith("\"") && boundary.endsWith("\"")) {
            boundary = boundary.substring(1, boundary.length - 1)
        }
        val semiIdx = boundary.indexOf(';')
        if (semiIdx >= 0) boundary = boundary.substring(0, semiIdx)
        return boundary
    }

    private fun parseMultipartFile(data: ByteArray, boundary: String): UploadedFile? {
        val boundaryBytes = "--$boundary".toByteArray()
        val crlfCrlf = "\r\n\r\n".toByteArray()

        // Find boundary positions
        val positions = mutableListOf<Int>()
        var searchFrom = 0
        while (searchFrom < data.size) {
            val pos = indexOf(data, boundaryBytes, searchFrom)
            if (pos < 0) break
            positions.add(pos)
            searchFrom = pos + boundaryBytes.size
        }

        // Each part is between consecutive boundaries
        for (i in 0 until positions.size - 1) {
            val partStart = positions[i] + boundaryBytes.size + 2 // skip boundary + \r\n
            val partEnd = positions[i + 1] - 2 // before \r\n before next boundary

            if (partStart >= partEnd || partStart >= data.size) continue

            val headerEndPos = indexOf(data, crlfCrlf, partStart)
            if (headerEndPos < 0 || headerEndPos >= partEnd) continue

            val headerString = String(data, partStart, headerEndPos - partStart, Charsets.UTF_8)
            if (!headerString.contains("filename=")) continue

            val filename = extractHeaderValue(headerString, "filename") ?: "upload"
            val mimeType = extractContentType(headerString) ?: "application/octet-stream"

            val bodyStart = headerEndPos + crlfCrlf.size
            val bodyData = data.copyOfRange(bodyStart, partEnd)

            return UploadedFile(filename, mimeType, bodyData)
        }

        return null
    }

    private fun indexOf(data: ByteArray, pattern: ByteArray, from: Int): Int {
        outer@ for (i in from..data.size - pattern.size) {
            for (j in pattern.indices) {
                if (data[i + j] != pattern[j]) continue@outer
            }
            return i
        }
        return -1
    }

    private fun extractHeaderValue(headers: String, key: String): String? {
        val idx = headers.indexOf("$key=\"")
        if (idx < 0) return null
        val start = idx + key.length + 2
        val end = headers.indexOf('"', start)
        if (end < 0) return null
        return headers.substring(start, end)
    }

    private fun extractContentType(headers: String): String? {
        for (line in headers.split("\r\n")) {
            if (line.lowercase().startsWith("content-type:")) {
                return line.substringAfter(':').trim()
            }
        }
        return null
    }

    // MARK: - HTTP Response Building

    private fun sendCORSResponse(socket: Socket) {
        val response = buildString {
            append("HTTP/1.1 204 No Content\r\n")
            append("Access-Control-Allow-Origin: *\r\n")
            append("Access-Control-Allow-Methods: POST, OPTIONS\r\n")
            append("Access-Control-Allow-Headers: Authorization, Content-Type\r\n")
            append("Access-Control-Max-Age: 86400\r\n")
            append("Content-Length: 0\r\n")
            append("\r\n")
        }
        socket.getOutputStream().write(response.toByteArray())
        socket.getOutputStream().flush()
    }

    private fun sendResponse(socket: Socket, status: Int, statusText: String, body: String, contentType: String = "text/plain") {
        val bodyBytes = body.toByteArray()
        val response = buildString {
            append("HTTP/1.1 $status $statusText\r\n")
            append("Access-Control-Allow-Origin: *\r\n")
            append("Access-Control-Allow-Headers: Authorization, Content-Type\r\n")
            append("Content-Type: $contentType\r\n")
            append("Content-Length: ${bodyBytes.size}\r\n")
            append("\r\n")
        }
        val output = socket.getOutputStream()
        output.write(response.toByteArray())
        output.write(bodyBytes)
        output.flush()
    }

    private fun String.escapeJson(): String =
        replace("\\", "\\\\").replace("\"", "\\\"").replace("\n", "\\n").replace("\r", "\\r")

    companion object {
        private const val TAG = "MediaUploadServer"
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

        val json = org.json.JSONObject(response.body!!.string())
        return MediaUploadResult(
            id = json.getInt("id"),
            url = json.getString("source_url"),
            alt = json.optString("alt_text", ""),
            caption = json.optJSONObject("caption")?.optString("rendered", "") ?: "",
            title = json.getJSONObject("title").getString("rendered"),
            mime = json.getString("mime_type"),
            type = json.getString("media_type")
        )
    }
}
