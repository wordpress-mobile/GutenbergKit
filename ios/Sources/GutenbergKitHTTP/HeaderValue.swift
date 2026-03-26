import Foundation

/// Utilities for parsing structured HTTP header values (RFC 9110 §5.6).
///
/// HTTP headers like `Content-Type` and `Content-Disposition` carry parameters
/// in `key=value` or `key="value"` form. This enum provides a shared
/// implementation for extracting those parameters while correctly handling
/// quoted strings and backslash escapes per RFC 2045 §5.1.
enum HeaderValue {

    /// Extracts a parameter value from a header value string.
    ///
    /// Searches for `name=` while skipping occurrences that fall inside
    /// quoted strings, then extracts the value — handling both quoted
    /// (with backslash escapes per RFC 2045 §5.1) and unquoted forms.
    ///
    /// ```swift
    /// // Content-Type: multipart/form-data; boundary=----WebKitFormBoundary
    /// HeaderValue.extractParameter("boundary", from: contentType)
    ///
    /// // Content-Disposition: form-data; name="file"; filename="photo.jpg"
    /// HeaderValue.extractParameter("filename", from: disposition)
    /// ```
    ///
    /// - Parameters:
    ///   - name: The parameter name to search for (case-insensitive).
    ///   - headerValue: The full header value string to search.
    /// - Returns: The extracted parameter value, or `nil` if not found.
    static func extractParameter(_ name: String, from headerValue: String) -> String? {
        let search = "\(name)="
        var searchStart = headerValue.startIndex

        while searchStart < headerValue.endIndex {
            guard let paramRange = headerValue.range(
                of: search,
                options: .caseInsensitive,
                range: searchStart..<headerValue.endIndex
            ) else {
                return nil
            }

            // Skip matches that fall inside a quoted string value.
            if isInsideQuotedString(headerValue, position: paramRange.lowerBound) {
                searchStart = paramRange.upperBound
                continue
            }

            // Ensure the match is at a parameter boundary — not a substring
            // of another parameter name (e.g., "name=" inside "filename=").
            if paramRange.lowerBound > headerValue.startIndex {
                let preceding = headerValue[headerValue.index(before: paramRange.lowerBound)]
                if preceding != ";" && preceding != " " && preceding != "\t" {
                    searchStart = paramRange.upperBound
                    continue
                }
            }

            let afterEquals = headerValue[paramRange.upperBound...]

            if afterEquals.hasPrefix("\"") {
                return extractQuotedValue(afterEquals)
            } else {
                let endIndex = afterEquals.firstIndex(of: ";") ?? afterEquals.endIndex
                return String(afterEquals[..<endIndex]).trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }

    /// Extracts a quoted value starting after the opening `"`, handling
    /// backslash escapes (`\"`, `\\`) per RFC 2045 §5.1.
    private static func extractQuotedValue(_ text: some StringProtocol) -> String {
        let valueStart = text.index(after: text.startIndex)
        var index = valueStart
        var result = ""

        while index < text.endIndex {
            let char = text[index]
            if char == "\\" {
                let next = text.index(after: index)
                if next < text.endIndex {
                    result.append(text[next])
                    index = text.index(after: next)
                } else {
                    break
                }
            } else if char == "\"" {
                break
            } else {
                result.append(char)
                index = text.index(after: index)
            }
        }
        return result
    }

    /// Returns whether the given position in the string falls inside a quoted string.
    ///
    /// Scans from the start, tracking quote open/close state while respecting
    /// backslash escapes.
    private static func isInsideQuotedString(_ string: String, position: String.Index) -> Bool {
        var inQuote = false
        var index = string.startIndex
        while index < position {
            let char = string[index]
            if inQuote && char == "\\" {
                // Skip escaped character
                index = string.index(after: index)
                if index < position {
                    index = string.index(after: index)
                }
                continue
            }
            if char == "\"" {
                inQuote = !inQuote
            }
            index = string.index(after: index)
        }
        return inQuote
    }
}
