import Foundation

/// Errors thrown when parsing an HTTP/1.1 request fails due to RFC 7230/9112 violations.
public enum HTTPRequestParseError: Error, Sendable, Equatable, LocalizedError, CaseIterable {
    /// The header section before `\r\n\r\n` is empty (e.g., `\r\n\r\n` with no request line).
    case emptyHeaderSection
    /// The request line does not contain at least a method and target (RFC 9112 §3).
    case malformedRequestLine
    /// A header line starts with SP or HTAB, indicating obs-fold (RFC 7230 §3.2.4).
    case obsFoldDetected
    /// A header field-name contains whitespace before the colon (RFC 7230 §3.2.4).
    case whitespaceBeforeColon
    /// The `Content-Length` value is not a valid non-negative integer (RFC 9112 §6.3).
    case invalidContentLength
    /// Multiple `Content-Length` headers with conflicting values (RFC 7230 §3.3.3).
    case conflictingContentLength
    /// The request contains a `Transfer-Encoding` header, which is not supported (RFC 7230 §3.3.3).
    case unsupportedTransferEncoding
    /// The HTTP-version in the request line is missing or does not match `HTTP/DIGIT.DIGIT` (RFC 9112 §2.3).
    case invalidHTTPVersion
    /// A header field-name is empty or contains characters outside the token set (RFC 9110 §5.1).
    case invalidFieldName
    /// A header field value contains NUL (0x00) or bare CR (RFC 9110 §5.5).
    case invalidFieldValue
    /// An HTTP/1.1 request is missing the required Host header (RFC 9110 §7.2).
    case missingHostHeader
    /// The request contains more than one Host header field line (RFC 9110 §7.2).
    case multipleHostHeaders
    /// The `Content-Length` exceeds the server's maximum allowed body size.
    case payloadTooLarge
    /// The header section exceeds the maximum allowed size before the terminator is found.
    case headersTooLarge
    /// The request contains more than 100 header field lines.
    case tooManyHeaders
    /// The header data could not be decoded as UTF-8.
    case invalidEncoding
    /// An I/O error occurred while buffering the request (e.g. disk full).
    case bufferIOError

    /// How the parser disposes of a parse error.
    public enum Disposition: Sendable {
        /// Abort the connection; the malformed request never reaches the handler.
        case fatal
        /// Surface to the handler via ``HTTPRequestParser/parseError`` so it can
        /// build a response.
        case recoverable
    }

    /// Whether this error aborts the connection (``Disposition/fatal``) or is
    /// surfaced to the handler (``Disposition/recoverable``).
    ///
    /// Only genuinely recoverable errors — where the request line and headers are
    /// well-formed — may be recoverable; anything smuggling-relevant (framing,
    /// Content-Length) must stay fatal so the request never reaches the handler.
    public var disposition: Disposition {
        switch self {
        case .payloadTooLarge:
            return .recoverable
        case .emptyHeaderSection, .malformedRequestLine, .obsFoldDetected,
             .whitespaceBeforeColon, .invalidContentLength, .conflictingContentLength,
             .unsupportedTransferEncoding, .invalidHTTPVersion, .invalidFieldName,
             .invalidFieldValue, .missingHostHeader, .multipleHostHeaders,
             .headersTooLarge, .tooManyHeaders, .invalidEncoding, .bufferIOError:
            return .fatal
        }
    }

    /// The HTTP status code that should be sent for this error.
    public var httpStatus: Int {
        switch self {
        case .payloadTooLarge: return 413
        case .headersTooLarge, .tooManyHeaders: return 431
        case .bufferIOError: return 500
        default: return 400
        }
    }

    /// The HTTP reason phrase for the corresponding status code.
    ///
    /// Returns a `StaticString` so callers needing a stable C pointer (e.g., JNI bridge)
    /// can use `utf8Start` without allocation.
    public var httpStatusText: StaticString {
        HTTPResponse.defaultStatusText(for: httpStatus)
    }

