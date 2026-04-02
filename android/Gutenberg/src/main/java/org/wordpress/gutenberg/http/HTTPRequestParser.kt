package org.wordpress.gutenberg.http

import java.io.Closeable
import java.io.File
import java.io.IOException

/**
 * Parses raw HTTP/1.1 request data into a structured [ParsedHTTPRequest].
 *
 * This parser handles incremental data — call [append] as bytes arrive,
 * then check [state] to determine whether buffering is complete.
 *
 * The parser buffers incoming data to a temporary file on disk rather than
 * accumulating it in memory, making it suitable for large request bodies.
 * If the temp file cannot be created (e.g. disk full), the parser falls back
 * to in-memory buffering automatically.
 *
 * State tracking is lightweight — [append] scans for the header separator
 * (`\r\n\r\n`) and extracts `Content-Length`. Full parsing and RFC validation
 * are deferred until [parseRequest] is called.
 *
 * ```kotlin
 * val parser = HTTPRequestParser("GET /api HTTP/1.1\r\nHost: localhost\r\n\r\n")
 * val request = parser.parseRequest()
 * println("${request?.method} ${request?.target}")
 * ```
 */
class HTTPRequestParser(
    private val maxBodySize: Long = DEFAULT_MAX_BODY_SIZE,
    private val inMemoryBodyThreshold: Int = DEFAULT_IN_MEMORY_BODY_THRESHOLD,
    cacheDir: File? = null,
    tempSubdir: String = TempFileOwner.DEFAULT_TEMP_SUBDIR
) : Closeable {
    /** The current buffering state of the parser. */
    enum class State {
        /** More data is needed before headers are complete. */
        NEEDS_MORE_DATA,
        /** Headers have been fully received but the body is still incomplete. */
        HEADERS_COMPLETE,
        /**
         * The request body exceeds the maximum allowed size and is being
         * drained (read and discarded) so the server can send a clean 413
         * response. No body bytes are buffered in this state.
         */
        DRAINING,
        /** All data has been received (headers and body). */
        COMPLETE;

        /** Whether headers have been fully received. */
        val hasHeaders: Boolean
            get() = this == HEADERS_COMPLETE || this == DRAINING || this == COMPLETE

        /** Whether all data has been received. */
        val isComplete: Boolean
            get() = this == COMPLETE
    }

    companion object {
        /** Default maximum request body size (4 GB). */
        const val DEFAULT_MAX_BODY_SIZE: Long = 4L * 1024 * 1024 * 1024

        /** Default threshold below which bodies are kept in memory (512 KB). */
        const val DEFAULT_IN_MEMORY_BODY_THRESHOLD: Int = 512 * 1024

        /** Maximum number of bytes to buffer before the header terminator is found (64 KB). */
        const val MAX_HEADER_SIZE: Int = 65536
    }

    private val lock = Any()
    private val buffer = Buffer(maxSize = MAX_HEADER_SIZE + inMemoryBodyThreshold, cacheDir = cacheDir, tempSubdir = tempSubdir)
    private var _state: State = State.NEEDS_MORE_DATA
    private var bytesWritten: Long = 0
    private var headerEndOffset: Long? = null
    private var expectedContentLength: Long = 0

    // Lazy parsing cache
    private var parsedHeaders: ParsedHeaders? = null
    private var parseError: HTTPRequestParseError? = null
    private var cachedBody: RequestBody? = null
    private var bodyExtracted = false

    /** The current buffering state. */
    val state: State get() = synchronized(lock) { _state }

    /**
     * The parse error detected during buffering, if any.
     *
     * Non-fatal errors like [HTTPRequestParseError.PAYLOAD_TOO_LARGE] are
     * exposed here instead of being thrown by [parseRequest], allowing the
     * caller to still access the parsed headers.
     */
    val pendingParseError: HTTPRequestParseError? get() = synchronized(lock) { parseError }

    /** Creates a parser and immediately parses the given raw HTTP string. */
    constructor(
        input: String,
        maxBodySize: Long = DEFAULT_MAX_BODY_SIZE,
        inMemoryBodyThreshold: Int = DEFAULT_IN_MEMORY_BODY_THRESHOLD,
        cacheDir: File? = null,
        tempSubdir: String = TempFileOwner.DEFAULT_TEMP_SUBDIR
    ) : this(maxBodySize, inMemoryBodyThreshold, cacheDir, tempSubdir) {
        append(input.toByteArray(Charsets.UTF_8))
    }

    /** Creates a parser and immediately parses the given raw HTTP data. */
    constructor(
        data: ByteArray,
        maxBodySize: Long = DEFAULT_MAX_BODY_SIZE,
        inMemoryBodyThreshold: Int = DEFAULT_IN_MEMORY_BODY_THRESHOLD,
        cacheDir: File? = null
    ) : this(maxBodySize, inMemoryBodyThreshold, cacheDir) {
        append(data)
    }

    /**
     * Appends received data to the buffer and updates the buffering state.
     *
     * This method performs lightweight scanning — it looks for the `\r\n\r\n`
     * header separator and extracts the `Content-Length` value. Full parsing
     * and RFC validation are deferred until [parseRequest] is called.
     */
    fun append(data: ByteArray): Unit = synchronized(lock) {
        if (_state == State.COMPLETE) return

        // In drain mode, discard bytes without buffering and check
        // whether the full Content-Length has been consumed.
        if (_state == State.DRAINING) {
            bytesWritten += data.size.toLong()
            val offset = headerEndOffset
            if (offset != null && bytesWritten - offset >= expectedContentLength) {
                _state = State.COMPLETE
            }
            return
        }

        val accepted: Boolean
        try {
            accepted = buffer.append(data)
        } catch (_: IOException) {
            parseError = HTTPRequestParseError.BUFFER_IO_ERROR
            _state = State.COMPLETE
            return
        }
        if (!accepted) {
            parseError = HTTPRequestParseError.PAYLOAD_TOO_LARGE
            _state = State.COMPLETE
            return
        }
        bytesWritten += data.size.toLong()

        if (headerEndOffset == null) {
            val readLength = minOf(bytesWritten, MAX_HEADER_SIZE.toLong()).toInt()
            val buffered: ByteArray
            try {
                buffered = buffer.read(0, readLength)
            } catch (_: Exception) {
                parseError = HTTPRequestParseError.BUFFER_IO_ERROR
                _state = State.COMPLETE
                return
            }
            val separator = "\r\n\r\n".toByteArray(Charsets.UTF_8)

            // RFC 7230 §3.5: Skip leading CRLFs for robustness.
            var scanStart = 0
            while (scanStart + 1 < buffered.size &&
                buffered[scanStart] == 0x0D.toByte() &&
                buffered[scanStart + 1] == 0x0A.toByte()
            ) {
                scanStart += 2
            }

            val sepIndex = ReadOnlyBytes(buffered).indexOf(separator, scanStart)
            if (sepIndex == -1) {
                if (bytesWritten > MAX_HEADER_SIZE) {
                    parseError = HTTPRequestParseError.HEADERS_TOO_LARGE
                    _state = State.COMPLETE
                } else {
                    _state = State.NEEDS_MORE_DATA
                }
                return
            }

            headerEndOffset = (sepIndex + separator.size).toLong()
            val headerBytes = buffered.copyOfRange(scanStart, sepIndex)
            try {
                expectedContentLength = scanContentLength(headerBytes)
            } catch (e: HTTPRequestParseException) {
                parseError = e.error
                _state = State.COMPLETE
                return
            }

            if (expectedContentLength > maxBodySize) {
                parseError = HTTPRequestParseError.PAYLOAD_TOO_LARGE
                _state = State.DRAINING
                return
            }
        }

        val offset = headerEndOffset ?: return
        val bodyBytesAvailable = bytesWritten - offset

        _state = if (bodyBytesAvailable >= expectedContentLength) {
            State.COMPLETE
        } else {
            State.HEADERS_COMPLETE
        }
    }

    /**
     * Parses the buffered data into a structured HTTP request.
     *
     * This triggers full parsing via [HTTPRequestSerializer] on the first call.
     * The parsed headers are cached for subsequent calls. When the state is
     * [State.COMPLETE] and a body is present, the body is extracted on the first access.
     *
     * @return The parsed request, or `null` if the state is [State.NEEDS_MORE_DATA].
     * @throws HTTPRequestParseException if the request is malformed.
     */
    fun parseRequest(): ParsedHTTPRequest? = synchronized(lock) {
        if (!_state.hasHeaders) return null

        // Payload-too-large means "valid headers, rejected body" — let
        // the caller access the parsed headers so the handler can build
        // a response (e.g., with CORS headers). Other parse errors
        // indicate genuinely malformed requests and are still thrown.
        parseError?.let { if (it != HTTPRequestParseError.PAYLOAD_TOO_LARGE) throw HTTPRequestParseException(it) }

        if (parsedHeaders == null) {
            val headerData = buffer.read(0, minOf(bytesWritten, MAX_HEADER_SIZE.toLong()).toInt())
            when (val result = HTTPRequestSerializer.parseHeaders(headerData)) {
                is HeaderParseResult.Parsed -> parsedHeaders = result.headers
                is HeaderParseResult.Invalid -> {
                    parseError = result.error
                    throw HTTPRequestParseException(result.error)
                }
                is HeaderParseResult.NeedsMoreData -> return null
            }
        }

        val headers = parsedHeaders ?: return null

        // Return partial (headers only) when the body was rejected or
        // hasn't fully arrived yet. The payloadTooLarge case goes through
        // drain mode which discards body bytes without buffering them, so
        // there is no body to extract even though the state is COMPLETE.
        if (_state != State.COMPLETE || parseError != null) {
            return ParsedHTTPRequest(
                method = headers.method,
                target = headers.target,
                httpVersion = headers.httpVersion,
                headers = headers.headers,
                body = null,
                isComplete = false
            )
        }

        if (headers.contentLength > 0L && !bodyExtracted) {
            cachedBody = extractBody(headers.bodyOffset, headers.contentLength)
            bodyExtracted = true
        }

        return ParsedHTTPRequest(
            method = headers.method,
            target = headers.target,
            httpVersion = headers.httpVersion,
            headers = headers.headers,
            body = cachedBody,
            isComplete = true
        )
    }

    /**
     * Extracts the request body from the buffer.
     *
     * Bodies smaller than [inMemoryBodyThreshold] are read into memory.
     * Larger bodies reference the buffer's backing file directly as a slice,
     * avoiding a redundant copy.
     */
    private fun extractBody(offset: Int, length: Long): RequestBody? {
        if (length <= inMemoryBodyThreshold) {
            return RequestBody.InMemory(buffer.read(offset, length.toInt()))
        }

        // Reference the body range directly in the buffer's file.
        val ownership = buffer.transferFileOwnership()
        if (ownership != null) {
            val (file, owner) = ownership
            return RequestBody.FileBacked(
                file = file,
                fileOffset = offset.toLong(),
                size = length,
                fileOwner = owner
            )
        }

        // Memory-backed buffer — read into a byte array.
        require(length <= Int.MAX_VALUE) { "Body too large for in-memory buffer: $length bytes" }
        return RequestBody.InMemory(buffer.read(offset, length.toInt()))
    }

    override fun close() {
        buffer.close()
    }

    /**
     * Extracts and validates the `Content-Length` value from header bytes without full parsing.
     *
     * Reuses [HTTPRequestSerializer.validateContentLength] so that the scan and the later
     * full parse apply identical validation rules. Conflicting or malformed values are
     * rejected immediately — before any body bytes are buffered.
     *
     * @return 0 if no `Content-Length` header is present.
     * @throws HTTPRequestParseException if the value is invalid or conflicting.
     */
    private fun scanContentLength(headerBytes: ByteArray): Long {
        val string = try {
            headerBytes.toString(Charsets.UTF_8)
        } catch (_: Exception) {
            return 0
        }
        val lines = string.split("\r\n")

        var contentLength: Long? = null
        for (line in lines.drop(1)) {
            if (line.isEmpty()) continue
            val colonIndex = line.indexOf(':')
            if (colonIndex == -1) continue
            val rawKey = line.substring(0, colonIndex)
            if (rawKey.lowercase() == "content-length") {
                val value = line.substring(colonIndex + 1).trimOWS()
                contentLength = HTTPRequestSerializer.validateContentLength(value, contentLength)
            }
        }

        return contentLength ?: 0
    }
}
