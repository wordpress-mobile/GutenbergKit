package org.wordpress.gutenberg.http

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

class RequestBodyTests {

    // MARK: - InMemory

    @Test
    fun `InMemory inputStream returns correct data`() {
        val data = "hello world".toByteArray()
        val body = RequestBody.InMemory(data)

        val result = body.inputStream().use { it.readBytes() }
        assertArrayEquals(data, result)
    }

    @Test
    fun `InMemory readBytes returns copy of data`() {
        val data = "hello".toByteArray()
        val body = RequestBody.InMemory(data)
        val copy = body.readBytes()

        assertArrayEquals(data, copy)
        // Mutating the copy should not affect the original.
        copy[0] = 'X'.code.toByte()
        assertEquals('h'.code.toByte(), data[0])
    }

    @Test
    fun `InMemory size returns correct value`() {
        val body = RequestBody.InMemory("hello".toByteArray())
        assertEquals(5L, body.size)
    }

    @Test
    fun `InMemory inMemoryData returns non-null`() {
        val body = RequestBody.InMemory("test".toByteArray())
        assertNotNull(body.inMemoryData)
        assertEquals(4, body.inMemoryData!!.size)
    }

    @Test
    fun `InMemory file returns null`() {
        val body = RequestBody.InMemory("test".toByteArray())
        assertNull(body.file)
    }

    @Test
    fun `InMemory equality with same data`() {
        val a = RequestBody.InMemory("hello".toByteArray())
        val b = RequestBody.InMemory("hello".toByteArray())
        assertEquals(a, b)
        assertEquals(a.hashCode(), b.hashCode())
    }

    @Test
    fun `InMemory inequality with different data`() {
        val a = RequestBody.InMemory("hello".toByteArray())
        val b = RequestBody.InMemory("world".toByteArray())
        assertNotEquals(a, b)
    }

    @Test
    fun `InMemory empty body`() {
        val body = RequestBody.InMemory(ByteArray(0))
        assertEquals(0L, body.size)
        assertArrayEquals(ByteArray(0), body.readBytes())
        assertArrayEquals(ByteArray(0), body.inputStream().use { it.readBytes() })
    }

    // MARK: - FileBacked

    @Test
    fun `FileBacked inputStream returns correct data`() {
        val data = "file-backed content".toByteArray()
        val file = File.createTempFile("rb-test-", null)
        file.deleteOnExit()
        file.writeBytes(data)

        val body = RequestBody.FileBacked(file = file, fileOffset = 0, size = data.size.toLong())
        val result = body.inputStream().use { it.readBytes() }
        assertArrayEquals(data, result)
    }

    @Test
    fun `FileBacked readBytes returns correct data`() {
        val data = "readBytes test".toByteArray()
        val file = File.createTempFile("rb-test-", null)
        file.deleteOnExit()
        file.writeBytes(data)

        val body = RequestBody.FileBacked(file = file, fileOffset = 0, size = data.size.toLong())
        assertArrayEquals(data, body.readBytes())
    }

    @Test
    fun `FileBacked with offset reads correct slice`() {
        val file = File.createTempFile("rb-test-", null)
        file.deleteOnExit()
        file.writeBytes("GARBAGE_hello world_TRAILING".toByteArray())

        // Read "hello world" starting at offset 8, length 11.
        val body = RequestBody.FileBacked(file = file, fileOffset = 8, size = 11)

        assertArrayEquals("hello world".toByteArray(), body.readBytes())
        assertArrayEquals("hello world".toByteArray(), body.inputStream().use { it.readBytes() })
    }

    @Test
    fun `FileBacked inputStream respects offset and size boundary`() {
        val file = File.createTempFile("rb-test-", null)
        file.deleteOnExit()
        file.writeBytes("AAAbbbCCC".toByteArray())

        val body = RequestBody.FileBacked(file = file, fileOffset = 3, size = 3)

        val stream = body.inputStream()
        val result = stream.use { it.readBytes() }
        assertArrayEquals("bbb".toByteArray(), result)
    }

