package org.wordpress.gutenberg.http

import java.io.ByteArrayInputStream
import java.io.Closeable
import java.io.File
import java.io.InputStream
import java.io.RandomAccessFile

/**
 * An immutable, read-only view over a [ByteArray].
 *
 * This inline value class prevents callers from mutating the backing array
 * through the type system, without the overhead of a defensive copy.
 * At runtime the wrapper is erased — method calls compile to static
 * functions that operate directly on the underlying `ByteArray`.
 */
@JvmInline
value class ReadOnlyBytes(private val backing: ByteArray) {
    /** The number of bytes. */
    val size: Int get() = backing.size

    /** Returns the byte at the given [index]. */
    operator fun get(index: Int): Byte = backing[index]

    /** Returns a mutable copy of the underlying data. */
    fun copyOf(): ByteArray = backing.copyOf()

    /** Returns a mutable copy of the specified range. */
    fun copyOfRange(fromIndex: Int, toIndex: Int): ByteArray =
        backing.copyOfRange(fromIndex, toIndex)

    /** Creates an [InputStream] that reads from the backing data. */
    fun inputStream(): InputStream = ByteArrayInputStream(backing)

    /**
     * Finds the first occurrence of [pattern] starting from [fromIndex].
     * Returns -1 if not found.
     *
     * Uses a naive O(n·m) scan. This is sufficient because it is only used
     * for finding the header terminator (`\r\n\r\n`) within the first 64 KB
     * of a request — the pattern is 4 bytes and the data is capped by the
     * header size limit, so KMP/Boyer-Moore overhead is not justified.
     */
    fun indexOf(pattern: ByteArray, fromIndex: Int = 0): Int {
        if (pattern.isEmpty()) return fromIndex
        val limit = size - pattern.size
        if (fromIndex > limit) return -1
        outer@ for (i in fromIndex..limit) {
            for (j in pattern.indices) {
                if (backing[i + j] != pattern[j]) continue@outer
            }
            return i
        }
        return -1
    }

    /** Returns whether the bytes at [offset] match [pattern]. */
    fun startsWith(pattern: ByteArray, offset: Int): Boolean {
        if (offset + pattern.size > size) return false
        for (i in pattern.indices) {
            if (backing[offset + i] != pattern[i]) return false
        }
        return true
    }
}

/**
 * Owner for a temporary file, responsible for deleting it when no longer needed.
 *
 * Multiple [RequestBody] instances may share the same owner — for example, when
 * multipart parsing creates part bodies that reference byte ranges within the
 * same backing file. Because of this shared ownership, individual RequestBody
 * consumers should NOT close the owner; instead, the server's connection handler
 * calls [close] once the entire request (including all derived parts) is done.
 *
 * Active files are tracked in a companion registry so that orphaned temp files —
 * left behind by a crash or process kill — can be cleaned up on the next server
 * start via [cleanOrphans].
 *
 * ### Why not finalize() or deleteOnExit()?
 *
 * Both are unreliable on Android:
 * - `finalize()` is deprecated and ART may skip finalizer execution entirely
 *   under memory pressure (Android 12+).
 * - `deleteOnExit()` only fires on clean JVM shutdown. Android apps are killed
 *   by the OS, not shut down gracefully, so the hook effectively never runs.
 *
 * Instead, cleanup relies on two mechanisms:
 * 1. **Explicit [close]** at the connection boundary (primary path).
 * 2. **[cleanOrphans]** at server start (safety net for crashes).
 */
internal class TempFileOwner(val file: File) : Closeable {
    init {
        activeFiles.add(file.absolutePath)
    }

    override fun close() {
        activeFiles.remove(file.absolutePath)
        file.delete()
    }

    companion object {
        /** The default subdirectory name used for temp files under the injected cache dir. */
        const val DEFAULT_TEMP_SUBDIR = "gutenberg-http"

        /** Paths of temp files currently owned by a live [TempFileOwner]. */
        private val activeFiles = java.util.concurrent.ConcurrentHashMap.newKeySet<String>()

        /**
         * Deletes orphaned temp files in the [cacheDir]/[tempSubdir] directory.
         *
         * A file is considered orphaned if it is not tracked by any active
         * [TempFileOwner]. Call this at a safe point when no requests are
         * in-flight (e.g., server start).
         *
         * **Important:** Two server instances with the same `name` must not run
         * concurrently. On startup, this method deletes all files in the server's
         * temp subdirectory that are not tracked by an active [TempFileOwner]. If
         * another instance with the same name is still handling requests, its
         * in-flight temp files may be removed, causing I/O failures. Callers must
         * ensure each running server uses a unique name, or that the previous
         * instance is fully stopped before starting a new one.
         *
         * @param cacheDir The base cache directory.
         * @param tempSubdir The subdirectory name for temp files. When used via
         *   [HttpServer][org.wordpress.gutenberg.HttpServer], this is scoped by
         *   the server's `name` to prevent interference between concurrent instances.
         */
        fun cleanOrphans(cacheDir: File, tempSubdir: String = DEFAULT_TEMP_SUBDIR) {
            val dir = File(cacheDir, tempSubdir)
            if (!dir.isDirectory) return
            dir.listFiles()?.forEach { file ->
                if (!activeFiles.contains(file.absolutePath)) {
                    file.delete()
                }
            }
        }
    }
}

