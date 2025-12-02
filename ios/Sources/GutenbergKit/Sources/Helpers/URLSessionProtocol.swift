import Foundation

/// Protocol for network operations, allowing dependency injection for testing
public protocol URLSessionProtocol: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
    func download(for request: URLRequest, delegate: (any URLSessionTaskDelegate)?) async throws -> (URL, URLResponse)
}

extension URLSession: URLSessionProtocol {}
