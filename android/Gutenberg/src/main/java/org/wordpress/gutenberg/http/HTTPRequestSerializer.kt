package org.wordpress.gutenberg.http

/**
 * Errors thrown when parsing an HTTP/1.1 request fails due to RFC 7230/9112 violations.
 */
enum class HTTPRequestParseError(
    /** The HTTP status code that should be sent for this error. */
    val httpStatus: Int,
    /** A camelCase identifier matching the Swift error case names and JSON fixture keys. */
    val errorId: String
) {
    EMPTY_HEADER_SECTION(400, "emptyHeaderSection"),
    MALFORMED_REQUEST_LINE(400, "malformedRequestLine"),
    OBS_FOLD_DETECTED(400, "obsFoldDetected"),
    WHITESPACE_BEFORE_COLON(400, "whitespaceBeforeColon"),
    INVALID_CONTENT_LENGTH(400, "invalidContentLength"),
    CONFLICTING_CONTENT_LENGTH(400, "conflictingContentLength"),
    UNSUPPORTED_TRANSFER_ENCODING(400, "unsupportedTransferEncoding"),
    INVALID_HTTP_VERSION(400, "invalidHTTPVersion"),
    INVALID_FIELD_NAME(400, "invalidFieldName"),
    INVALID_FIELD_VALUE(400, "invalidFieldValue"),
    MISSING_HOST_HEADER(400, "missingHostHeader"),
    MULTIPLE_HOST_HEADERS(400, "multipleHostHeaders"),
    PAYLOAD_TOO_LARGE(413, "payloadTooLarge"),
    HEADERS_TOO_LARGE(431, "headersTooLarge"),
    TOO_MANY_HEADERS(431, "tooManyHeaders"),
    INVALID_ENCODING(400, "invalidEncoding"),
    BUFFER_IO_ERROR(500, "bufferIOError");
}

/**
 * Exception thrown when HTTP request parsing fails.
 */
class HTTPRequestParseException(val error: HTTPRequestParseError) : Exception(error.errorId)

/**
 * Parsed header information from an HTTP request.
 */
data class ParsedHeaders(
    /** The HTTP method (e.g., "GET", "POST"). */
    val method: String,
    /** The request-target from the HTTP request line, per RFC 9112 Section 3. */
    val target: String,
    /** The HTTP-version from the request line (e.g., "HTTP/1.1"), per RFC 9112 §2.3. */
    val httpVersion: String,
    /** The HTTP headers as key-value pairs, preserving original casing. */
    val headers: LinkedHashMap<String, String>,
    /** The value of the `Content-Length` header, or 0 if absent. */
    val contentLength: Long,
    /** The byte offset where the body begins (after the `\r\n\r\n` separator). */
    val bodyOffset: Int
)

/**
 * The result of attempting to parse HTTP request headers.
 */
sealed class HeaderParseResult {
    /** The data does not yet contain the complete header section (`\r\n\r\n`). */
    data object NeedsMoreData : HeaderParseResult()
    /** The header data is malformed and cannot be parsed. */
    data class Invalid(val error: HTTPRequestParseError) : HeaderParseResult()
    /** Headers were successfully parsed. */
    data class Parsed(val headers: ParsedHeaders) : HeaderParseResult()
}

/**
 * Parses raw HTTP/1.1 request bytes into structured components.
 *
 * This is the stateless parser that converts raw HTTP request data into
 * a [ParsedHeaders] structure. For incremental parsing with buffering,
 * use [HTTPRequestParser] instead.
 */
internal object HTTPRequestSerializer {

