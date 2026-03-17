import Foundation

/// Converts a `StaticString` to a `String`.
///
/// The Swift standard library does not provide a direct `String.init(_ : StaticString)` initializer.
/// This extension bridges that gap so that APIs returning `StaticString` for pointer-stability
/// reasons (e.g., `HTTPResponse.defaultStatusText`, `HTTPRequestParseError.httpStatusText`) can
/// be used naturally where a `String` is expected.
extension String {
    init(_ staticString: StaticString) {
        self = staticString.withUTF8Buffer { String(decoding: $0, as: UTF8.self) }
    }
}

/// An HTTP response to send back to a client.
public struct HTTPResponse: Sendable {

    /// The HTTP status code (e.g., 200, 404, 500).
    public let status: Int

    /// The HTTP reason phrase (e.g., "OK", "Not Found").
    ///
    /// When no explicit override was provided at init, this returns the standard
    /// phrase for `status` from `defaultStatusText(for:)`.
    public var statusText: String {
        statusTextOverride ?? String(Self.defaultStatusText(for: status))
    }

    /// Additional response headers. `Content-Length` is always set to the actual body size
    /// during serialization (any caller-provided value is replaced). `Connection` is added
    /// automatically if not already present.
    public let headers: [(String, String)]

    /// The response body.
    ///
    /// The entire body is held in memory. This is fine for the current use case
    /// (Gutenberg REST API payloads — JSON, HTML, CSS, JS) which are small. If
    /// large responses (e.g., media downloads) need to be proxied in the future,
    /// this could be replaced with a streaming abstraction similar to `RequestBody`.
    public let body: Data

    /// Caller-provided reason phrase override, or `nil` to use the default.
    private let statusTextOverride: String?

    /// Creates an HTTP response.
    ///
    /// - Parameters:
    ///   - status: The HTTP status code.
    ///   - statusText: The reason phrase. Defaults to a standard phrase for common status codes.
    ///   - headers: Additional headers to include. Defaults to `Content-Type: text/plain`.
    ///   - body: The response body. Defaults to empty.
    public init(
        status: Int,
        statusText: String? = nil,
        headers: [(String, String)] = [("Content-Type", "text/plain")],
        body: Data = Data()
    ) {
        self.status = status
        self.statusTextOverride = statusText
        self.headers = headers
        self.body = body
    }

    #if canImport(Network)
    /// RFC 9110 §7.6.1: hop-by-hop headers that must not be forwarded by proxies.
    private static let responseHopByHop: Set<String> = [
        "connection", "transfer-encoding", "keep-alive",
        "proxy-connection", "te", "upgrade", "trailer",
    ]

    public init(_ response: (Data, URLResponse)) {
        guard let httpResponse = response.1 as? HTTPURLResponse else {
            self.status = 502
            self.statusTextOverride = "Bad Gateway"
            self.headers = [("Content-Type", "text/plain")]
            self.body = Data("Upstream returned a non-HTTP response".utf8)
            return
        }
        self.status = httpResponse.statusCode
        self.statusTextOverride = nil

        // Strip hop-by-hop headers (RFC 9110 §7.6.1) and the upstream Content-Length,
        // then set Content-Length from the actual body size. This ensures `headers` is
        // always truthful — consumers reading it directly (without going through
        // `serialized()`) won't see a stale upstream value.
        let upstream = (httpResponse.allHeaderFields as? [String: String] ?? [:])
        self.headers = upstream.compactMap { key, value in
            let lower = key.lowercased()
            guard !Self.responseHopByHop.contains(lower),
                  lower != "content-length" else { return nil }
            return (key, value)
        } + [("Content-Length", "\(response.0.count)")]
        self.body = response.0
    }
    #endif

    /// Headers excluded during serialization: hop-by-hop headers (RFC 9110 §7.6.1)
    /// plus headers that are always recalculated (Content-Length, Date, Server).
    private static let serializationExcluded: Set<String> = [
        "content-length", "connection", "transfer-encoding", "keep-alive",
        "proxy-connection", "te", "upgrade", "trailer",
        "date", "server",
    ]

