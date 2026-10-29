package org.wordpress.gutenberg.media

import android.util.Log
import android.webkit.MimeTypeMap
import android.webkit.WebResourceResponse
import androidx.webkit.WebViewAssetLoader
import java.io.File
import java.io.FileInputStream
import java.io.IOException

/**
 * Serves files from `MediaFileManager`'s uploads directory under the editor's
 * asset origin. Registered at `/media/` so JS `fetch()` can read picked /
 * captured media same-origin against the asset loader's host.
 *
 * Path traversal is rejected outright — only flat `<name>` filenames inside
 * the uploads dir are servable.
 */
internal class MediaPathHandler(uploadsDir: File) : WebViewAssetLoader.PathHandler {

    private val uploadsRoot: File = uploadsDir.canonicalFile

    override fun handle(path: String): WebResourceResponse {
        val name = path.trimStart('/')
        if (name.isEmpty() || name.contains('/') || name.contains("..")) {
            return notFound()
        }
        val file = File(uploadsRoot, name)
        val resolved = try {
            file.canonicalFile
        } catch (e: IOException) {
            Log.w("MediaPathHandler", "Refusing /media/$name — canonical resolution failed", e)
            return notFound()
        } catch (e: SecurityException) {
            Log.w("MediaPathHandler", "Refusing /media/$name — canonical resolution denied", e)
            return notFound()
        }
        // Segment-aware containment check: walk `parentFile` from the resolved
        // candidate up to the filesystem root, accepting only if we pass
        // through `uploadsRoot`. This refuses `/foo-evil` matching `/foo` the
        // way a naive string-prefix would, without depending on
        // `java.nio.file.Path` (API 26+, `minSdk = 24` here).
        if (!resolved.isWithin(uploadsRoot) || !resolved.isFile) {
            return notFound()
        }
        val mime = MimeTypeMap.getSingleton()
            .getMimeTypeFromExtension(resolved.extension.lowercase())
            ?: "application/octet-stream"
        return WebResourceResponse(mime, null, FileInputStream(resolved))
    }

    private fun File.isWithin(root: File): Boolean {
        var current: File? = this
        while (current != null) {
            if (current == root) return true
            current = current.parentFile
        }
        return false
    }

    private fun notFound(): WebResourceResponse =
        WebResourceResponse("text/plain", "utf-8", 404, "Not Found", emptyMap(), null)
}
