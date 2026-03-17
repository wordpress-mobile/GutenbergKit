package org.wordpress.gutenberg.http

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class BufferTests {

    @Test
    fun `memory-backed append rejects data that would exceed maxSize`() {
        // Use a nonexistent cacheDir to force the memory fallback path.
        val bogusDir = java.io.File("/nonexistent-dir-that-will-never-exist")
        val buffer = Buffer(maxSize = 10, cacheDir = bogusDir)

        assertTrue(buffer.append("hello".toByteArray()))   // 5 bytes, under limit
        assertTrue(buffer.append("world".toByteArray()))   // 10 bytes, at limit
        assertFalse(buffer.append("!".toByteArray()))      // 11 bytes, rejected

        // Buffer still contains the data that was accepted.
        assertArrayEquals("helloworld".toByteArray(), buffer.read(0, 10))
        buffer.close()
    }

    @Test
    fun `transferFileOwnership creates TempFileOwner and close deletes the file`() {
        val buffer = Buffer()
        buffer.append("hello".toByteArray())
        val (file, owner) = buffer.transferFileOwnership()!!
        buffer.close()

        assertTrue("File should exist after buffer close when ownership was transferred", file.exists())
        owner.close()
        assertFalse("File should be deleted after TempFileOwner.close()", file.exists())
    }

    @Test
    fun `cleanOrphans deletes files not tracked by a live TempFileOwner`() {
        val cacheDir = kotlin.io.path.createTempDirectory("gutenberg-test-").toFile()
        val subDir = java.io.File(cacheDir, TempFileOwner.DEFAULT_TEMP_SUBDIR).also { it.mkdirs() }
        val orphan = java.io.File.createTempFile("GutenbergKitHTTP-", null, subDir)
        assertTrue(orphan.exists())

        TempFileOwner.cleanOrphans(cacheDir)
        assertFalse("Orphaned file should be deleted", orphan.exists())

        cacheDir.deleteRecursively()
    }

    @Test
    fun `cleanOrphans preserves files tracked by a live TempFileOwner`() {
        val cacheDir = kotlin.io.path.createTempDirectory("gutenberg-test-").toFile()
        val buffer = Buffer(cacheDir = cacheDir)
        buffer.append("data".toByteArray())
        val (file, owner) = buffer.transferFileOwnership()!!
        buffer.close()

        TempFileOwner.cleanOrphans(cacheDir)
        assertTrue("File should survive cleanOrphans while owner is live", file.exists())

        owner.close()
        cacheDir.deleteRecursively()
    }

    @Test
    fun `read with zero maxLength returns empty array`() {
        val buffer = Buffer()
        buffer.append("hello".toByteArray())
        val result = buffer.read(0, 0)
        assertEquals(0, result.size)
        buffer.close()
    }

    @Test
    fun `read with valid offset and length returns correct data`() {
        val buffer = Buffer()
        buffer.append("hello world".toByteArray())
        val result = buffer.read(6, 5)
        assertArrayEquals("world".toByteArray(), result)
        buffer.close()
    }

    @Test(expected = IllegalArgumentException::class)
    fun `read with negative offset throws`() {
        val buffer = Buffer()
        buffer.append("hello".toByteArray())
        try {
            buffer.read(-1, 5)
        } finally {
            buffer.close()
        }
    }

    @Test(expected = IllegalArgumentException::class)
    fun `read with negative maxLength throws`() {
        val buffer = Buffer()
        buffer.append("hello".toByteArray())
        try {
            buffer.read(0, -1)
        } finally {
            buffer.close()
        }
    }

    @Test
    fun `read beyond written data returns partial result`() {
        val buffer = Buffer()
        buffer.append("hi".toByteArray())
        val result = buffer.read(0, 100)
        assertArrayEquals("hi".toByteArray(), result)
        buffer.close()
    }
}
