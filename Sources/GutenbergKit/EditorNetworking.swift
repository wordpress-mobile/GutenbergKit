import Foundation

public protocol EditorNetworkingClient {
    /// Asks the delegate to perform the network request on behalf of the editor.
    func send(_ request: EditorNetworkRequest) async throws -> EditorNetworkResponse
}

/// An HTTP network request.
public struct EditorNetworkRequest: Sendable {
    public var method: String
    public var url: URL

    // TODO: Add support for remainig fields
    // public var query: [(String, String?)]?
    // public var body: Data?
    // public var headers: [String: String]?
    // public var id: String?
}

/// A response with an associated value and metadata.
public struct EditorNetworkResponse: Sendable {
    public let urlResponse: URLResponse
    public let data: Data?

    public init(urlResponse: URLResponse, data: Data? = nil) {
        self.urlResponse = urlResponse
        self.data = data
    }
}
