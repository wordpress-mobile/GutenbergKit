package org.wordpress.gutenberg.http

/**
 * A parsed HTTP/1.1 request, either partial (headers only) or complete (headers and body).
 *
 * Contains the method, target, HTTP version, headers, and optional body.
 * When [isComplete] is false, the body is still pending and will be null.
 *
 * The body, if present, is accessible via [RequestBody] which provides
 * stream-based access regardless of backing storage (in-memory or file).
 */
class ParsedHTTPRequest(
    /** The HTTP method (e.g., "GET", "POST"). */
    val method: String,
    /** The request-target from the HTTP request line (e.g., "/wp/v2/posts?per_page=10"). */
    val target: String,
    /** The HTTP-version from the request line (e.g., "HTTP/1.1"). */
    val httpVersion: String,
    /**
     * The raw HTTP headers map. Header names preserve their original casing,
     * which makes map lookups case-sensitive. Use [header] for safe
     * case-insensitive lookup, or [allHeaders] for iteration.
     */
    internal val headers: Map<String, String>,
    /** The request body, or null if there is no body or the request is partial. */
    val body: RequestBody?,
    /** Whether all data has been received. */
    val isComplete: Boolean
) {
    /** The number of headers in the request. */
    val headerCount: Int get() = headers.size

    /** All headers as a list of name-value pairs, suitable for iteration. */
    val allHeaders: List<Pair<String, String>> get() = headers.map { it.key to it.value }

    /**
     * Returns the value of the first header matching the given name (case-insensitive).
     */
    fun header(name: String): String? {
        val lowered = name.lowercase()
        return headers.entries.firstOrNull { it.key.lowercase() == lowered }?.value
    }

    /**
     * Returns the headers suitable for forwarding to an upstream server.
     *
     * Strips RFC 9110 §7.6.1 hop-by-hop headers, any headers listed in the
     * `Connection` header, and the `Proxy-Authorization` header (which carries
     * the proxy's own bearer token per RFC 9110 §11.7.1 and must not be
     * forwarded upstream).  The `Authorization` header is intentionally kept
     * so that the client's own credentials (e.g. HTTP Basic) pass through.
     */
    fun forwardingHeaders(): Map<String, String> {
        val hopByHop = mutableSetOf(
            "host", "connection", "transfer-encoding", "keep-alive",
            "proxy-connection", "te", "upgrade", "trailer",
            "proxy-authorization",
        )

        // Headers listed in Connection are also hop-by-hop (RFC 9110 §7.6.1).
        header("Connection")?.split(",")?.forEach { name ->
            hopByHop.add(name.trim().lowercase())
        }

        return headers.filterKeys { it.lowercase() !in hopByHop }
    }

    /**
     * Parses the body as `multipart/form-data` and returns the individual parts.
     *
     * Extracts the boundary from the `Content-Type` header automatically.
     * Part bodies are lazy references back to the original request body — no
     * part data is copied during parsing for file-backed bodies.
     *
     * @throws MultipartParseException if the Content-Type is not `multipart/form-data`,
     *   the body is missing, or the multipart structure is malformed.
     */
    fun multipartParts(): List<MultipartPart> {
        val contentType = header("Content-Type")
            ?: throw MultipartParseException(MultipartParseError.NOT_MULTIPART_FORM_DATA)
        val boundary = extractBoundary(contentType)
            ?: throw MultipartParseException(MultipartParseError.NOT_MULTIPART_FORM_DATA)
        val bodyData = body
            ?: throw MultipartParseException(MultipartParseError.MISSING_BODY)

        val inMemory = bodyData.inMemoryData
        return if (inMemory != null) {
            // In-memory: scan the data directly (already in memory, no extra allocation).
            MultipartPart.parse(
                source = bodyData,
                bodyData = inMemory,
                bodyFileOffset = 0L,
                boundary = boundary
            )
        } else {
            // File-backed: scan in fixed-size chunks to avoid loading the entire
            // body into memory. Memory usage is O(chunk_size) regardless of body size.
            MultipartPart.parseChunked(
                source = bodyData as RequestBody.FileBacked,
                boundary = boundary
            )
        }
    }

    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (other !is ParsedHTTPRequest) return false
        return method == other.method &&
            target == other.target &&
            httpVersion == other.httpVersion &&
            headers == other.headers &&
            body == other.body &&
            isComplete == other.isComplete
    }

    override fun hashCode(): Int {
        var result = method.hashCode()
        result = 31 * result + target.hashCode()
        result = 31 * result + httpVersion.hashCode()
        result = 31 * result + headers.hashCode()
        result = 31 * result + (body?.hashCode() ?: 0)
        result = 31 * result + isComplete.hashCode()
        return result
    }

    companion object {
        /**
         * Extracts the boundary parameter from a `multipart/form-data` Content-Type value.
         */
        private fun extractBoundary(contentType: String): String? {
            if (!contentType.lowercase().startsWith("multipart/form-data")) return null
            val boundary = HeaderValue.extractParameter("boundary", contentType) ?: return null
            if (boundary.isEmpty() || boundary.length > 70) return null
            // RFC 2046 §5.1.1: boundary characters must be from the bchars set.
            if (!boundary.all { isBoundaryChar(it) }) return null
            // RFC 2046 §5.1.1: space cannot be the last character.
            if (boundary.endsWith(" ")) return null
            return boundary
        }

        /**
         * Returns whether a character is valid in a MIME boundary (RFC 2046 §5.1.1 bchars).
         */
        private fun isBoundaryChar(c: Char): Boolean {
            val ascii = c.code
            return when {
                ascii in 0x41..0x5A -> true // A-Z
                ascii in 0x61..0x7A -> true // a-z
                ascii in 0x30..0x39 -> true // 0-9
                c in "'()+_,-./:=? " -> true
                else -> false
            }
        }
    }
}
