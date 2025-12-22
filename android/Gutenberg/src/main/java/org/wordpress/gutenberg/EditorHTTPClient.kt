package org.wordpress.gutenberg

import android.util.Log
import com.google.gson.Gson
import com.google.gson.JsonSyntaxException
import com.google.gson.annotations.SerializedName
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.Response
import org.wordpress.gutenberg.model.http.EditorHTTPHeaders
import java.io.File
import java.io.IOException
import java.util.concurrent.TimeUnit

/**
 * A protocol for making authenticated HTTP requests to the WordPress REST API.
 */
interface EditorHTTPClientProtocol {
    suspend fun download(url: String, destination: File): EditorHTTPClientDownloadResponse
    suspend fun perform(method: String, url: String): EditorHTTPClientResponse
}

/**
 * A delegate for observing HTTP requests made by the editor.
 *
 * Implement this interface to inspect or log all network requests.
 */
interface EditorHTTPClientDelegate {
    fun didPerformRequest(url: String, method: String, response: Response, data: ByteArray)
}

/**
 * Response from an HTTP request containing body data and response metadata.
 */
data class EditorHTTPClientResponse(
    val data: ByteArray,
    val statusCode: Int,
    val headers: EditorHTTPHeaders
) {
    val stringData: String
        get() = data.toString(Charsets.UTF_8)

    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (other !is EditorHTTPClientResponse) return false
        return data.contentEquals(other.data) && statusCode == other.statusCode && headers == other.headers
    }

    override fun hashCode(): Int {
        var result = data.contentHashCode()
        result = 31 * result + statusCode
        result = 31 * result + headers.hashCode()
        return result
    }
}

/**
 * Response from a download request containing the downloaded file location and response metadata.
 */
data class EditorHTTPClientDownloadResponse(
    val file: File,
    val statusCode: Int,
    val headers: EditorHTTPHeaders
)

/**
 * A WordPress REST API error response.
 */
data class WPError(
    val code: String,
    val message: String
)

/**
 * Errors that can occur during HTTP requests.
 */
sealed class EditorHTTPClientError : Exception() {
    /**
     * The server returned a WordPress-formatted error response.
     */
    data class WPErrorResponse(val error: org.wordpress.gutenberg.WPError) : EditorHTTPClientError() {
        override val message: String
            get() = "${error.code}: ${error.message}"
    }

    /**
     * A file download failed with the given HTTP status code.
     */
    data class DownloadFailed(val statusCode: Int) : EditorHTTPClientError() {
        override val message: String
            get() = "Download failed with status code: $statusCode"
    }

    /**
     * An unexpected error occurred with the given response data and status code.
     */
    data class Unknown(val responseData: ByteArray, val statusCode: Int) : EditorHTTPClientError() {
        override val message: String
            get() = "Unknown error with status code: $statusCode"

        override fun equals(other: Any?): Boolean {
            if (this === other) return true
            if (other !is Unknown) return false
            return responseData.contentEquals(other.responseData) && statusCode == other.statusCode
        }

        override fun hashCode(): Int {
            var result = responseData.contentHashCode()
            result = 31 * result + statusCode
            return result
        }
    }
}

/**
 * An HTTP client for making authenticated requests to the WordPress REST API.
 *
 * This class handles request signing, error parsing, and response validation.
 * All requests are automatically authenticated using the provided authorization header.
 */