    public var errorDescription: String? {
        switch self {
        case .emptyHeaderSection:
            return "The HTTP request header section is empty — no request line was found before the header terminator."
        case .malformedRequestLine:
            return "The HTTP request line is malformed — it must contain at least a method and request target separated by a space."
        case .obsFoldDetected:
            return "The HTTP request contains an obsolete line folding (a header continuation line starting with a space or tab), which is rejected per RFC 7230 §3.2.4."
        case .whitespaceBeforeColon:
            return "A header field name contains whitespace before the colon, which is rejected per RFC 7230 §3.2.4 to prevent request smuggling."
        case .invalidContentLength:
            return "The Content-Length header value is not a valid non-negative integer."
        case .conflictingContentLength:
            return "The request contains multiple Content-Length headers with different values, which is rejected per RFC 7230 §3.3.3."
        case .unsupportedTransferEncoding:
            return "The request contains a Transfer-Encoding header. This server only supports identity encoding with Content-Length framing (RFC 7230 §3.3.3)."
        case .invalidHTTPVersion:
            return "The HTTP-version in the request line is missing or malformed — it must match HTTP/DIGIT.DIGIT (e.g., HTTP/1.1) per RFC 9112 §2.3."
        case .invalidFieldName:
            return "A header field name is empty or contains characters outside the HTTP token set per RFC 9110 §5.1."
        case .invalidFieldValue:
            return "A header field value contains a NUL byte (0x00) or bare CR, which is rejected per RFC 9110 §5.5."
        case .missingHostHeader:
            return "The HTTP/1.1 request is missing the required Host header field per RFC 9110 §7.2."
        case .multipleHostHeaders:
            return "The request contains more than one Host header field line, which is rejected per RFC 9110 §7.2."
        case .payloadTooLarge:
            return "The request body exceeds the maximum allowed size."
        case .headersTooLarge:
            return "The request header section exceeds the maximum allowed size (64 KB)."
        case .tooManyHeaders:
            return "The request contains more than 100 header field lines."
        case .invalidEncoding:
            return "The HTTP request headers could not be decoded as UTF-8."
        case .bufferIOError:
            return "An I/O error occurred while buffering the request body (e.g. disk full)."
        }
    }
}

/// Parses raw HTTP/1.1 request bytes into structured components.
///
/// This is the stateless counterpart to ``HTTPResponseSerializer`` — it converts
/// raw HTTP request data into a ``ParsedHTTPRequest``, while ``HTTPResponseSerializer``
/// converts structured response data into raw bytes.
///
/// For incremental parsing with buffering, use ``HTTPRequestParser`` instead.
///
/// ```swift
/// let data = Data("GET /api HTTP/1.1\r\nHost: localhost\r\n\r\n".utf8)
/// if case .parsed(let headers) = HTTPRequestSerializer.parseHeaders(from: data) {
///     print(headers.method, headers.target)
/// }
/// ```
public enum HTTPRequestSerializer {

    /// Parsed header information from an HTTP request.
    public struct ParsedHeaders: Sendable {
        /// The HTTP method (e.g., "GET", "POST").
        public let method: String
        /// The request-target from the HTTP request line, per RFC 9112 Section 3.
        public let target: String
        /// The HTTP-version from the request line (e.g., "HTTP/1.1"), per RFC 9112 §2.3.
        public let httpVersion: String
        /// The HTTP headers as key-value pairs, preserving original casing.
        public let headers: [String: String]
        /// The value of the `Content-Length` header, or 0 if absent.
        public let contentLength: Int64
        /// The byte offset where the body begins (after the `\r\n\r\n` separator).
        public let bodyOffset: Int
    }

    /// The result of attempting to parse HTTP request headers.
    public enum HeaderParseResult: Sendable {
        /// The data does not yet contain the complete header section (`\r\n\r\n`).
        case needsMoreData
        /// The header data is malformed and cannot be parsed.
        case invalid(HTTPRequestParseError)
        /// Headers were successfully parsed.
        case parsed(ParsedHeaders)
    }

    /// Attempts to parse the HTTP request line and headers from raw data.
    ///
    /// Looks for the `\r\n\r\n` header terminator, then parses the request line
    /// and individual headers. Returns `.needsMoreData` if the terminator hasn't
    /// been received yet, or `.invalid` with a specific ``HTTPRequestParseError``
    /// if the request is malformed.
    ///
    /// - Parameter data: The raw HTTP request bytes received so far.
    /// - Returns: The parse result indicating whether headers are available.
    public static func parseHeaders(from data: Data) -> HeaderParseResult {
        // Ensure zero-based indexing — Data slices retain their original indices,
        // so a caller passing e.g. `fullData[500...]` would crash on `data[0]`.
        let data = Data(data)

        // RFC 7230 §3.5: Skip leading CRLFs for robustness.
        // A server SHOULD ignore at least one empty line received prior to the request-line.
        var scanOffset = 0
        while scanOffset + 1 < data.count,
              data[scanOffset] == 0x0D,
              data[scanOffset + 1] == 0x0A {
            scanOffset += 2
        }
        guard scanOffset < data.count else {
            return .needsMoreData
        }
        let effectiveData = data[scanOffset...]

        let separator = Data("\r\n\r\n".utf8)
        guard let separatorRange = effectiveData.range(of: separator) else {
            return .needsMoreData
        }

        let headerData = effectiveData[effectiveData.startIndex..<separatorRange.lowerBound]
        // Validate UTF-8 encoding by round-tripping through String and back.
        // This rejects overlong encodings, lone surrogates, and other malformed
        // sequences that a lenient decoder might silently accept.
        guard let headerString = String(data: headerData, encoding: .utf8),
              Data(headerString.utf8) == Data(headerData) else {
            return .invalid(.invalidEncoding)
        }

        let lines = headerString.components(separatedBy: "\r\n")
        guard let requestLine = lines.first, !requestLine.isEmpty else {
            return .invalid(.emptyHeaderSection)
        }

        let parts = requestLine.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: false)
        guard parts.count >= 2 else {
            return .invalid(.malformedRequestLine)
        }