    @Test
    fun `FileBacked single byte read`() {
        val file = File.createTempFile("rb-test-", null)
        file.deleteOnExit()
        file.writeBytes("ABCDE".toByteArray())

        val body = RequestBody.FileBacked(file = file, fileOffset = 2, size = 1)
        val stream = body.inputStream()
        assertEquals('C'.code, stream.read())
        assertEquals(-1, stream.read()) // Past the size boundary.
        stream.close()
    }

    @Test
    fun `FileBacked binary data preserved`() {
        val binaryData = ByteArray(512) { it.toByte() }
        val file = File.createTempFile("rb-test-", null)
        file.deleteOnExit()
        file.writeBytes(binaryData)

        val body = RequestBody.FileBacked(file = file, fileOffset = 0, size = binaryData.size.toLong())
        assertArrayEquals(binaryData, body.readBytes())
        assertArrayEquals(binaryData, body.inputStream().use { it.readBytes() })
    }

    @Test
    fun `FileBacked zero-length body`() {
        val file = File.createTempFile("rb-test-", null)
        file.deleteOnExit()
        file.writeBytes("content".toByteArray())

        val body = RequestBody.FileBacked(file = file, fileOffset = 3, size = 0)
        assertEquals(0L, body.size)
        assertArrayEquals(ByteArray(0), body.readBytes())
    }

    @Test
    fun `FileBacked multiple streams read independently`() {
        val data = "independent reads".toByteArray()
        val file = File.createTempFile("rb-test-", null)
        file.deleteOnExit()
        file.writeBytes(data)

        val body = RequestBody.FileBacked(file = file, fileOffset = 0, size = data.size.toLong())

        val stream1 = body.inputStream()
        val stream2 = body.inputStream()

        val result1 = stream1.use { it.readBytes() }
        val result2 = stream2.use { it.readBytes() }

        assertArrayEquals(data, result1)
        assertArrayEquals(data, result2)
    }

    @Test
    fun `FileBacked inMemoryData returns null`() {
        val file = File.createTempFile("rb-test-", null)
        file.deleteOnExit()
        file.writeBytes("test".toByteArray())

        val body = RequestBody.FileBacked(file = file, fileOffset = 0, size = 4)
        assertNull(body.inMemoryData)
    }

    @Test
    fun `FileBacked equality with same file and range`() {
        val file = File.createTempFile("rb-test-", null)
        file.deleteOnExit()
        file.writeBytes("content".toByteArray())

        val a = RequestBody.FileBacked(file = file, fileOffset = 1, size = 3)
        val b = RequestBody.FileBacked(file = file, fileOffset = 1, size = 3)
        assertEquals(a, b)
        assertEquals(a.hashCode(), b.hashCode())
    }

    @Test
    fun `FileBacked inequality with different offset`() {
        val file = File.createTempFile("rb-test-", null)
        file.deleteOnExit()
        file.writeBytes("content".toByteArray())

        val a = RequestBody.FileBacked(file = file, fileOffset = 0, size = 3)
        val b = RequestBody.FileBacked(file = file, fileOffset = 1, size = 3)
        assertNotEquals(a, b)
    }

    @Test
    fun `FileBacked inequality with different size`() {
        val file = File.createTempFile("rb-test-", null)
        file.deleteOnExit()
        file.writeBytes("content".toByteArray())

        val a = RequestBody.FileBacked(file = file, fileOffset = 0, size = 3)
        val b = RequestBody.FileBacked(file = file, fileOffset = 0, size = 5)
        assertNotEquals(a, b)
    }

    // MARK: - Cross-type inequality

    @Test
    fun `InMemory and FileBacked are not equal even with same content`() {
        val data = "same content".toByteArray()
        val file = File.createTempFile("rb-test-", null)
        file.deleteOnExit()
        file.writeBytes(data)

        val inMemory = RequestBody.InMemory(data)
        val fileBacked = RequestBody.FileBacked(file = file, fileOffset = 0, size = data.size.toLong())
        assertNotEquals(inMemory as RequestBody, fileBacked as RequestBody)
    }
}
