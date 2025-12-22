package org.wordpress.gutenberg.stores

import android.annotation.SuppressLint
import android.util.Log
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import org.wordpress.gutenberg.model.EditorCachePolicy
import org.wordpress.gutenberg.model.http.EditorHTTPHeaders
import org.wordpress.gutenberg.model.http.EditorHttpMethod
import org.wordpress.gutenberg.model.http.EditorURLResponse
import java.io.File
import java.security.MessageDigest
import java.util.Date
import java.util.concurrent.locks.ReentrantReadWriteLock
import kotlin.concurrent.read
import kotlin.concurrent.write

/**
 * A URL-based cache for storing HTTP responses keyed by URL and HTTP method.
 *
 * Responses are stored on disk and survive process termination. Responses are keyed by both
 * URL and HTTP method, so GET and OPTIONS requests to the same URL are stored independently.
 */
class EditorURLCache(
    private val cacheRoot: File,
    private val cachePolicy: EditorCachePolicy = EditorCachePolicy.Always
) {
    private val json = Json { ignoreUnknownKeys = true }
    private val lock = ReentrantReadWriteLock()

    companion object {
        private const val TAG = "EditorURLCache"
    }

    init {
        cacheRoot.mkdirs()
    }

    /**
     * Stores a response for the given URL and HTTP method.
     *
     * If a response already exists for this URL and method combination, it will be overwritten.
     *
     * @param response The response to store.
     * @param url The URL to associate with the response.
     * @param httpMethod The HTTP method to associate with the response.
     */
    fun store(response: EditorURLResponse, url: String, httpMethod: EditorHttpMethod) {
        store(response, url, httpMethod, Date())
    }

    internal fun store(
        response: EditorURLResponse,
        url: String,
        httpMethod: EditorHttpMethod,
        currentDate: Date
    ) = lock.write {
        __store(response, url, httpMethod, currentDate)
    }

    /**
     * Stores the contents of a file as a cached response for the given URL and HTTP method.
     *
     * @param file The file whose contents should be stored.
     * @param headers The HTTP headers to associate with the response.
     * @param url The URL to associate with the response.
     * @param httpMethod The HTTP method to associate with the response.
     */
    fun store(
        file: File,
        headers: EditorHTTPHeaders,
        url: String,
        httpMethod: EditorHttpMethod
    ) {
        store(file, headers, url, httpMethod, Date())
    }

    internal fun store(
        file: File,
        headers: EditorHTTPHeaders,
        url: String,
        httpMethod: EditorHttpMethod,
        currentDate: Date
    ) = lock.write {
        val data = file.readText()
        val response = EditorURLResponse(data = data, responseHeaders = headers)
        __store(response, url, httpMethod, currentDate)
    }

    private fun __store(
        response: EditorURLResponse,
        url: String,
        httpMethod: EditorHttpMethod,
        currentDate: Date
    ) {
        val cacheKey = buildCacheKey(url, httpMethod)
        val cacheFile = File(cacheRoot, cacheKey)

        val entry = CachedEntry(
            data = response.data,
            headers = response.responseHeaders.dictionaryValue,
            storageDate = currentDate.time
        )

        val encodedEntry = json.encodeToString(entry)
        cacheFile.writeText(encodedEntry)
        Log.d(TAG, "Wrote cache entry: file=${cacheFile.absolutePath}, size=${encodedEntry.length} bytes, url=$url")
    }

    /**
     * Checks whether a cached response exists for the given URL and HTTP method.
     *
     * @param url The URL to check.
     * @param httpMethod The HTTP method to check.
     * @return `true` if a cached response exists, `false` otherwise.
     */
    fun hasResponse(url: String, httpMethod: EditorHttpMethod): Boolean {
        return hasResponse(url, httpMethod, Date())
    }

    internal fun hasResponse(url: String, httpMethod: EditorHttpMethod, currentDate: Date): Boolean {
        return getResponse(url, httpMethod, currentDate) != null
    }

    /**
     * Retrieves the cached response for the given URL and HTTP method.
     *
     * @param url The URL to look up.
     * @param httpMethod The HTTP method to look up.
     * @return The cached response, or `null` if no response is cached or the cache has expired.
     */
    fun getResponse(url: String, httpMethod: EditorHttpMethod): EditorURLResponse? {
        return getResponse(url, httpMethod, Date())
    }

    internal fun getResponse(
        url: String,
        httpMethod: EditorHttpMethod,
        currentDate: Date
    ): EditorURLResponse? = lock.read {
        val cacheKey = buildCacheKey(url, httpMethod)
        val cacheFile = File(cacheRoot, cacheKey)

        if (!cacheFile.exists()) {
            return@read null
        }

        runCatching {
            val entry = json.decodeFromString<CachedEntry>(cacheFile.readText())
            val storageDate = Date(entry.storageDate)

            if (!cachePolicy.allowsResponseWith(storageDate, currentDate)) {
                return@read null
            }

            EditorURLResponse(
                data = entry.data,
                responseHeaders = EditorHTTPHeaders(entry.headers)
            )
        }.getOrNull()
    }

    /**
     * Removes all cached responses.
     */
    fun purge() = lock.write {
        cacheRoot.listFiles()?.forEach { it.delete() }
    }

    /**
     * Removes cached responses that are no longer valid according to the cache policy.
     *
     * This method iterates through all cached entries and deletes those whose storage date
     * is no longer allowed by the current cache policy. Use this periodically to prevent
     * unbounded cache growth.
     *
     * @return The number of entries removed.
     */
    fun clean(): Int {
        return clean(Date())
    }

    internal fun clean(currentDate: Date): Int = lock.write {
        var removedCount = 0

        cacheRoot.listFiles()?.forEach { file ->
            if (!file.isFile) return@forEach

            val shouldRemove = runCatching {
                val entry = json.decodeFromString<CachedEntry>(file.readText())
                val storageDate = Date(entry.storageDate)
                !cachePolicy.allowsResponseWith(storageDate, currentDate)
            }.getOrDefault(true) // Remove entries that can't be parsed

            if (shouldRemove) {
                if (file.delete()) {
                    removedCount++
                    Log.d(TAG, "Cleaned expired cache entry: ${file.name}")
                }
            }
        }

        if (removedCount > 0) {
            Log.d(TAG, "Cache cleanup complete: removed $removedCount entries")
        }

        removedCount
    }

    /**
     * Builds a unique cache key for the given URL and HTTP method combination.
     */
    private fun buildCacheKey(url: String, httpMethod: EditorHttpMethod): String {
        val input = "$httpMethod:$url"
        val digest = MessageDigest.getInstance("SHA-256")
        val hashBytes = digest.digest(input.toByteArray())
        return hashBytes.joinToString("") { "%02x".format(it) }
    }

    /**
     * Internal structure for persisting cached responses.
     */
    @SuppressLint("UnsafeOptInUsageError")
    @Serializable
    private data class CachedEntry(
        val data: String,
        val headers: Map<String, String>,
        val storageDate: Long
    )
}