class EditorHTTPClient(
    private val authHeader: String,
    private val delegate: EditorHTTPClientDelegate? = null,
    private val requestTimeoutSeconds: Long = 60,
    okHttpClient: OkHttpClient? = null
) : EditorHTTPClientProtocol {

    private val client: OkHttpClient = okHttpClient?.newBuilder()
        ?.callTimeout(requestTimeoutSeconds, TimeUnit.SECONDS)
        ?.build()
        ?: OkHttpClient.Builder()
            .callTimeout(requestTimeoutSeconds, TimeUnit.SECONDS)
            .connectTimeout(requestTimeoutSeconds, TimeUnit.SECONDS)
            .readTimeout(requestTimeoutSeconds, TimeUnit.SECONDS)
            .writeTimeout(requestTimeoutSeconds, TimeUnit.SECONDS)
            .build()

    override suspend fun download(url: String, destination: File): EditorHTTPClientDownloadResponse =
        withContext(Dispatchers.IO) {
            val request = Request.Builder()
                .url(url)
                .addHeader("Authorization", authHeader)
                .get()
                .build()

            val response = client.newCall(request).execute()
            val statusCode = response.code
            val headers = extractHeaders(response)

            if (statusCode !in 200..299) {
                Log.e(TAG, "HTTP error downloading $url: $statusCode")
                throw EditorHTTPClientError.DownloadFailed(statusCode)
            }

            response.body?.let { body ->
                destination.parentFile?.mkdirs()
                destination.outputStream().use { output ->
                    body.byteStream().use { input ->
                        input.copyTo(output)
                    }
                }
                Log.d(TAG, "Downloaded file: file=${destination.absolutePath}, size=${destination.length()} bytes, url=$url")
            } ?: throw EditorHTTPClientError.DownloadFailed(statusCode)

            EditorHTTPClientDownloadResponse(
                file = destination,
                statusCode = statusCode,
                headers = headers
            )
        }

    override suspend fun perform(method: String, url: String): EditorHTTPClientResponse =
        withContext(Dispatchers.IO) {
            // OkHttp requires a body for POST, PUT, PATCH methods
            // GET, HEAD, OPTIONS, DELETE don't require a body
            val requiresBody = method.uppercase() in listOf("POST", "PUT", "PATCH")
            val requestBody = if (requiresBody) "".toRequestBody(null) else null

            val request = Request.Builder()
                .url(url)
                .addHeader("Authorization", authHeader)
                .method(method, requestBody)
                .build()

            val response: Response
            try {
                response = client.newCall(request).execute()
            } catch (e: IOException) {
                throw e
            }

            // Note: This loads the entire response into memory. This is acceptable because
            // this method is only used for WordPress REST API responses (editor settings, post
            // data, themes, etc.) which are expected to be small (KB range). Large assets like
            // JS/CSS files use the download() method which streams directly to disk.
            val data = response.body?.bytes() ?: ByteArray(0)
            val statusCode = response.code
            val headers = extractHeaders(response)

            delegate?.didPerformRequest(url, method, response, data)

            if (statusCode !in 200..299) {
                Log.e(TAG, "HTTP error fetching $url: $statusCode")

                // Try to parse as WordPress error
                val wpError = tryParseWPError(data)
                if (wpError != null) {
                    throw EditorHTTPClientError.WPErrorResponse(wpError)
                }

                throw EditorHTTPClientError.Unknown(data, statusCode)
            }

            EditorHTTPClientResponse(
                data = data,
                statusCode = statusCode,
                headers = headers
            )
        }

    private fun extractHeaders(response: Response): EditorHTTPHeaders {
        val headerMap = mutableMapOf<String, String>()
        response.headers.forEach { (name, value) ->
            headerMap[name] = value
        }
        return EditorHTTPHeaders(headerMap)
    }

    private fun tryParseWPError(data: ByteArray): WPError? {
        return try {
            val json = data.toString(Charsets.UTF_8)
            val parsed = gson.fromJson(json, WPErrorJson::class.java)
            // Both code and message must be present (non-null) to be a valid WP error
            // Empty strings are accepted to match Swift behavior
            if (parsed.code != null && parsed.message != null) {
                WPError(parsed.code, parsed.message)
            } else {
                null
            }
        } catch (e: JsonSyntaxException) {
            null
        } catch (e: Exception) {
            null
        }
    }

    /**
     * Internal data class for parsing WordPress error JSON responses.
     */
    private data class WPErrorJson(
        @SerializedName("code") val code: String?,
        @SerializedName("message") val message: String?,
        @SerializedName("data") val data: Any? = null
    )

    companion object {
        private const val TAG = "EditorHTTPClient"
        private val gson = Gson()
    }
}