    /// Serializes the response into raw HTTP/1.1 bytes ready to send on the wire.
    public func serialized() -> Data {
        var allHeaders = headers.filter { !Self.serializationExcluded.contains($0.0.lowercased()) }
        allHeaders.append(("Content-Length", "\(body.count)"))
        allHeaders.append(("Connection", "close"))
        allHeaders.append(("Date", Self.httpDate()))
        allHeaders.append(("Server", "GutenbergKit"))

        // Strip CR/LF from header names and values to prevent header injection.
        let headerString = allHeaders.map { "\(Self.sanitize($0.0)): \(Self.sanitize($0.1))" }.joined(separator: "\r\n")
        // RFC 9112 §4: status-code = 3DIGIT — always zero-pad to 3 digits.
        let statusCode = String(format: "%03d", min(max(status, 0), 999))
        let head = "HTTP/1.1 \(statusCode) \(Self.sanitize(statusText))\r\n\(headerString)\r\n\r\n"

        var data = Data(head.utf8)
        data.append(body)
        return data
    }

    /// Removes control characters (including CR, LF, NUL, BEL, etc.) to prevent
    /// HTTP response header injection and malformed output per RFC 9112 §4.
    /// HTAB (0x09) and non-ASCII characters (obs-text, 0x80+) are preserved,
    /// as RFC 9110 §5.5 explicitly allows them in header field values.
    private static func sanitize(_ value: String) -> String {
        value.filter { char in
            guard let ascii = char.asciiValue else { return true }  // Keep non-ASCII
            if ascii == 0x09 { return true }                        // Keep HTAB
            return ascii >= 0x20 && ascii != 0x7F                   // Strip CTLs and DEL
        }
    }

    private static let httpDateLock = NSLock()
    private static let httpDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
        return formatter
    }()

    /// Formats the current time as an HTTP-date per RFC 9110 §5.6.7.
    private static func httpDate() -> String {
        httpDateLock.lock()
        defer { httpDateLock.unlock() }
        return httpDateFormatter.string(from: Date())
    }

    /// Returns this response's reason phrase as a `StaticString`.
    ///
    /// This is the same table as `defaultStatusText(for:)`, exposed for callers
    /// (like the JNI bridge) that need a stable pointer without allocation.
    var staticStatusText: StaticString {
        Self.defaultStatusText(for: status)
    }

    /// Standard English reason phrases per RFC 9110 / RFC 9112 §4.
    ///
    /// This avoids `HTTPURLResponse.localizedString(forStatusCode:)` which may
    /// return locale-dependent translations.
    static func defaultStatusText(for status: Int) -> StaticString {
        switch status {
        // 1xx Informational
        case 100: "Continue"
        case 101: "Switching Protocols"
        case 102: "Processing"
        case 103: "Early Hints"
        // 2xx Success
        case 200: "OK"
        case 201: "Created"
        case 202: "Accepted"
        case 203: "Non-Authoritative Information"
        case 204: "No Content"
        case 205: "Reset Content"
        case 206: "Partial Content"
        case 207: "Multi-Status"
        case 208: "Already Reported"
        case 226: "IM Used"
        // 3xx Redirection
        case 300: "Multiple Choices"
        case 301: "Moved Permanently"
        case 302: "Found"
        case 303: "See Other"
        case 304: "Not Modified"
        case 307: "Temporary Redirect"
        case 308: "Permanent Redirect"
        // 4xx Client Error
        case 400: "Bad Request"
        case 401: "Unauthorized"
        case 402: "Payment Required"
        case 403: "Forbidden"
        case 404: "Not Found"
        case 405: "Method Not Allowed"
        case 406: "Not Acceptable"
        case 407: "Proxy Authentication Required"
        case 408: "Request Timeout"
        case 409: "Conflict"
        case 410: "Gone"
        case 411: "Length Required"
        case 412: "Precondition Failed"
        case 413: "Content Too Large"
        case 414: "URI Too Long"
        case 415: "Unsupported Media Type"
        case 416: "Range Not Satisfiable"
        case 417: "Expectation Failed"
        case 421: "Misdirected Request"
        case 422: "Unprocessable Content"
        case 423: "Locked"
        case 424: "Failed Dependency"
        case 425: "Too Early"
        case 426: "Upgrade Required"
        case 428: "Precondition Required"
        case 429: "Too Many Requests"
        case 431: "Request Header Fields Too Large"
        case 451: "Unavailable For Legal Reasons"
        // 5xx Server Error
        case 500: "Internal Server Error"
        case 501: "Not Implemented"
        case 502: "Bad Gateway"
        case 503: "Service Unavailable"
        case 504: "Gateway Timeout"
        case 505: "HTTP Version Not Supported"
        case 506: "Variant Also Negotiates"
        case 507: "Insufficient Storage"
        case 508: "Loop Detected"
        case 510: "Not Extended"
        case 511: "Network Authentication Required"
        default: "Unknown"
        }
    }
}
