package org.wordpress.gutenberg

import android.content.Context
import android.net.Uri
import android.provider.OpenableColumns
import android.webkit.MimeTypeMap
import java.io.File
import java.io.FileOutputStream
import java.io.IOException

/**
 * Utility class for caching files from content providers to avoid ERR_UPLOAD_FILE_CHANGED errors
 * in WebView when uploading files from cloud storage providers.
 */
object FileCache {
    private const val CACHE_DIR_NAME = "gutenberg_file_uploads"
    private const val BUFFER_SIZE = 8192

    /**
     * Copies a file from a content URI to the app's cache directory.
     *
     * This is necessary to work around Android WebView issues with uploading files from
     * cloud storage providers (Google Drive, Dropbox, etc.) which can trigger
     * ERR_UPLOAD_FILE_CHANGED errors due to streaming content or changing metadata.
     *
     * @param context Android context
     * @param uri The content:// URI to copy
     * @return URI of the cached file, or null if the copy failed
     */
    fun copyToCache(context: Context, uri: Uri): Uri? {
        val cacheDir = File(context.cacheDir, CACHE_DIR_NAME)
        if (!cacheDir.exists()) {
            cacheDir.mkdirs()
        }

        val fileName = getFileName(context, uri) ?: "upload_${System.currentTimeMillis()}"
        val extension = getFileExtension(context, uri)
        val fileNameWithExtension = if (extension != null && !fileName.endsWith(".$extension")) {
            "$fileName.$extension"
        } else {
            fileName
        }

        // Create a unique file to avoid conflicts
        val uniqueFileName = "${System.currentTimeMillis()}_$fileNameWithExtension"
        val cachedFile = File(cacheDir, uniqueFileName)

        return try {
            context.contentResolver.openInputStream(uri)?.use { input ->
                FileOutputStream(cachedFile).use { output ->
                    val buffer = ByteArray(BUFFER_SIZE)
                    var bytesRead: Int
                    while (input.read(buffer).also { bytesRead = it } != -1) {
                        output.write(buffer, 0, bytesRead)
                    }
                }
            }
            Uri.fromFile(cachedFile)
        } catch (e: IOException) {
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
     * Checks if a MIME type represents a media file (image or video).
     *
     * @param context Android context
     * @param uri The content URI
     * @return true if the MIME type starts with "image/" or "video/"
     */
    fun isMediaFile(context: Context, uri: Uri): Boolean {
        val mimeType = context.contentResolver.getType(uri) ?: return false
        return mimeType.startsWith("image/") || mimeType.startsWith("video/")
    }
}
