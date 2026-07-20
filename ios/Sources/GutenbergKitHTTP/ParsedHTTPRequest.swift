import Foundation

/// A parsed HTTP/1.1 request, either partial (headers only) or complete (headers and body).
///
/// - `.partial`: Headers have been received but the body is still pending.
/// - `.complete`: All data has been received. The body, if present, is accessible
///   via ``RequestBody`` which provides stream-based access regardless of backing storage.
public enum ParsedHTTPRequest: Sendable, Equatable {
    /// Headers have been received but the body has not yet been fully received.
    case partial(method: String, target: String, httpVersion: String, headers: [String: String])
    /// All data has been received (headers and body).
    case complete(method: String, target: String, httpVersion: String, headers: [String: String], body: RequestBody?)
}

// MARK: - Convenience Properties

extension ParsedHTTPRequest {

    /// The HTTP method (e.g., "GET", "POST", "PUT", "DELETE").
    public var method: String {
        switch self {
        case .partial(let method, _, _, _): return method
        case .complete(let method, _, _, _, _): return method
        }
    }

    /// The request-target from the HTTP request line, per RFC 9112 Section 3 (e.g., "/wp/v2/posts?per_page=10").
    public var target: String {
        switch self {
        case .partial(_, let target, _, _): return target
        case .complete(_, let target, _, _, _): return target
        }
    }

    /// The path portion of ``target``, without the query component
    /// (e.g., "/wp/v2/posts" for "/wp/v2/posts?per_page=10").
    ///
    /// Use this for routing — matching against ``target`` fails as soon as a
    /// client appends a query string.
    public var path: String {
        let target = target
        guard let separator = target.firstIndex(of: "?") else { return target }
        return String(target[target.startIndex..<separator])
    }

    /// The query component of ``target``, including the leading "?"
    /// (e.g., "?per_page=10"), or an empty string when there is no query.
    ///
    /// A bare trailing "?" carries no parameters and yields an empty string, so
    /// the value can be appended to an upstream URL unconditionally.
    public var query: String {
        let target = target
        guard let separator = target.firstIndex(of: "?") else { return "" }
        let value = String(target[target.index(after: separator)...])
        return value.isEmpty ? "" : "?\(value)"
    }

    /// The HTTP-version from the request line (e.g., "HTTP/1.1"), per RFC 9112 §2.3.
    public var httpVersion: String {
        switch self {
        case .partial(_, _, let httpVersion, _): return httpVersion
        case .complete(_, _, let httpVersion, _, _): return httpVersion
        }
    }

    /// The raw HTTP headers dictionary. Header names preserve their original casing,
    /// which makes dictionary lookups case-sensitive. Use ``header(_:)`` for safe
    /// case-insensitive lookup, or ``allHeaders`` for iteration.
    var headers: [String: String] {
        switch self {
        case .partial(_, _, _, let headers): return headers
        case .complete(_, _, _, let headers, _): return headers
        }
    }

    /// The number of headers in the request.
    public var headerCount: Int { headers.count }

    /// All headers as an ordered list of name-value pairs, suitable for iteration.
    ///
    /// Use this instead of accessing the headers dictionary directly when you need
    /// to enumerate or filter headers. For single-header lookup, prefer ``header(_:)``.
    public var allHeaders: [(name: String, value: String)] {
        headers.map { (name: $0.key, value: $0.value) }
    }

    /// The request body, or `nil` if there is no body or if the request is partial.
    public var body: RequestBody? {
        switch self {
        case .partial: return nil
        case .complete(_, _, _, _, let body): return body
        }
    }

    /// Whether all data has been received.
    public var isComplete: Bool {
        if case .complete = self { return true }
        return false
    }

    /// Returns the value of the first header matching the given name (case-insensitive).
    public func header(_ name: String) -> String? {
        let lowered = name.lowercased()
        return headers.first(where: { $0.key.lowercased() == lowered })?.value
    }

    /// Parses the body as `multipart/form-data` and returns the individual parts.
    ///
    /// Extracts the boundary from the `Content-Type` header automatically.
    /// Part bodies are lazy references back to the original request body — no
    /// part data is copied during parsing. Bytes are only read when a part's
    /// body is accessed via ``RequestBody/makeInputStream()``.
    ///
    /// - Returns: The parsed parts.
    /// - Throws: ``MultipartParseError`` if the Content-Type is not `multipart/form-data`,
    ///   the body is missing, or the multipart structure is malformed.
    public func multipartParts() throws -> [MultipartPart] {
        guard let contentType = header("Content-Type"),
              let boundary = Self.extractBoundary(from: contentType) else {
            throw MultipartParseError.notMultipartFormData
        }

        guard let body else {
            throw MultipartParseError.missingBody
        }

        if let data = body.inMemoryData {
            // In-memory: scan the data directly (already in memory, no extra allocation).
            return try MultipartPart.parse(
                source: body,
                bodyData: data,
                bodyFileOffset: 0,
                boundary: boundary
            )
        } else {
            // File-backed: scan in fixed-size chunks to avoid loading the entire
            // body into memory. Memory usage is O(chunk_size) regardless of body size.
            return try MultipartPart.parseChunked(source: body, boundary: boundary)
        }
    }