        let method = String(parts[0])
        let target = String(parts[1])

        // RFC 9110 §9.1: method = token (tchar characters only).
        guard method.allSatisfy({ isTokenChar($0) }) else {
            return .invalid(.malformedRequestLine)
        }

        // RFC 9112 §2.3: HTTP-version = "HTTP/" DIGIT "." DIGIT
        guard parts.count >= 3 else {
            return .invalid(.invalidHTTPVersion)
        }
        let httpVersion = String(parts[2])
        guard isValidHTTPVersion(httpVersion) else {
            return .invalid(.invalidHTTPVersion)
        }

        // RFC 9112 §3.2: Validate request-target form.
        // origin-form: starts with "/"
        // absolute-form: starts with a scheme (e.g. "http://", "https://")
        // asterisk-form: "*" (only valid for OPTIONS)
        // authority-form: only valid for CONNECT
        if method == "CONNECT" {
            // authority-form: host:port — must contain a colon and not start with "/"
            if target.hasPrefix("/") || !target.contains(":") {
                return .invalid(.malformedRequestLine)
            }
        } else if method == "OPTIONS" && target == "*" {
            // asterisk-form is valid for OPTIONS
        } else if target.hasPrefix("/") {
            // origin-form — valid for all methods
        } else if target.lowercased().hasPrefix("http://") || target.lowercased().hasPrefix("https://") {
            // absolute-form — valid for all methods
        } else {
            return .invalid(.malformedRequestLine)
        }

        var headers: [String: String] = [:]
        var keyIndex: [String: String] = [:]  // lowercased -> original casing
        var contentLengthValue: Int64?
        var hostHeaderCount = 0
        var headerCount = 0
        for line in lines.dropFirst() where !line.isEmpty {
            headerCount += 1
            if headerCount > 100 {
                return .invalid(.tooManyHeaders)
            }
            // RFC 7230 §3.2.4: Reject obs-fold (continuation line starting with SP or HTAB)
            if line.first == " " || line.first == "\t" {
                return .invalid(.obsFoldDetected)
            }

            guard let colonIndex = line.firstIndex(of: ":") else {
                // RFC 9112 §5: A line with content but no colon is not a valid field line.
                return .invalid(.invalidFieldName)
            }

            let rawKey = line[line.startIndex..<colonIndex]

            // RFC 7230 §3.2.4: No whitespace is allowed between the field-name and colon.
            // Check this before the general token validation so we return the more
            // specific error (.whitespaceBeforeColon) instead of .invalidFieldName.
            if rawKey.contains(where: { $0 == " " || $0 == "\t" }) {
                return .invalid(.whitespaceBeforeColon)
            }

            // RFC 9110 §5.1: field-name = token (must be non-empty and contain only tchar)
            guard !rawKey.isEmpty, rawKey.allSatisfy({ isTokenChar($0) }) else {
                return .invalid(.invalidFieldName)
            }

            let key = String(rawKey)
            let lowerKey = key.lowercased()
            let value = String(line[line.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)

            // RFC 9110 §5.5: field-value may only contain VCHAR (0x21-0x7E),
            // SP (0x20), HTAB (0x09), and obs-text (0x80-0xFF).
            // Reject any byte in 0x00-0x08, 0x0A-0x1F, and 0x7F.
            for scalar in value.unicodeScalars {
                let v = scalar.value
                if v <= 0x08 || (v >= 0x0A && v <= 0x1F) || v == 0x7F {
                    return .invalid(.invalidFieldValue)
                }
            }

            // RFC 7230 §3.3.3: Reject requests with Transfer-Encoding since this
            // server does not support chunked decoding. Silently ignoring it would
            // cause body framing mismatches (request smuggling).
            if lowerKey == "transfer-encoding" {
                return .invalid(.unsupportedTransferEncoding)
            }

            // Content-Length: validate and normalize to a single integer value.
            if lowerKey == "content-length" {
                do {
                    contentLengthValue = try validateContentLength(value, existing: contentLengthValue)
                } catch {
                    return .invalid(error)
                }
                // Store the resolved integer as the canonical header value,
                // not the raw (possibly comma-separated) form.
                let resolved = String(contentLengthValue!)
                if let existingKey = keyIndex["content-length"] {
                    headers[existingKey] = resolved
                } else {
                    headers[key] = resolved
                    keyIndex["content-length"] = key
                }
                continue
            }

            // Track Host header occurrences for RFC 9110 §7.2 validation.
            if lowerKey == "host" {
                hostHeaderCount += 1
            }

            // RFC 9110 §5.3: Combine duplicate field lines with comma-separated values.
            if let existingKey = keyIndex[lowerKey] {
                headers[existingKey] = "\(headers[existingKey]!), \(value)"
            } else {
                headers[key] = value
                keyIndex[lowerKey] = key
            }
        }

        // RFC 9110 §7.2: Reject requests with multiple Host headers (any version)
        // or missing Host header (HTTP/1.1 only).
        if hostHeaderCount > 1 {
            return .invalid(.multipleHostHeaders)
        }
        if httpVersion == "HTTP/1.1" && hostHeaderCount == 0 {
            return .invalid(.missingHostHeader)
        }

        let contentLength = contentLengthValue ?? 0

        let bodyOffset = data.distance(from: data.startIndex, to: separatorRange.upperBound)

        return .parsed(ParsedHeaders(
            method: method,
            target: target,
            httpVersion: httpVersion,
            headers: headers,
            contentLength: contentLength,
            bodyOffset: bodyOffset
        ))
    }

