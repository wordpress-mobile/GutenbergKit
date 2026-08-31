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
                // anyway: the editor loads from `file://` (Origin `null`), which
                // can't be cleanly allowlisted.
                ("Access-Control-Allow-Origin", "*"),
                ("Access-Control-Allow-Methods", "GET, POST, PUT, PATCH, DELETE, OPTIONS"),
                ("Access-Control-Allow-Headers", "Accept, Authorization, Content-Type, Relay-Authorization, X-HTTP-Method-Override"),
                ("Access-Control-Max-Age", "86400"),
            ]
        }
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