    /// Extracts the boundary parameter from a `multipart/form-data` Content-Type value.
    ///
    /// Uses ``HeaderValue/extractParameter(_:from:)`` for the actual extraction,
    /// then validates the result against RFC 2046 §5.1.1 boundary constraints.
    private static func extractBoundary(from contentType: String) -> String? {
        guard contentType.lowercased().hasPrefix("multipart/form-data") else {
            return nil
        }

        guard let boundary = HeaderValue.extractParameter("boundary", from: contentType) else {
            return nil
        }

        guard !boundary.isEmpty, boundary.count <= 70 else { return nil }
        // RFC 2046 §5.1.1: boundary characters must be from the bchars set.
        guard boundary.allSatisfy({ isBoundaryChar($0) }) else { return nil }
        // RFC 2046 §5.1.1: space cannot be the last character of a boundary.
        guard !boundary.hasSuffix(" ") else { return nil }
        return boundary
    }

    /// Returns whether a character is valid in a MIME boundary (RFC 2046 §5.1.1 bchars).
    ///
    /// `bchars = bcharsnospace / " "`
    /// `bcharsnospace = DIGIT / ALPHA / "'" / "(" / ")" / "+" / "_" / "," / "-" / "." / "/" / ":" / "=" / "?"`
    private static func isBoundaryChar(_ c: Character) -> Bool {
        guard let ascii = c.asciiValue else { return false }
        switch ascii {
        case UInt8(ascii: "A")...UInt8(ascii: "Z"),
             UInt8(ascii: "a")...UInt8(ascii: "z"),
             UInt8(ascii: "0")...UInt8(ascii: "9"):
            return true
        case UInt8(ascii: "'"), UInt8(ascii: "("), UInt8(ascii: ")"),
             UInt8(ascii: "+"), UInt8(ascii: "_"), UInt8(ascii: ","),
             UInt8(ascii: "-"), UInt8(ascii: "."), UInt8(ascii: "/"),
             UInt8(ascii: ":"), UInt8(ascii: "="), UInt8(ascii: "?"),
             UInt8(ascii: " "):
            return true
        default:
            return false
        }
    }

    #if canImport(Network)
    /// Converts this parsed request into a `URLRequest` using the given base URL.
    ///
    /// The `target` (path and query) is resolved against `baseURL` to produce the
    /// final request URL. If a body is present, it is attached as an `httpBodyStream`.
    ///
    /// - Parameter baseURL: The base URL to resolve the request target against.
    /// - Returns: A configured `URLRequest`, or `nil` if the URL cannot be constructed.
    public func urlRequest(relativeTo baseURL: URL) -> URLRequest? {
        guard let url = URL(string: target, relativeTo: baseURL) else {
            return nil
        }

        var request = URLRequest(url: url)
        request.httpMethod = method

        // RFC 9110 §7.6.1: hop-by-hop headers must not be forwarded by proxies.
        // "proxy-authorization" and "relay-authorization" carry the proxy's
        // own bearer token and must not be forwarded to the upstream server.
        // "authorization" is intentionally kept so that the client's own
        // credentials (e.g. HTTP Basic for the upstream server) pass through.
        var hopByHop: Set<String> = [
            "host", "connection", "transfer-encoding", "keep-alive",
            "proxy-connection", "te", "upgrade", "trailer",
            "proxy-authorization", "relay-authorization",
        ]

        // Headers listed in Connection are also hop-by-hop (RFC 9110 §7.6.1).
        if let connectionValue = header("Connection") {
            for name in connectionValue.split(separator: ",") {
                hopByHop.insert(name.trimmingCharacters(in: .whitespaces).lowercased())
            }
        }

        for (key, value) in headers {
            guard !hopByHop.contains(key.lowercased()) else { continue }
            request.setValue(value, forHTTPHeaderField: key)
        }

        if let body {
            request.httpBodyStream = try? body.makeInputStream()
        }

        return request
    }
    #endif
}
