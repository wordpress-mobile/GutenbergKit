package org.wordpress.gutenberg.http

import java.io.RandomAccessFile

/**
 * Errors thrown when parsing a multipart/form-data body fails.
 */
enum class MultipartParseError(
    /** A camelCase identifier matching the Swift error case names and JSON fixture keys. */
    val errorId: String
) {
    NOT_MULTIPART_FORM_DATA("notMultipartFormData"),
    MISSING_BODY("missingBody"),
    MISSING_CONTENT_DISPOSITION("missingContentDisposition"),
    MISSING_NAME_PARAMETER("missingNameParameter"),
    MALFORMED_BODY("malformedBody"),
    TOO_MANY_PARTS("tooManyParts");
}

/**
 * Exception thrown when multipart parsing fails.
 */
class MultipartParseException(val error: MultipartParseError) : Exception(error.errorId)

/**
 * A single part from a `multipart/form-data` body, per RFC 7578.
 *
 * Each part represents one form field or file upload, with its own
 * Content-Disposition parameters and optional Content-Type.
 *
 * Part bodies are represented as lightweight references (byte ranges)
 * back to the original request body. No part data is copied during parsing
 * for file-backed bodies; bytes are only read when [body] is accessed
 * via [RequestBody.inputStream] or [RequestBody.readBytes].
 */
