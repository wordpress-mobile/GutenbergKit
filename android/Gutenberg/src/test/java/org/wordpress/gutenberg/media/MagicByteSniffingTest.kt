package org.wordpress.gutenberg.media

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import java.io.ByteArrayInputStream

class MagicByteSniffingTest {

    @Test
    fun `sniffs JPEG`() {
        assertEquals("image/jpeg", mime(0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10))
    }

    @Test
    fun `sniffs PNG`() {
        assertEquals("image/png", mime(0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A))
    }

    @Test
    fun `sniffs GIF87a and GIF89a`() {
        assertEquals("image/gif", mime(0x47, 0x49, 0x46, 0x38, 0x37, 0x61))
        assertEquals("image/gif", mime(0x47, 0x49, 0x46, 0x38, 0x39, 0x61))
    }

    @Test
    fun `sniffs WebP`() {
        // RIFF....WEBP — size bytes between RIFF and WEBP can be anything.
        assertEquals(
            "image/webp",
            mime(0x52, 0x49, 0x46, 0x46, 0xAA, 0xBB, 0xCC, 0xDD, 0x57, 0x45, 0x42, 0x50),
        )
    }

    @Test
    fun `sniffs HEIC across conformant brands`() {
        listOf("heic", "heix", "heim", "heis", "mif1", "msf1").forEach { brand ->
            assertEquals(
                "expected HEIC for brand $brand",
                "image/heic",
                mimeWithFtypBrand(brand),
            )
        }
    }

    @Test
    fun `sniffs AVIF still and sequence brands`() {
        assertEquals("image/avif", mimeWithFtypBrand("avif"))
        assertEquals("image/avif", mimeWithFtypBrand("avis"))
    }

    @Test
    fun `returns null for unknown ftyp brand`() {
        assertNull(mimeWithFtypBrand("mp42"))
    }

    @Test
    fun `returns null for too-short input`() {
        assertNull(mime(0xFF, 0xD8))
    }

    @Test
    fun `returns null for empty input`() {
        assertNull(mimeFromMagicBytes(ByteArrayInputStream(ByteArray(0))))
    }

    @Test
    fun `returns null for unrecognised header`() {
        assertNull(mime(0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07))
    }

    @Test
    fun `WebP needs both RIFF and WEBP anchors`() {
        // RIFF without WEBP brand → not WebP
        assertNull(
            mime(0x52, 0x49, 0x46, 0x46, 0x00, 0x00, 0x00, 0x00, 0x57, 0x41, 0x56, 0x45),
        )
    }

    private fun mime(vararg bytes: Int): String? =
        mimeFromMagicBytes(ByteArrayInputStream(ByteArray(bytes.size) { bytes[it].toByte() }))

    private fun mimeWithFtypBrand(brand: String): String? {
        val header = ByteArray(12)
        // Bytes 0-3: box size (any 4 bytes). Bytes 4-7: 'ftyp'. Bytes 8-11: brand.
        "ftyp".toByteArray(Charsets.US_ASCII).copyInto(header, destinationOffset = 4)
        brand.toByteArray(Charsets.US_ASCII).copyInto(header, destinationOffset = 8)
        return mimeFromMagicBytes(ByteArrayInputStream(header))
    }
}