    /**
     * Attempts to parse the HTTP request line and headers from raw data.
     *
     * Looks for the `\r\n\r\n` header terminator, then parses the request line
     * and individual headers. Returns [HeaderParseResult.NeedsMoreData] if the
     * terminator hasn't been received yet, or [HeaderParseResult.Invalid] with
     * a specific error if the request is malformed.
     */
    fun parseHeaders(data: ByteArray): HeaderParseResult {
        // RFC 7230 §3.5: Skip leading CRLFs for robustness.
        var scanOffset = 0
        while (scanOffset + 1 < data.size &&
            data[scanOffset] == 0x0D.toByte() &&
            data[scanOffset + 1] == 0x0A.toByte()
        ) {
            scanOffset += 2
        }
        if (scanOffset >= data.size) return HeaderParseResult.NeedsMoreData

        val separator = "\r\n\r\n".toByteArray(Charsets.UTF_8)
        val separatorIndex = ReadOnlyBytes(data).indexOf(separator, scanOffset)
        if (separatorIndex == -1) return HeaderParseResult.NeedsMoreData

        val headerBytes = data.copyOfRange(scanOffset, separatorIndex)

        // Validate UTF-8 encoding by round-tripping through String and back.
        val headerString: String
        try {
            headerString = headerBytes.toString(Charsets.UTF_8)
            val reEncoded = headerString.toByteArray(Charsets.UTF_8)
            if (!reEncoded.contentEquals(headerBytes)) {
                return HeaderParseResult.Invalid(HTTPRequestParseError.INVALID_ENCODING)
            }
        } catch (_: Exception) {
            return HeaderParseResult.Invalid(HTTPRequestParseError.INVALID_ENCODING)
        }

        val lines = headerString.split("\r\n")
        val requestLine = lines.firstOrNull()
        if (requestLine.isNullOrEmpty()) {
            return HeaderParseResult.Invalid(HTTPRequestParseError.EMPTY_HEADER_SECTION)
        }

        val parts = requestLine.split(" ", limit = 3)
        if (parts.size < 2) {
            return HeaderParseResult.Invalid(HTTPRequestParseError.MALFORMED_REQUEST_LINE)
        }

        val method = parts[0]
        val target = parts[1]

        // RFC 9110 §9.1: method = token (tchar characters only).
        if (!method.all { isTokenChar(it) }) {
            return HeaderParseResult.Invalid(HTTPRequestParseError.MALFORMED_REQUEST_LINE)
        }

        // RFC 9112 §2.3: HTTP-version = "HTTP/" DIGIT "." DIGIT
        if (parts.size < 3) {
            return HeaderParseResult.Invalid(HTTPRequestParseError.INVALID_HTTP_VERSION)
        }
        val httpVersion = parts[2]
        if (!isValidHTTPVersion(httpVersion)) {
            return HeaderParseResult.Invalid(HTTPRequestParseError.INVALID_HTTP_VERSION)
        }

        // RFC 9112 §3.2: Validate request-target form.
        if (method == "CONNECT") {
            if (target.startsWith("/") || !target.contains(":")) {
                return HeaderParseResult.Invalid(HTTPRequestParseError.MALFORMED_REQUEST_LINE)
            }
        } else if (method == "OPTIONS" && target == "*") {
            // asterisk-form is valid for OPTIONS
        } else if (target.startsWith("/")) {
            // origin-form — valid for all methods
        } else if (target.lowercase().startsWith("http://") || target.lowercase().startsWith("https://")) {
            // absolute-form — valid for all methods
        } else {
            return HeaderParseResult.Invalid(HTTPRequestParseError.MALFORMED_REQUEST_LINE)
        }

        val headers = LinkedHashMap<String, String>()
        val keyIndex = HashMap<String, String>()  // lowercased -> original casing
        var contentLengthValue: Long? = null
        var hostHeaderCount = 0
        var headerCount = 0

        for (line in lines.drop(1)) {
            if (line.isEmpty()) continue

            headerCount++
            if (headerCount > 100) {
                return HeaderParseResult.Invalid(HTTPRequestParseError.TOO_MANY_HEADERS)
            }

            // RFC 7230 §3.2.4: Reject obs-fold
            if (line[0] == ' ' || line[0] == '\t') {
                return HeaderParseResult.Invalid(HTTPRequestParseError.OBS_FOLD_DETECTED)
            }

            val colonIndex = line.indexOf(':')
            if (colonIndex == -1) {
                return HeaderParseResult.Invalid(HTTPRequestParseError.INVALID_FIELD_NAME)
            }

            val rawKey = line.substring(0, colonIndex)

            // RFC 7230 §3.2.4: No whitespace is allowed between the field-name and colon.
            // Check this before the general token validation so we return the more
            // specific error (WHITESPACE_BEFORE_COLON) instead of INVALID_FIELD_NAME.
            if (rawKey.any { it == ' ' || it == '\t' }) {
                return HeaderParseResult.Invalid(HTTPRequestParseError.WHITESPACE_BEFORE_COLON)
            }

            // RFC 9110 §5.1: field-name = token
            if (rawKey.isEmpty() || !rawKey.all { isTokenChar(it) }) {
                return HeaderParseResult.Invalid(HTTPRequestParseError.INVALID_FIELD_NAME)
            }

            val key = rawKey
            val lowerKey = key.lowercase()
            // RFC 9110 §5.5: OWS (optional whitespace) is SP / HTAB only.
            // Kotlin's String.trim() strips all chars <= 0x20 (including CR, LF, etc.),
            // which would silently remove bare CRs before field value validation.
            val value = line.substring(colonIndex + 1).trimOWS()

            // RFC 9110 §5.5: Validate field value characters.
            for (c in value) {
                val v = c.code
                if (v <= 0x08 || (v in 0x0A..0x1F) || v == 0x7F) {
                    return HeaderParseResult.Invalid(HTTPRequestParseError.INVALID_FIELD_VALUE)
                }
            }

            // RFC 7230 §3.3.3: Reject Transfer-Encoding
            if (lowerKey == "transfer-encoding") {
                return HeaderParseResult.Invalid(HTTPRequestParseError.UNSUPPORTED_TRANSFER_ENCODING)
            }

            // Content-Length: validate and normalize
            if (lowerKey == "content-length") {
                contentLengthValue = try {
                    validateContentLength(value, contentLengthValue)
                } catch (e: HTTPRequestParseException) {
                    return HeaderParseResult.Invalid(e.error)
                }
                val resolved = contentLengthValue.toString()
                val existingKey = keyIndex["content-length"]
                if (existingKey != null) {
                    headers[existingKey] = resolved
                } else {
                    headers[key] = resolved
                    keyIndex["content-length"] = key
                }
                continue
            }

            // Track Host header occurrences
            if (lowerKey == "host") {
                hostHeaderCount++
            }

            // RFC 9110 §5.3: Combine duplicate field lines with comma-separated values.
            val existingKey = keyIndex[lowerKey]
            if (existingKey != null) {
                headers[existingKey] = "${headers[existingKey]}, $value"
            } else {
                headers[key] = value
                keyIndex[lowerKey] = key
            }
        }

        // RFC 9110 §7.2: Host header validation
        if (hostHeaderCount > 1) {
            return HeaderParseResult.Invalid(HTTPRequestParseError.MULTIPLE_HOST_HEADERS)
        }
        if (httpVersion == "HTTP/1.1" && hostHeaderCount == 0) {
            return HeaderParseResult.Invalid(HTTPRequestParseError.MISSING_HOST_HEADER)
        }

        val contentLength = contentLengthValue ?: 0L
        val bodyOffset = separatorIndex + separator.size

        return HeaderParseResult.Parsed(
            ParsedHeaders(
                method = method,
                target = target,
                httpVersion = httpVersion,
                headers = headers,
                contentLength = contentLength,
                bodyOffset = bodyOffset
            )
        )
    }

