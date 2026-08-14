#if canImport(Network)

import Foundation
import Network

/// Errors thrown by ``HTTPServer``.
public enum HTTPServerError: Error, LocalizedError, Sendable {
    /// The server failed to bind to the requested port.
    case failedToStart
    /// The listener did not become ready within the start timeout (e.g. it was
    /// stuck in `.waiting`). Bounds the bind wait so a caller — such as the
    /// editor load — isn't hung indefinitely on a listener that never binds.
    case startTimeout
    /// The connection closed before a complete request was received.
    case connectionClosed
    /// The read timeout expired before a complete request was received.
    case readTimeout
    /// The request failed authentication (checked after headers, before body).
    case authenticationFailed
    /// The request method requires a Content-Length header but none was provided.
    case lengthRequired
    /// An auth-exempt request (OPTIONS) carried a body. CORS preflights are
    /// bodyless, so a body on the auth-exempt path is rejected rather than read.
    case unexpectedBody
    /// A network-level error occurred on the connection.
    case networkError(NWError)

    public var errorDescription: String? {
        switch self {
        case .failedToStart: "Failed to start HTTP server"
        case .startTimeout: "HTTP server listener did not become ready within the start timeout"
        case .connectionClosed: "Connection closed before request was complete"
        case .readTimeout: "Read timeout expired before request was complete"
        case .authenticationFailed: "Request failed authentication"
        case .lengthRequired: "Content-Length header is required for this method"
        case .unexpectedBody: "Request method must not carry a body"
        case .networkError(let error): "Network error: \(error.localizedDescription)"
        }
    }
}

#endif // canImport(Network)
