import Foundation

/// Protocol for network operations, allowing dependency injection for testing
public protocol URLSessionProtocol: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)

    /// Like ``data(for:)``, with a delegate for the one task the request runs as.
    ///
    /// GutenbergKit passes one to report the task to an ``EditorHTTPClientDelegate``.
    /// `URLSession` implements this itself; any other conformer gets a default that
    /// drops the delegate, so its requests go unreported.
    func data(for request: URLRequest, delegate: (any URLSessionTaskDelegate)?) async throws -> (Data, URLResponse)

    func download(for request: URLRequest, delegate: (any URLSessionTaskDelegate)?) async throws -> (URL, URLResponse)
}

public extension URLSessionProtocol {
    func data(for request: URLRequest, delegate: (any URLSessionTaskDelegate)?) async throws -> (Data, URLResponse) {
        try await data(for: request)
    }
}

extension URLSession: URLSessionProtocol {}