/**
 * An HTTP request body with stream semantics.
 *
 * `RequestBody` abstracts over the underlying storage (in-memory data or a file on disk)
 * and provides uniform access regardless of backing:
 * - **Stream access**: Use [inputStream] to read without loading everything into memory.
 * - **Materialized access**: Use [readBytes] to get the full contents.
 */
sealed class RequestBody {

    /** The number of bytes in the body. */
    abstract val size: Long

    /**
     * Creates an [InputStream] for reading the body contents.
     *
     * The caller is responsible for closing the returned stream.
     */
    abstract fun inputStream(): InputStream

    /** Reads the full body contents into a byte array. */
    abstract fun readBytes(): ByteArray

    /**
     * Reads the full body contents and returns a read-only view along with the
     * file offset at which the data begins (0 for in-memory bodies).
     *
     * This is used internally for multipart boundary scanning.
     */
    internal abstract fun readAllData(): Pair<ReadOnlyBytes, Long>

    /** A read-only view of the in-memory data backing this body, or `null` for file-backed bodies. */
    open val inMemoryData: ReadOnlyBytes? get() = null

    /** The file backing this body, or `null` for in-memory bodies. */
    open val file: File? get() = null

    /** The byte offset within the backing file where this body begins (0 for in-memory). */
    open val fileOffset: Long get() = 0

    /** The temp file owner, if any. Used to propagate ownership to derived bodies. */
    internal open val fileOwner: TempFileOwner? get() = null

    /**
     * A body backed by in-memory data.
     */
    class InMemory(val data: ByteArray) : RequestBody() {
        override val size: Long get() = data.size.toLong()
        override val inMemoryData: ReadOnlyBytes get() = ReadOnlyBytes(data)

        override fun inputStream(): InputStream =
            java.io.ByteArrayInputStream(data)

        override fun readBytes(): ByteArray = data.copyOf()

        override fun readAllData(): Pair<ReadOnlyBytes, Long> = ReadOnlyBytes(data) to 0L

        override fun equals(other: Any?): Boolean {
            if (this === other) return true
            return other is InMemory && data.contentEquals(other.data)
        }

        override fun hashCode(): Int = data.contentHashCode()
    }

    /**
     * A body backed by a byte range within a file on disk.
     *
     * Bytes are not read until [inputStream] or [readBytes] is called,
     * keeping the representation lightweight for uses like multipart part bodies.
     */
    class FileBacked internal constructor(
        override val file: File,
        override val fileOffset: Long = 0,
        override val size: Long,
        override val fileOwner: TempFileOwner? = null
    ) : RequestBody() {

        override fun inputStream(): InputStream {
            return object : InputStream() {
                private val raf = RandomAccessFile(file, "r").also { it.seek(fileOffset) }
                private var remaining = size
                private var closed = false

                override fun read(): Int {
                    if (remaining <= 0) return -1
                    remaining--
                    return raf.read()
                }

                override fun read(b: ByteArray, off: Int, len: Int): Int {
                    if (remaining <= 0) return -1
                    val toRead = minOf(len.toLong(), remaining).toInt()
                    val n = raf.read(b, off, toRead)
                    if (n > 0) remaining -= n
                    return n
                }

                override fun close() {
                    if (!closed) {
                        closed = true
                        raf.close()
                    }
                }
            }
        }

        override fun readBytes(): ByteArray {
            require(size <= Int.MAX_VALUE) { "Body too large to read into memory: $size bytes" }
            val intSize = size.toInt()
            RandomAccessFile(file, "r").use { raf ->
                raf.seek(fileOffset)
                val buf = ByteArray(intSize)
                var pos = 0
                while (pos < intSize) {
                    val n = raf.read(buf, pos, intSize - pos)
                    if (n == -1) break
                    pos += n
                }
                return if (pos == intSize) buf else buf.copyOf(pos)
            }
        }

        override fun readAllData(): Pair<ReadOnlyBytes, Long> = ReadOnlyBytes(readBytes()) to fileOffset

        override fun equals(other: Any?): Boolean {
            if (this === other) return true
            return other is FileBacked &&
                file == other.file &&
                fileOffset == other.fileOffset &&
                size == other.size
        }

        override fun hashCode(): Int {
            var result = file.hashCode()
            result = 31 * result + fileOffset.hashCode()
            result = 31 * result + size.hashCode()
            return result
        }
    }
}

