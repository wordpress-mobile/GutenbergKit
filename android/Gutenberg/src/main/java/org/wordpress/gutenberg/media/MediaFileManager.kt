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

/** A byte sequence that must appear at a fixed offset in the header. */
private class Anchor(val offset: Int, val bytes: ByteArray) {
    fun matchesIn(header: ByteArray, read: Int): Boolean {
        if (read < offset + bytes.size) return false
        for (i in bytes.indices) if (header[offset + i] != bytes[i]) return false
        return true
    }
}

/** A MIME type identified by one or more byte anchors in the header. */
private class MagicSignature(val mime: String, val anchors: List<Anchor>)

private fun bytes(vararg values: Int): ByteArray =
    ByteArray(values.size) { values[it].toByte() }

private val PREFIX_SIGNATURES: List<MagicSignature> = listOf(
    MagicSignature("image/jpeg", listOf(Anchor(0, bytes(0xFF, 0xD8, 0xFF)))),
    MagicSignature("image/png", listOf(Anchor(0, bytes(0x89, 0x50, 0x4E, 0x47)))),
    MagicSignature("image/gif", listOf(Anchor(0, bytes(0x47, 0x49, 0x46, 0x38)))),
    MagicSignature(
        "image/webp",
        listOf(
            Anchor(0, bytes(0x52, 0x49, 0x46, 0x46)), // 'RIFF'
            Anchor(8, bytes(0x57, 0x45, 0x42, 0x50)), // 'WEBP'
        ),
    ),
)

/**
 * ISO BMFF ftyp brands → MIME. The container has 'ftyp' at bytes 4-7 and the
 * major brand at bytes 8-11. HEIC has several conformant brands; AVIF has two.
 * Add brands here rather than touching `mimeFromMagicBytes`.
 */
private val FTYP_BRANDS: Map<String, String> = mapOf(
    "heic" to "image/heic",
    "heix" to "image/heic",
    "heim" to "image/heic",
    "heis" to "image/heic",
    "mif1" to "image/heic",
    "msf1" to "image/heic",
    "avif" to "image/avif",
    "avis" to "image/avif",
)

private const val ISO_BMFF_HEADER_BYTES = 12

private fun mimeFromMagicBytes(input: InputStream): String? {
    val header = ByteArray(ISO_BMFF_HEADER_BYTES)
    val read = input.read(header)
    if (read < 4) return null
    PREFIX_SIGNATURES.firstOrNull { sig ->
        sig.anchors.all { it.matchesIn(header, read) }
    }?.let { return it.mime }
    if (read >= ISO_BMFF_HEADER_BYTES && asciiAt(header, 4, 4) == "ftyp") {
        return FTYP_BRANDS[asciiAt(header, 8, 4)]
    }
    return null
}

private fun asciiAt(buf: ByteArray, offset: Int, length: Int): String =
    if (buf.size >= offset + length) String(buf, offset, length) else ""
