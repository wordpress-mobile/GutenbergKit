package org.wordpress.gutenberg.media

import android.webkit.MimeTypeMap
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import java.io.File
import java.nio.file.Files

/**
 * Pins the path-traversal-rejection contract on `MediaPathHandler`. The
 * handler is the security boundary for everything under `/media/`; if a
 * future refactor regresses any of these cases, a request could be served
 * from outside the uploads dir.
 *
 * Robolectric provides `WebResourceResponse` and `MimeTypeMap`; symlink cases
 * use `java.nio.file.Files` from the host JVM, which has no API-level gate
 * under unit tests.
 */
@RunWith(RobolectricTestRunner::class)
class MediaPathHandlerTest {

    @get:Rule val tempFolder = TemporaryFolder()

    private lateinit var uploadsDir: File
    private lateinit var handler: MediaPathHandler

    @Before
    fun setUp() {
        uploadsDir = tempFolder.newFolder("Uploads")
        handler = MediaPathHandler(uploadsDir)
        // Robolectric's shadow MimeTypeMap is empty by default — register the
        // extensions the served-file test exercises so `getMimeTypeFromExtension`
        // returns the same value the production singleton would.
        shadowOf(MimeTypeMap.getSingleton())
            .addExtensionMimeTypeMapping("jpg", "image/jpeg")
    }

    // `WebResourceResponse`'s 3-arg success constructor doesn't set a status
    // code (the framework defaults it), so the test contract is "data is
    // non-null on success, null on a 404 from `notFound()`."

    @Test
    fun `serves an existing file inside uploads with resolved MIME`() {
        val payload = byteArrayOf(0xFF.toByte(), 0xD8.toByte(), 0xFF.toByte())
        File(uploadsDir, "abc.jpg").writeBytes(payload)

        val response = handler.handle("/abc.jpg")

        assertNotNull(response.data)
        assertEquals("image/jpeg", response.mimeType)
    }

    @Test
    fun `falls back to octet-stream when extension is unknown`() {
        File(uploadsDir, "abc.weirdext").writeBytes(byteArrayOf(0x00))

        val response = handler.handle("/abc.weirdext")

        assertNotNull(response.data)
        assertEquals("application/octet-stream", response.mimeType)
    }

    @Test
    fun `rejects empty path`() {
        assertEquals(404, handler.handle("").statusCode)
    }

    @Test
    fun `rejects slash-only path`() {
        assertEquals(404, handler.handle("/").statusCode)
    }

    @Test
    fun `rejects path containing dotdot segment`() {
        // Caught by the upfront pattern check; never reaches canonical resolution.
        assertEquals(404, handler.handle("/../etc/passwd").statusCode)
        assertEquals(404, handler.handle("/..").statusCode)
    }

    @Test
    fun `rejects multi-segment paths`() {
        File(uploadsDir, "sub").mkdir()
        File(uploadsDir, "sub/nested.jpg").writeBytes(byteArrayOf(0xFF.toByte()))

        // Multi-segment paths are rejected upfront, even when the underlying
        // file exists — the handler only serves flat names directly under uploads.
        assertEquals(404, handler.handle("/sub/nested.jpg").statusCode)
    }

    @Test
    fun `returns 404 for a missing file`() {
        assertEquals(404, handler.handle("/does-not-exist.jpg").statusCode)
    }

    @Test
    fun `returns 404 when the name resolves to a directory`() {
        File(uploadsDir, "subdir").mkdir()

        // Containment passes (the dir is inside uploads), but `!isFile` rejects.
        assertEquals(404, handler.handle("/subdir").statusCode)
    }

    @Test
    fun `rejects a symlink resolving outside uploads`() {
        val outside = tempFolder.newFile("outside.jpg").apply {
            writeBytes(byteArrayOf(0x01))
        }
        // Symlink inside uploads, target outside — canonical resolution follows
        // the link, parentFile walk never passes through uploadsRoot.
        Files.createSymbolicLink(
            File(uploadsDir, "link.jpg").toPath(),
            outside.toPath(),
        )

        assertEquals(404, handler.handle("/link.jpg").statusCode)
    }

    @Test
    fun `rejects a sibling-prefix directory request`() {
        // Defence against any future regression that swaps the parentFile walk
        // for a naive `canonicalPath.startsWith(uploadsRoot.canonicalPath)`:
        // a sibling dir whose path is a string-prefix of uploads must not match.
        // The handler only sees flat names so this can't arrive as a request;
        // assert that even if a symlink resolves into such a dir, it's rejected.
        val sibling = tempFolder.newFolder("Uploads-evil")
        val target = File(sibling, "evil.jpg").apply { writeBytes(byteArrayOf(0x01)) }
        Files.createSymbolicLink(
            File(uploadsDir, "evil.jpg").toPath(),
            target.toPath(),
        )

        assertEquals(404, handler.handle("/evil.jpg").statusCode)
    }
}
