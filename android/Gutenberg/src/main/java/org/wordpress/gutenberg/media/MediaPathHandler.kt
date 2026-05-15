package org.wordpress.gutenberg.media

import android.util.Log
import android.webkit.MimeTypeMap
import android.webkit.WebResourceResponse
import androidx.webkit.WebViewAssetLoader
import java.io.File
import java.io.FileInputStream
import java.io.IOException
import java.nio.file.Path

/**
 * Serves files from `MediaFileManager`'s uploads directory under the editor's
 * asset origin. Registered at `/media/` so JS `fetch()` can read picked /
 * captured media same-origin against `appassets.androidplatform.net`.
 *
 * Path traversal is rejected outright — only flat `<name>` filenames inside
 * the uploads dir are servable.
 */
internal class MediaPathHandler(private val uploadsDir: File) : WebViewAssetLoader.PathHandler {

    private val uploadsRoot: Path = uploadsDir.canonicalFile.toPath()

    override fun handle(path: String): WebResourceResponse {
        val name = path.trimStart('/')
        if (name.isEmpty() || name.contains('/') || name.contains("..")) {
            return notFound()
        }
        val file = File(uploadsDir, name)
        val resolved = try {
            file.canonicalFile.toPath()
        } catch (e: IOException) {
            Log.w("MediaPathHandler", "Refusing /media/$name — canonical path resolution failed", e)
            return notFound()
        }
        // Segment-aware containment check via Path.startsWith — refuses
        // `/foo-evil` matching `/foo` the way naive string-prefix would.
        if (!resolved.startsWith(uploadsRoot) || !file.isFile) {
            return notFound()
        }
        val mime = MimeTypeMap.getSingleton()
            .getMimeTypeFromExtension(file.extension.lowercase())
            ?: "application/octet-stream"
        return WebResourceResponse(mime, null, FileInputStream(file))
    }

    private fun notFound(): WebResourceResponse =
        WebResourceResponse("text/plain", "utf-8", 404, "Not Found", emptyMap(), null)
}