data class MultipartPart(
    /** The field name from `Content-Disposition: form-data; name="..."`. */
    val name: String,
    /** The filename, if present, from `Content-Disposition: form-data; filename="..."`. */
    val filename: String?,
    /** The `Content-Type` of this part, or `"text/plain"` if not specified (RFC 7578 §4.4). */
    val contentType: String,
    /** The part's body content, backed by a reference to the original request body. */
    val body: RequestBody
) {
    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (other !is MultipartPart) return false
        return name == other.name &&
            filename == other.filename &&
            contentType == other.contentType &&
            body == other.body
    }

    override fun hashCode(): Int {
        var result = name.hashCode()
        result = 31 * result + (filename?.hashCode() ?: 0)
        result = 31 * result + contentType.hashCode()
        result = 31 * result + body.hashCode()
        return result
    }

    companion object {
        private const val SCAN_CHUNK_SIZE = 65_536

        /**
         * Parses an in-memory `multipart/form-data` body into its constituent parts.
         *
         * Scans the body data to locate part boundaries and extract headers, but does
         * not copy part body bytes for file-backed sources. Each part's [body] is a
         * lightweight reference (offset + length) back to the source [RequestBody].
         *
         * @param source The original request body to reference for part content.
         * @param bodyData The raw body bytes (read once for scanning, then released by the caller).
         * @param bodyFileOffset The byte offset of [bodyData] within [source]'s backing file
         *     (0 for data-backed bodies).
         * @param boundary The boundary string from the Content-Type header.
         * @return A list of parsed parts with lazy body references.
         * @throws MultipartParseException if the body is malformed.
         */
        fun parse(
            source: RequestBody,
            bodyData: ReadOnlyBytes,
            bodyFileOffset: Long,
            boundary: String
        ): List<MultipartPart> {
            val delimiter = "--$boundary".toByteArray(Charsets.UTF_8)
            val closeDelimiter = "--$boundary--".toByteArray(Charsets.UTF_8)
            val crlf = "\r\n".toByteArray(Charsets.UTF_8)
            val crlfcrlf = "\r\n\r\n".toByteArray(Charsets.UTF_8)

            val firstDelimiterIndex = bodyData.indexOf(delimiter, 0)
            if (firstDelimiterIndex == -1) {
                throw MultipartParseException(MultipartParseError.MALFORMED_BODY)
            }

            val parts = mutableListOf<MultipartPart>()
            var searchStart = firstDelimiterIndex + delimiter.size

            while (searchStart < bodyData.size) {
                // RFC 2046 §5.1.1: skip optional transport padding (LWSP) after boundary.
                while (searchStart < bodyData.size &&
                    (bodyData[searchStart] == ' '.code.toByte() ||
                        bodyData[searchStart] == '\t'.code.toByte())
                ) {
                    searchStart++
                }

                // Skip the CRLF after the delimiter line
                if (searchStart + 1 < bodyData.size &&
                    bodyData[searchStart] == crlf[0] &&
                    bodyData[searchStart + 1] == crlf[1]
                ) {
                    searchStart += crlf.size
                }

                if (searchStart >= bodyData.size) break

                // Find the header/body separator within this part
                val headerEnd = bodyData.indexOf(crlfcrlf, searchStart)
                if (headerEnd == -1) {
                    throw MultipartParseException(MultipartParseError.MALFORMED_BODY)
                }

                val headerData = bodyData.copyOfRange(searchStart, headerEnd)
                val partBodyStart = headerEnd + crlfcrlf.size

                // Find the next delimiter to determine where this part's body ends
                val nextDelimiterIndex = bodyData.indexOf(delimiter, partBodyStart)
                if (nextDelimiterIndex == -1) {
                    throw MultipartParseException(MultipartParseError.MALFORMED_BODY)
                }

                // The body ends at the CRLF before the next delimiter
                var partBodyEnd = nextDelimiterIndex
                if (partBodyEnd >= partBodyStart + crlf.size) {
                    if (bodyData[partBodyEnd - 2] == crlf[0] &&
                        bodyData[partBodyEnd - 1] == crlf[1]
                    ) {
                        partBodyEnd -= crlf.size
                    }
                }

                // Build a lightweight body reference instead of copying bytes
                val partBodyLength = partBodyEnd - partBodyStart
                val partBody = makePartBody(
                    source = source,
                    bodyData = bodyData,
                    partOffset = partBodyStart,
                    partLength = partBodyLength,
                    bodyFileOffset = bodyFileOffset
                )

                val part = parsePartHeaders(headerData, partBody)
                parts.add(part)

                if (parts.size > 100) {
                    throw MultipartParseException(MultipartParseError.TOO_MANY_PARTS)
                }

                // Check if the next delimiter is the closing one
                if (bodyData.startsWith(closeDelimiter, nextDelimiterIndex)) {
                    break
                }

                searchStart = nextDelimiterIndex + delimiter.size
            }

            return parts
        }

        /**
         * Parses a file-backed `multipart/form-data` body using chunked scanning.
         *
         * Reads the file in fixed-size chunks to find boundary offsets, keeping memory
         * usage at O(chunk_size) regardless of body size. Part bodies are file-slice
         * references, not copies.
         *
         * @param source The file-backed request body.
         * @param boundary The boundary string from the Content-Type header.
         * @return A list of parsed parts with lazy body references.
         * @throws MultipartParseException if the body is malformed.
         */
        fun parseChunked(
            source: RequestBody.FileBacked,
            boundary: String
        ): List<MultipartPart> {
            val delimiter = "--$boundary".toByteArray(Charsets.UTF_8)
            val crlfcrlf = "\r\n\r\n".toByteArray(Charsets.UTF_8)

            val file = source.file!!
            val bodyStart = source.fileOffset
            val bodyLength = source.size
            val bodyEnd = bodyStart + bodyLength

            RandomAccessFile(file, "r").use { raf ->
                // Phase 1: Scan for all boundary delimiter offsets using chunked reads.
                // An overlap region (delimiter.size - 1 bytes) is carried between chunks
                // so boundaries split across chunk boundaries are still found.
                val overlapSize = delimiter.size - 1
                val delimiterOffsets = mutableListOf<Long>()
                var position = bodyStart
                var carryOver = ByteArray(0)

                while (position < bodyEnd) {
                    val readSize = minOf(SCAN_CHUNK_SIZE.toLong(), bodyEnd - position).toInt()
                    raf.seek(position)
                    val chunk = ByteArray(readSize)
                    val bytesRead = raf.read(chunk)
                    if (bytesRead <= 0) break
                    val actualChunk = if (bytesRead < readSize) chunk.copyOf(bytesRead) else chunk

                    val searchBuffer = if (carryOver.isEmpty()) {
                        actualChunk
                    } else {
                        ByteArray(carryOver.size + actualChunk.size).also {
                            carryOver.copyInto(it)
                            actualChunk.copyInto(it, carryOver.size)
                        }
                    }
                    val searchBytes = ReadOnlyBytes(searchBuffer)

                    var searchOffset = 0
                    while (true) {
                        val idx = searchBytes.indexOf(delimiter, searchOffset)
                        if (idx == -1) break
                        val absoluteOffset = position - carryOver.size + idx
                        if (absoluteOffset >= bodyStart && absoluteOffset + delimiter.size <= bodyEnd) {
                            delimiterOffsets.add(absoluteOffset)
                        }
                        searchOffset = idx + 1
                    }

                    carryOver = if (actualChunk.size > overlapSize) {
                        actualChunk.copyOfRange(actualChunk.size - overlapSize, actualChunk.size)
                    } else {
                        actualChunk.copyOf()
                    }
                    position += actualChunk.size
                }

                if (delimiterOffsets.isEmpty()) {
                    throw MultipartParseException(MultipartParseError.MALFORMED_BODY)
                }

                // Phase 2: Extract parts from consecutive delimiter pairs.
                val parts = mutableListOf<MultipartPart>()
                val maxPartHeaderSize = 8192

                for (i in delimiterOffsets.indices) {
                    val delimStart = delimiterOffsets[i]
                    val afterDelim = delimStart + delimiter.size

                    // Check if this is the close delimiter ("--boundary--").
                    if (afterDelim + 2 <= bodyEnd) {
                        raf.seek(afterDelim)
                        val b1 = raf.read()
                        val b2 = raf.read()
                        if (b1 == '-'.code && b2 == '-'.code) {
                            break
                        }
                    } else {
                        break
                    }

                    if (i + 1 >= delimiterOffsets.size) {
                        throw MultipartParseException(MultipartParseError.MALFORMED_BODY)
                    }
                    val nextDelimStart = delimiterOffsets[i + 1]

                    // Read the region between this delimiter and the next to extract headers.
                    val regionLength = minOf(maxPartHeaderSize.toLong(), nextDelimStart - afterDelim).toInt()
                    raf.seek(afterDelim)
                    val headerRegion = ByteArray(regionLength)
                    val headerBytesRead = raf.read(headerRegion, 0, regionLength)
                    if (headerBytesRead <= 0) {
                        throw MultipartParseException(MultipartParseError.MALFORMED_BODY)
                    }
                    val actualHeaderRegion = if (headerBytesRead < regionLength) {
                        headerRegion.copyOf(headerBytesRead)
                    } else {
                        headerRegion
                    }

                    // Skip optional transport padding (LWSP) after boundary.
                    var scanPos = 0
                    while (scanPos < actualHeaderRegion.size &&
                        (actualHeaderRegion[scanPos] == ' '.code.toByte() ||
                            actualHeaderRegion[scanPos] == '\t'.code.toByte())
                    ) {
                        scanPos++
                    }

                    // Skip CRLF after the delimiter line.
                    if (scanPos + 1 < actualHeaderRegion.size &&
                        actualHeaderRegion[scanPos] == 0x0D.toByte() &&
                        actualHeaderRegion[scanPos + 1] == 0x0A.toByte()
                    ) {
                        scanPos += 2
                    }

                    // Find the \r\n\r\n header/body separator.
                    val headerSearch = ReadOnlyBytes(actualHeaderRegion)
                    val headerEndIdx = headerSearch.indexOf(crlfcrlf, scanPos)
                    if (headerEndIdx == -1) {
                        throw MultipartParseException(MultipartParseError.MALFORMED_BODY)
                    }

                    val headerData = actualHeaderRegion.copyOfRange(scanPos, headerEndIdx)
                    val partBodyStart = afterDelim + (headerEndIdx + crlfcrlf.size)

                    // Body ends at the CRLF before the next delimiter.
                    var partBodyEnd = nextDelimStart
                    if (partBodyEnd >= partBodyStart + 2) {
                        raf.seek(nextDelimStart - 2)
                        val cr = raf.read()
                        val lf = raf.read()
                        if (cr == 0x0D && lf == 0x0A) {
                            partBodyEnd = nextDelimStart - 2
                        }
                    }

                    val partBodyLength = maxOf(0L, partBodyEnd - partBodyStart)
                    val partBody = RequestBody.FileBacked(
                        file = file,
                        fileOffset = partBodyStart,
                        size = partBodyLength,
                        fileOwner = source.fileOwner
                    )

                    val part = parsePartHeaders(headerData, partBody)
                    parts.add(part)

                    if (parts.size > 100) {
                        throw MultipartParseException(MultipartParseError.TOO_MANY_PARTS)
                    }
                }

                if (parts.isEmpty()) {
                    throw MultipartParseException(MultipartParseError.MALFORMED_BODY)
                }

                return parts
            }
        }

        /**
         * Creates a [RequestBody] for a part.
         *
         * For file-backed sources, returns a file-slice reference (no copy).
         * For in-memory sources, creates a copy via [ByteArray.copyOfRange].
         * Unlike Swift's copy-on-write Data slicing, Kotlin's ByteArray has no
         * COW semantics — but this path only triggers for bodies below the
         * [HTTPRequestParser.DEFAULT_IN_MEMORY_BODY_THRESHOLD] (512 KB), so
         * the copy is negligible. Large bodies are file-backed and use slices.
         */
        private fun makePartBody(
            source: RequestBody,
            bodyData: ReadOnlyBytes,
            partOffset: Int,
            partLength: Int,
            bodyFileOffset: Long
        ): RequestBody {
            return when (source) {
                is RequestBody.FileBacked -> RequestBody.FileBacked(
                    file = source.file,
                    fileOffset = bodyFileOffset + partOffset,
                    size = partLength.toLong(),
                    fileOwner = source.fileOwner
                )
                is RequestBody.InMemory -> {
                    val end = partOffset + partLength
                    RequestBody.InMemory(bodyData.copyOfRange(partOffset, end))
                }
            }
        }

        /**
         * Parses a single part's headers into a [MultipartPart].
         */
        private fun parsePartHeaders(headerData: ByteArray, body: RequestBody): MultipartPart {
            val headerString = try {
                headerData.toString(Charsets.UTF_8)
            } catch (_: Exception) {
                throw MultipartParseException(MultipartParseError.MISSING_CONTENT_DISPOSITION)
            }

            val lines = headerString.split("\r\n")

            var contentDisposition: String? = null
            var contentType: String? = null

            for (line in lines) {
                if (line.isEmpty()) continue
                val colonIndex = line.indexOf(':')
                if (colonIndex == -1) continue
                val key = line.substring(0, colonIndex).trim()
                val value = line.substring(colonIndex + 1).trim()

                when (key.lowercase()) {
                    "content-disposition" -> contentDisposition = value
                    "content-type" -> contentType = value
                }
            }

            val disposition = contentDisposition
                ?: throw MultipartParseException(MultipartParseError.MISSING_CONTENT_DISPOSITION)
            if (!disposition.lowercase().startsWith("form-data")) {
                throw MultipartParseException(MultipartParseError.MISSING_CONTENT_DISPOSITION)
            }

            val name = HeaderValue.extractParameter("name", disposition)
                ?: throw MultipartParseException(MultipartParseError.MISSING_NAME_PARAMETER)

            val filename = HeaderValue.extractParameter("filename", disposition)

            return MultipartPart(
                name = name,
                filename = filename,
                contentType = contentType ?: "text/plain",
                body = body
            )
        }

    }
}
