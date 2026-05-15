package org.wordpress.gutenberg.media

import android.content.Context
import android.net.Uri
import android.util.Log
import android.webkit.MimeTypeMap
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.wordpress.gutenberg.DEFAULT_ASSET_DOMAIN
import java.io.File
import java.io.IOException
import java.io.InputStream
import java.util.UUID
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Imports user-picked / captured media into an app-private uploads directory
 * and produces an editor-loadable URL. Pairs with `MediaPathHandler`, which
 * serves files back to the WebView under the same origin as the editor bundle.
 *
 * Mirrors iOS's `MediaFileManager` actor — same 2-day TTL, same on-disk layout,
 * same MediaInfo shape on the wire.
 */
internal object MediaFileManager {
    private const val ROOT_DIR = "GutenbergKit"
    private const val UPLOADS_DIR = "Uploads"
    private const val MEDIA_PATH_SEGMENT = "media"
    private const val FILE_TTL_DAYS = 2L
    private const val FALLBACK_EXT = "bin"
    private const val FALLBACK_MIME = "application/octet-stream"

    /** WebViewAssetLoader prefix — leading and trailing slash are required by the API. */
    const val MEDIA_PATH_PREFIX = "/$MEDIA_PATH_SEGMENT/"

    private fun mediaUrlFor(fileName: String): String =
        Uri.Builder()
            .scheme("https")
            .authority(DEFAULT_ASSET_DOMAIN)
            .appendPath(MEDIA_PATH_SEGMENT)
            .appendPath(fileName)
            .build()
            .toString()

    private val cleanupOnce = AtomicBoolean(false)

    fun uploadsDir(context: Context): File =
        File(File(context.filesDir, ROOT_DIR), UPLOADS_DIR).apply { mkdirs() }

    /**
     * Copies the source URI into uploads and returns a MediaInfo whose `url`
     * resolves against the editor's asset origin via `MediaPathHandler`.
     */
    suspend fun import(context: Context, uri: Uri): MediaInfo = withContext(Dispatchers.IO) {
        ensureCleanup(context)
        val mime = resolveMime(context, uri)
        val ext = preferredExtension(mime, uri)
        val fileName = "${UUID.randomUUID()}.$ext"
        val dest = File(uploadsDir(context), fileName)
        val input = context.contentResolver.openInputStream(uri)
            ?: throw IOException("Could not open URI for read: $uri")
        input.use { source ->
            dest.outputStream().use { sink -> source.copyTo(sink) }
        }
        MediaInfo(url = mediaUrlFor(fileName), type = mime)
    }

    /**
     * Provisions a destination file for the camera capture launcher. The
     * camera writes directly into uploads, so a successful capture is
     * already-imported — no copy step.
     */
    fun newCameraOutputFile(context: Context): File {
        ensureCleanup(context)
        return File(uploadsDir(context), "${UUID.randomUUID()}.jpg")
    }

    fun mediaInfoForFile(file: File, mime: String = "image/jpeg"): MediaInfo =
        MediaInfo(url = mediaUrlFor(file.name), type = mime)

    private fun ensureCleanup(context: Context) {
        if (!cleanupOnce.compareAndSet(false, true)) return
        try {
            sweepStaleFiles(uploadsDir(context))
        } catch (e: SecurityException) {
            Log.w("MediaFileManager", "Cleanup skipped", e)
        }
    }

    private fun sweepStaleFiles(dir: File) {
        val cutoff = System.currentTimeMillis() - TimeUnit.DAYS.toMillis(FILE_TTL_DAYS)
        dir.listFiles()?.forEach { file ->
            if (file.lastModified() < cutoff) file.delete()
        }
    }

    private fun resolveMime(context: Context, uri: Uri): String {
        // ContentResolver knows the MIME for content:// URIs (MediaStore, SAF,
        // photo picker) and for FileProvider-backed file:// URIs from our own
        // camera launcher — that's every source we produce today.
        context.contentResolver.getType(uri)?.let { return it }
        val pathExt = MimeTypeMap.getFileExtensionFromUrl(uri.toString())
        if (!pathExt.isNullOrEmpty()) {
            MimeTypeMap.getSingleton()
                .getMimeTypeFromExtension(pathExt.lowercase())
                ?.let { return it }
        }
        // Last-ditch sniff for SAF providers that hand back octet-streams.
        // Magic-byte coverage focuses on the formats `getType` and the system
        // tables miss most often: HEIC and AVIF.
        return runCatching {
            context.contentResolver.openInputStream(uri)?.use { mimeFromMagicBytes(it) }
        }.getOrNull() ?: FALLBACK_MIME
    }

    private fun preferredExtension(mime: String, uri: Uri): String {
        MimeTypeMap.getSingleton().getExtensionFromMimeType(mime)?.let { return it }
        val pathExt = MimeTypeMap.getFileExtensionFromUrl(uri.toString())
        if (!pathExt.isNullOrEmpty()) return pathExt.lowercase()
        return FALLBACK_EXT
    }
}

@Suppress("ReturnCount", "MagicNumber")
private fun mimeFromMagicBytes(input: InputStream): String? {
    val header = ByteArray(12)
    val read = input.read(header)
    if (read < 4) return null
    if (matchesAt(header, 0, 0xFF, 0xD8, 0xFF)) return "image/jpeg"
    if (matchesAt(header, 0, 0x89, 0x50, 0x4E, 0x47)) return "image/png"
    if (matchesAt(header, 0, 0x47, 0x49, 0x46, 0x38)) return "image/gif"
    if (read >= 12 &&
        matchesAt(header, 0, 0x52, 0x49, 0x46, 0x46) &&
        matchesAt(header, 8, 0x57, 0x45, 0x42, 0x50)
    ) {
        return "image/webp"
    }
    // ISO BMFF: bytes 4-7 spell 'ftyp', brand at bytes 8-11.
    if (read >= 12 && asciiAt(header, 4, 4) == "ftyp") {
        return when (asciiAt(header, 8, 4)) {
            "heic", "heix", "heim", "heis", "mif1", "msf1" -> "image/heic"
            "avif", "avis" -> "image/avif"
            else -> null
        }
    }
    return null
}

private fun asciiAt(buf: ByteArray, offset: Int, length: Int): String =
    if (buf.size >= offset + length) String(buf, offset, length) else ""

private fun matchesAt(buf: ByteArray, offset: Int, vararg expected: Int): Boolean {
    if (buf.size < offset + expected.size) return false
    return expected.indices.all { buf[offset + it] == expected[it].toByte() }
}
