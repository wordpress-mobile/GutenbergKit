package org.wordpress.gutenberg

import android.content.Context
import android.net.Uri
import android.provider.OpenableColumns
import android.util.Log
import android.webkit.MimeTypeMap
import java.io.File
import java.io.FileOutputStream
import java.io.IOException

/**
 * Utility class for caching files from content providers to avoid ERR_UPLOAD_FILE_CHANGED errors
 * in WebView when uploading files from cloud storage providers.
 */
object FileCache {
    private const val TAG = "FileCache"
    private const val CACHE_DIR_NAME = "gutenberg_file_uploads"
    private const val BUFFER_SIZE = 8192
    const val DEFAULT_MAX_FILE_SIZE = 100 * 1024 * 1024L // 100MB in bytes

    /**
     * Copies a file from a content URI to the app's cache directory.
     *
     * This is necessary to work around Android WebView issues with uploading files from
     * cloud storage providers (Google Drive, Dropbox, etc.) which can trigger
     * ERR_UPLOAD_FILE_CHANGED errors due to streaming content or changing metadata.
     *
     * @param context Android context
     * @param uri The content:// URI to copy
     * @param maxSizeBytes Maximum file size in bytes (default: 100MB)
     * @return URI of the cached file, or null if the copy failed or file exceeds size limit
     */
    fun copyToCache(context: Context, uri: Uri, maxSizeBytes: Long = DEFAULT_MAX_FILE_SIZE): Uri? {
        // Check file size before attempting to copy
        val fileSize = getFileSize(context, uri)
        if (fileSize != null && fileSize > maxSizeBytes) {
            val fileSizeMB = fileSize / (1024 * 1024)
            val maxSizeMB = maxSizeBytes / (1024 * 1024)
            Log.w(TAG, "File exceeds maximum size limit: uri=$uri, size=${fileSizeMB}MB, limit=${maxSizeMB}MB")
            return null
        }

        if (fileSize != null) {
            Log.d(TAG, "File size check passed: uri=$uri, size=${fileSize / (1024 * 1024)}MB")
        } else {
            Log.w(TAG, "Unable to determine file size, proceeding with copy attempt: uri=$uri")
        }

        val cacheDir = File(context.cacheDir, CACHE_DIR_NAME)
        if (!cacheDir.exists()) {
            cacheDir.mkdirs()
        }

        val fileName = getFileName(context, uri) ?: "upload_${System.currentTimeMillis()}"
        val extension = getFileExtension(context, uri)
        val mimeType = context.contentResolver.getType(uri)
        val fileNameWithExtension = if (extension != null && !fileName.endsWith(".$extension")) {
            "$fileName.$extension"
        } else {
            fileName
        }

        // Create a unique file to avoid conflicts
        val uniqueFileName = "${System.currentTimeMillis()}_$fileNameWithExtension"
        val cachedFile = File(cacheDir, uniqueFileName)

        Log.d(TAG, "Attempting to cache file: uri=$uri, fileName=$fileName, mimeType=$mimeType, destination=$cachedFile")

        return try {
            var totalBytesRead = 0L
            context.contentResolver.openInputStream(uri)?.use { input ->
                FileOutputStream(cachedFile).use { output ->
                    val buffer = ByteArray(BUFFER_SIZE)
                    var bytesRead: Int
                    while (input.read(buffer).also { bytesRead = it } != -1) {
                        output.write(buffer, 0, bytesRead)
                        totalBytesRead += bytesRead
                    }
                }
            }
            Log.d(TAG, "Successfully cached file: uri=$uri, cachedFile=$cachedFile, size=$totalBytesRead bytes")
            Uri.fromFile(cachedFile)
        } catch (e: IOException) {
            Log.e(TAG, "Failed to copy file to cache: uri=$uri, error=${e.message}", e)
            // Clean up partial file if copy failed
            if (cachedFile.exists()) {
                cachedFile.delete()
            }
            null
        }
    }

    /**
     * Clears all cached files from previous sessions to prevent storage accumulation.
     *
     * @param context Android context
     */
    fun clearCache(context: Context) {
        val cacheDir = File(context.cacheDir, CACHE_DIR_NAME)
        if (cacheDir.exists() && cacheDir.isDirectory) {
            cacheDir.listFiles()?.forEach { file ->
                file.delete()
            }
        }
    }

    /**
     * Gets the file size from a content URI.
     *
     * Queries the content provider for the file size using OpenableColumns.SIZE.
     * Some content providers may not provide size information, in which case this
     * returns null.
     *
     * @param context Android context
     * @param uri The content URI
     * @return File size in bytes, or null if size cannot be determined
     */
    private fun getFileSize(context: Context, uri: Uri): Long? {
        return try {
            context.contentResolver.query(uri, null, null, null, null)?.use { cursor ->
                if (cursor.moveToFirst()) {
                    val sizeIndex = cursor.getColumnIndex(OpenableColumns.SIZE)
                    if (sizeIndex != -1) {
                        val size = cursor.getLong(sizeIndex)
                        // Some providers return -1 or 0 when size is unknown
                        if (size > 0) size else null
                    } else {
                        null
                    }
                } else {
                    null
                }
            }
        } catch (e: Exception) {
            Log.w(TAG, "Failed to query file size for uri: $uri, error=${e.message}", e)
            null
        }
    }

    /**
     * Retrieves the display name of a file from a content URI.
     *
     * @param context Android context
     * @param uri The content URI
     * @return The file name, or null if it cannot be determined
     */
    private fun getFileName(context: Context, uri: Uri): String? {
        var fileName: String? = null
        context.contentResolver.query(uri, null, null, null, null)?.use { cursor ->
            if (cursor.moveToFirst()) {
                val nameIndex = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                if (nameIndex != -1) {
                    fileName = cursor.getString(nameIndex)
                }
            }
        }
        return fileName
    }

    /**
     * Gets the file extension from a content URI by checking its MIME type.
     *
     * @param context Android context
     * @param uri The content URI
     * @return The file extension (without the dot), or null if it cannot be determined
     */
    private fun getFileExtension(context: Context, uri: Uri): String? {
        val mimeType = context.contentResolver.getType(uri)
        return mimeType?.let { MimeTypeMap.getSingleton().getExtensionFromMimeType(it) }
    }

    /**
     * Checks if a URI comes from a known-safe local content provider.
     *
     * These providers serve local files that won't change during upload, so copying
     * them to cache is unnecessary. This allow list includes only Android's built-in
     * local content providers.
     *
     * @param uri The content URI to check
     * @return true if the URI is from a known-safe local provider
     */
    fun isKnownSafeLocalProvider(uri: Uri): Boolean {
        val authority = uri.authority ?: return false

        // Android's MediaStore (photos, videos, audio from device)
        if (authority.startsWith("com.android.providers.media")) {
            return true
        }

        // Android's Downloads provider
        if (authority.startsWith("com.android.providers.downloads")) {
            return true
        }

        // All other providers (including cloud providers) are not on the allow list
        return false
    }
}
