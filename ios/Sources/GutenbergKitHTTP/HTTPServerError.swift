#if canImport(Network)

import Foundation
import Network

/// Errors thrown by ``HTTPServer``.
public enum HTTPServerError: Error, LocalizedError, Sendable {
    /// The server failed to bind to the requested port.
    case failedToStart
    /// The connection closed before a complete request was received.
    case connectionClosed
    /// The read timeout expired before a complete request was received.
    case readTimeout
    /// The request failed authentication (checked after headers, before body).
    case authenticationFailed
    /// The request method requires a Content-Length header but none was provided.
    case lengthRequired
    /// A network-level error occurred on the connection.
    case networkError(NWError)

    public var errorDescription: String? {
        switch self {
        case .failedToStart: "Failed to start HTTP server"
        case .connectionClosed: "Connection closed before request was complete"
        case .readTimeout: "Read timeout expired before request was complete"
        case .authenticationFailed: "Request failed authentication"
        case .lengthRequired: "Content-Length header is required for this method"
        case .networkError(let error): "Network error: \(error.localizedDescription)"
        }
    }
}

#endif // canImport(Network)
