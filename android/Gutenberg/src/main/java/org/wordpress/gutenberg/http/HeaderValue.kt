package org.wordpress.gutenberg.http

/**
 * Utilities for parsing structured HTTP header values (RFC 9110 §5.6).
 *
 * HTTP headers like `Content-Type` and `Content-Disposition` carry parameters
 * in `key=value` or `key="value"` form. This object provides a shared
 * implementation for extracting those parameters while correctly handling
 * quoted strings and backslash escapes per RFC 2045 §5.1.
 */
internal object HeaderValue {

    /**
     * Extracts a parameter value from a header value string.
     *
     * Searches for `name=` while skipping occurrences that fall inside
     * quoted strings, then extracts the value — handling both quoted
     * (with backslash escapes per RFC 2045 §5.1) and unquoted forms.
     *
     * @param name The parameter name to search for (case-insensitive).
     * @param headerValue The full header value string to search.
     * @return The extracted parameter value, or `null` if not found.
     */
    fun extractParameter(name: String, headerValue: String): String? {
        val search = "$name="
        var searchStart = 0

        while (searchStart < headerValue.length) {
            val matchIndex = headerValue.indexOf(search, searchStart, ignoreCase = true)
            if (matchIndex == -1) return null

            // Skip matches that fall inside a quoted string value.
            if (isInsideQuotedString(headerValue, matchIndex)) {
                searchStart = matchIndex + search.length
                continue
            }

            // Ensure the match is at a parameter boundary — not a substring
            // of another parameter name (e.g., "name=" inside "filename=").
            if (matchIndex > 0) {
                val preceding = headerValue[matchIndex - 1]
                if (preceding != ';' && preceding != ' ' && preceding != '\t') {
                    searchStart = matchIndex + search.length
                    continue
                }
            }

            val afterEquals = matchIndex + search.length

            return if (afterEquals < headerValue.length && headerValue[afterEquals] == '"') {
                extractQuotedValue(headerValue, afterEquals)
            } else {
                val endIndex = headerValue.indexOf(';', afterEquals)
                val raw = if (endIndex == -1) {
                    headerValue.substring(afterEquals)
                } else {
                    headerValue.substring(afterEquals, endIndex)
                }
                raw.trim()
            }
        }

        return null
    }

    /**
     * Extracts a quoted value starting at [quoteStart] (the opening `"`),
     * handling backslash escapes (`\"`, `\\`) per RFC 2045 §5.1.
     */
    private fun extractQuotedValue(text: String, quoteStart: Int): String {
        val valueStart = quoteStart + 1
        var index = valueStart
        val result = StringBuilder()

        while (index < text.length) {
            val char = text[index]
            if (char == '\\') {
                val next = index + 1
                if (next < text.length) {
                    result.append(text[next])
                    index = next + 1
                } else {
                    break
                }
            } else if (char == '"') {
                break
            } else {
                result.append(char)
                index++
            }
        }

        return result.toString()
    }

    /**
     * Returns whether the given position in the string falls inside a quoted string.
     *
     * Scans from the start, tracking quote open/close state while respecting
     * backslash escapes.
     */
    private fun isInsideQuotedString(string: String, position: Int): Boolean {
        var inQuote = false
        var index = 0
        while (index < position) {
            val char = string[index]
            if (inQuote && char == '\\') {
                // Skip escaped character
                index++
                if (index < position) {
                    index++
                }
                continue
            }
            if (char == '"') {
                inQuote = !inQuote
            }
            index++
        }
        return inQuote
    }
}