    /// Validates a Content-Length header value per RFC 9110 §8.6 / RFC 7230 §3.3.3.
    ///
    /// A Content-Length value may be a single number or a comma-separated list of
    /// identical values (e.g. "5, 5"). Each element must be a non-negative decimal
    /// integer (ASCII digits only — no +, ., 0x, etc.).
    ///
    /// - Parameters:
    ///   - value: The raw header value string.
    ///   - existing: A previously parsed Content-Length value, if any.
    /// - Returns: The validated content length as an integer.
    /// - Throws: ``HTTPRequestParseError/invalidContentLength`` or ``HTTPRequestParseError/conflictingContentLength``.
    static func validateContentLength(_ value: String, existing: Int64?) throws(HTTPRequestParseError) -> Int64 {
        let parts = value.split(separator: ",", omittingEmptySubsequences: false).map {
            $0.trimmingCharacters(in: .whitespaces)
        }
        guard let first = parts.first,
              !first.isEmpty,
              first.allSatisfy({ $0.isASCII && $0.isNumber }),
              let cl = Int64(first),
              cl >= 0
        else {
            throw HTTPRequestParseError.invalidContentLength
        }
        // All parts in a comma-separated list must represent the same integer value
        for part in parts.dropFirst() {
            guard !part.isEmpty,
                  part.allSatisfy({ $0.isASCII && $0.isNumber }),
                  let partValue = Int64(part),
                  partValue == cl
            else {
                throw HTTPRequestParseError.conflictingContentLength
            }
        }
        if let existing = existing, existing != cl {
            throw HTTPRequestParseError.conflictingContentLength
        }
        return cl
    }

    /// Validates that a string matches the HTTP-version format: `HTTP/DIGIT.DIGIT`.
    private static func isValidHTTPVersion(_ version: String) -> Bool {
        let prefix = "HTTP/"
        guard version.hasPrefix(prefix) else { return false }
        let rest = version.dropFirst(prefix.count)
        let parts = rest.split(separator: ".", maxSplits: 1)
        guard parts.count == 2,
              parts[0].count == 1, parts[0].first?.isASCII == true, parts[0].first?.isNumber == true,
              parts[1].count == 1, parts[1].first?.isASCII == true, parts[1].first?.isNumber == true
        else { return false }
        return true
    }

    /// Returns whether a character is a valid HTTP token character (RFC 9110 §5.6.2).
    ///
    /// `tchar = "!" / "#" / "$" / "%" / "&" / "'" / "*" / "+" / "-" / "." /
    ///           "^" / "_" / "`" / "|" / "~" / DIGIT / ALPHA`
    private static func isTokenChar(_ c: Character) -> Bool {
        guard let ascii = c.asciiValue else { return false }
        switch ascii {
        case UInt8(ascii: "A")...UInt8(ascii: "Z"),
             UInt8(ascii: "a")...UInt8(ascii: "z"),
             UInt8(ascii: "0")...UInt8(ascii: "9"):
            return true
        case UInt8(ascii: "!"), UInt8(ascii: "#"), UInt8(ascii: "$"), UInt8(ascii: "%"),
             UInt8(ascii: "&"), UInt8(ascii: "'"), UInt8(ascii: "*"), UInt8(ascii: "+"),
             UInt8(ascii: "-"), UInt8(ascii: "."), UInt8(ascii: "^"), UInt8(ascii: "_"),
             UInt8(ascii: "`"), UInt8(ascii: "|"), UInt8(ascii: "~"):
            return true
        default:
            return false
        }
    }
}