    /**
     * Validates a Content-Length header value per RFC 9110 §8.6 / RFC 7230 §3.3.3.
     */
    internal fun validateContentLength(value: String, existing: Long?): Long {
        val parts = value.split(",").map { it.trim() }
        val first = parts.firstOrNull()
        if (first.isNullOrEmpty() || !first.all { isAsciiDigit(it) }) {
            throw HTTPRequestParseException(HTTPRequestParseError.INVALID_CONTENT_LENGTH)
        }
        val cl = first.toLongOrNull()
            ?: throw HTTPRequestParseException(HTTPRequestParseError.INVALID_CONTENT_LENGTH)
        if (cl < 0) throw HTTPRequestParseException(HTTPRequestParseError.INVALID_CONTENT_LENGTH)

        for (part in parts.drop(1)) {
            if (part.isEmpty() || !part.all { isAsciiDigit(it) }) {
                throw HTTPRequestParseException(HTTPRequestParseError.CONFLICTING_CONTENT_LENGTH)
            }
            val partValue = part.toLongOrNull()
            if (partValue != cl) {
                throw HTTPRequestParseException(HTTPRequestParseError.CONFLICTING_CONTENT_LENGTH)
            }
        }

        if (existing != null && existing != cl) {
            throw HTTPRequestParseException(HTTPRequestParseError.CONFLICTING_CONTENT_LENGTH)
        }
        return cl
    }

    /**
     * Validates that a string matches the HTTP-version format: `HTTP/DIGIT.DIGIT`.
     */
    private fun isValidHTTPVersion(version: String): Boolean {
        if (!version.startsWith("HTTP/")) return false
        val rest = version.removePrefix("HTTP/")
        val parts = rest.split(".", limit = 2)
        if (parts.size != 2) return false
        return parts[0].length == 1 && parts[0][0].isDigit() &&
            parts[1].length == 1 && parts[1][0].isDigit()
    }

    /**
     * Returns whether a character is a valid HTTP token character (RFC 9110 §5.6.2).
     */
    private fun isTokenChar(c: Char): Boolean {
        val ascii = c.code
        return when {
            ascii in 0x41..0x5A -> true // A-Z
            ascii in 0x61..0x7A -> true // a-z
            ascii in 0x30..0x39 -> true // 0-9
            c in "!#\$%&'*+-.^_`|~" -> true
            else -> false
        }
    }

    /**
     * Returns whether a character is an ASCII digit (0-9).
     * Unlike [Char.isDigit], this rejects non-ASCII Unicode digits.
     */
    private fun isAsciiDigit(c: Char): Boolean = c.code in 0x30..0x39

}

/**
 * Trims only SP (0x20) and HTAB (0x09) from both ends of a string.
 *
 * This matches RFC 9110's OWS (optional whitespace) definition:
 *   OWS = *( SP / HTAB )
 *
 * Unlike Kotlin's [String.trim], this does NOT strip CR, LF, or other
 * control characters, ensuring they are preserved for field value
 * validation (which must reject them per RFC 9110 §5.5).
 */
internal fun String.trimOWS(): String {
    var start = 0
    var end = length
    while (start < end && (this[start] == ' ' || this[start] == '\t')) start++
    while (end > start && (this[end - 1] == ' ' || this[end - 1] == '\t')) end--
    return if (start == 0 && end == length) this else substring(start, end)
}
