import Foundation

/// CORS behavior for an ``HTTPServer``.
public enum CORSPolicy: Sendable {
    /// No CORS headers are added (the default).
    case none

    /// Permissive CORS for a loopback-only server serving a WebView: allows any
    /// origin and the methods/headers this library's clients use. The server
    /// answers OPTIONS preflight requests itself and stamps these headers on
    /// every response — including ones it generates internally (timeouts, parse
    /// errors) that never reach the handler.
    case permissive

    /// Headers added to every response under this policy.
    var responseHeaders: [(String, String)] {
        switch self {
        case .none:
            []
        case .permissive:
            [
                // `*` (any origin) rather than echoing a specific origin is
                // deliberate, and safe here — not an oversight to tighten. The
                // server is loopback-only, and every non-OPTIONS request is gated
                // by a per-session random bearer token stored only in the editor
                // origin's `localStorage`/`window.GBKit`, which is origin-scoped
                // and unreadable by any other origin — so no cross-origin can
                // obtain it. `*` only governs whether a *token-holding* origin may
                // read the response, and the sole token-holder is the editor
                // itself, the legitimate client. Echoing the origin isn't viable
                // anyway: the editor loads from `file://` and WebKit sends
                // `Origin: file://`, an opaque origin that can't be cleanly
                // allowlisted.
                ("Access-Control-Allow-Origin", "*"),
                ("Access-Control-Allow-Methods", "GET, POST, PUT, PATCH, DELETE, OPTIONS"),
                ("Access-Control-Allow-Headers", Self.allowedRequestHeadersValue),
                ("Access-Control-Max-Age", "86400"),
            ]
        }
    }

    /// The request headers a browser may send under ``permissive``.
    ///
    /// Only headers a browser actually announces in a preflight belong here.
    /// `Accept` does not: api-fetch's value (`application/json, */*;q=0.1`)
    /// carries none of the CORS-unsafe bytes and is well under the 128-byte
    /// cap, so it is safelisted and never reaches the preflight.
    ///
    /// Enumerated rather than echoed back from `Access-Control-Request-Headers`
    /// because this governs what a caller may *send*, and the relay forwards
    /// most request headers upstream with the site credential attached. A
    /// header announced but not listed here is refused by the browser, which
    /// reports only an opaque CORS error — see ``unallowedHeaders(announced:)``
    /// for the diagnostic that makes that legible.
    static let allowedRequestHeaders = [
        "Authorization", "Content-Type", "Relay-Authorization", "X-HTTP-Method-Override",
    ]

    /// ``allowedRequestHeaders`` as the header value, joined once rather than on
    /// every response — `responseHeaders` is evaluated for each one.
    static let allowedRequestHeadersValue = allowedRequestHeaders.joined(separator: ", ")

    /// The headers a preflight announced that this policy will not allow.
    ///
    /// A preflight announces exactly the headers that are not CORS-safelisted,
    /// so anything reported here is a header the caller intends to send and the
    /// browser is about to refuse — failing the request before it reaches the
    /// handler, with nothing on the wire to explain why.
    func unallowedHeaders(announced: String?) -> [String] {
        guard case .permissive = self, let announced else { return [] }

        let allowed = Set(Self.allowedRequestHeaders.map { $0.lowercased() })
        return announced
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { !$0.isEmpty && !allowed.contains($0) }
    }
}

extension HTTPResponse {
    /// Returns a copy with `newHeaders` appended, skipping any whose name
    /// (case-insensitive) is already present.
    func addingHeadersIfAbsent(_ newHeaders: [(String, String)]) -> HTTPResponse {
        guard !newHeaders.isEmpty else { return self }
        let existing = Set(headers.map { $0.0.lowercased() })
        let toAdd = newHeaders.filter { !existing.contains($0.0.lowercased()) }
        guard !toAdd.isEmpty else { return self }
        return HTTPResponse(status: status, statusText: statusText, headers: headers + toAdd, body: body)
    }
}