/**
 * Abstraction over the parser's backing store.
 *
 * Tries to use a temp file on disk (suitable for large bodies). If the file
 * cannot be created, falls back to an in-memory buffer automatically.
 *
 * When memory-backed, the buffer is capped at [maxSize] to prevent unbounded
 * growth. The file-backed path has no cap — body size enforcement is handled
 * by the parser via `Content-Length` and `maxBodySize`.
 *
 * @param maxSize Maximum bytes allowed in the in-memory fallback buffer.
 *   Ignored when the buffer is file-backed.
 * @param cacheDir Optional directory for temp files (e.g., from `Context.getCacheDir()`).
 *   Files are created in a [tempSubdir] subdirectory. When `null`,
 *   falls back to the system temp directory.
 * @param tempSubdir The subdirectory name for temp files under [cacheDir].
 *   Defaults to [TempFileOwner.DEFAULT_TEMP_SUBDIR].
 */
internal class Buffer(maxSize: Int = Int.MAX_VALUE, cacheDir: File? = null, tempSubdir: String = TempFileOwner.DEFAULT_TEMP_SUBDIR) : Closeable {
    private val maxSize = maxSize
    private var file: File? = null
    private var raf: RandomAccessFile? = null
    private var memoryBuffer: java.io.ByteArrayOutputStream? = null
    private var fileOwnershipTransferred = false

    init {
        try {
            val tempDir = if (cacheDir != null) {
                File(cacheDir, tempSubdir).also { it.mkdirs() }
            } else {
                null
            }
            val tempFile = File.createTempFile("GutenbergKitHTTP-", null, tempDir)
            // No deleteOnExit() — on Android, apps are killed by the OS rather
            // than shut down gracefully, so the JVM shutdown hook never fires.
            // Cleanup is handled by TempFileOwner.close() and cleanOrphans().
            val handle = RandomAccessFile(tempFile, "rw")
            file = tempFile
            raf = handle
        } catch (_: Exception) {
            // Temp file unavailable — buffer in memory instead.
            memoryBuffer = java.io.ByteArrayOutputStream()
        }
    }

    /**
     * Appends data to the buffer.
     *
     * @return `true` if the data was accepted, `false` if the in-memory
     *   buffer would exceed its size limit.
     */
    fun append(data: ByteArray): Boolean {
        val r = raf
        if (r != null) {
            r.seek(r.length())
            r.write(data)
            return true
        } else {
            val buf = memoryBuffer!!
            if (buf.size() + data.size > maxSize) {
                return false
            }
            buf.write(data)
            return true
        }
    }

    fun read(offset: Int, maxLength: Int): ByteArray {
        require(offset >= 0) { "offset must be non-negative, was $offset" }
        require(maxLength >= 0) { "maxLength must be non-negative, was $maxLength" }
        if (maxLength == 0) return ByteArray(0)
        val r = raf
        if (r != null) {
            r.seek(offset.toLong())
            val buf = ByteArray(maxLength)
            var pos = 0
            while (pos < maxLength) {
                val n = r.read(buf, pos, maxLength - pos)
                if (n <= 0) break
                pos += n
            }
            return if (pos == maxLength) buf else buf.copyOf(pos)
        } else {
            val bytes = memoryBuffer!!.toByteArray()
            val start = offset.coerceAtMost(bytes.size)
            // Use Long arithmetic to avoid Int overflow when offset + maxLength > Int.MAX_VALUE
            // (possible with large media files like videos).
            val end = (offset.toLong() + maxLength.toLong()).coerceAtMost(bytes.size.toLong()).toInt()
            return bytes.copyOfRange(start, end)
        }
    }

    /**
     * Transfers ownership of the backing file to a [TempFileOwner].
     *
     * After this call, the buffer will no longer delete the file on [close].
     * Returns `null` if the buffer is memory-backed or ownership was already transferred.
     */
    fun transferFileOwnership(): Pair<File, TempFileOwner>? {
        val f = file ?: return null
        if (fileOwnershipTransferred) return null
        fileOwnershipTransferred = true
        return f to TempFileOwner(f)
    }

    /** Whether this buffer is backed by a file (vs. in-memory). */
    val isFileBacked: Boolean get() = raf != null

    override fun close() {
        try { raf?.close() } catch (_: Exception) {}
        if (!fileOwnershipTransferred) {
            file?.delete()
        }
    }
}
