import Foundation
import OSLog

/// A protocol for making authenticated HTTP requests to the WordPress REST API.
public protocol EditorHTTPClientProtocol: Sendable {
    func perform(_ urlRequest: URLRequest) async throws -> (Data, HTTPURLResponse)
    func download(_ urlRequest: URLRequest) async throws -> (URL, HTTPURLResponse)
}

/// A delegate for observing HTTP requests made by the editor.
///
/// Implement this protocol to inspect or log all network requests.
public protocol EditorHTTPClientDelegate {
    func didPerformRequest(_ request: URLRequest, response: URLResponse, data: Data)
}

/// A WordPress REST API error response.
struct WPError: Decodable {
    let code: String
    let message: String
}

/// An HTTP client for making authenticated requests to the WordPress REST API.
///
/// This actor handles request signing, error parsing, and response validation.
/// All requests are automatically authenticated using the provided authorization header.
public actor EditorHTTPClient: EditorHTTPClientProtocol {

    /// Errors that can occur during HTTP requests.
    enum ClientError: Error {
        /// The server returned a WordPress-formatted error response.
        case wpError(WPError)
        /// A file download failed with the given HTTP status code.
        case downloadFailed(statusCode: Int)
        /// An unexpected error occurred with the given response data and status code.
        case unknown(response: Data, statusCode: Int)
    }
    
    private let urlSession: URLSession
    private let authHeader: String
    private let delegate: EditorHTTPClientDelegate?
    private let requestTimeout: TimeInterval

    public init(
        urlSession: URLSession,
        authHeader: String,
        delegate: EditorHTTPClientDelegate? = nil,
        requestTimeout: TimeInterval = 60 // `URLRequest` default
    ) {
        self.urlSession = urlSession
        self.authHeader = authHeader
        self.delegate = delegate
        self.requestTimeout = requestTimeout
    }

    public func perform(_ urlRequest: URLRequest) async throws -> (Data, HTTPURLResponse) {
        var mutableRequest = urlRequest
        mutableRequest.setValue(self.authHeader, forHTTPHeaderField: "Authorization")
        mutableRequest.timeoutInterval = self.requestTimeout

        let (data, response) = try await self.urlSession.data(for: mutableRequest)
        self.delegate?.didPerformRequest(mutableRequest, response: response, data: data)

        let httpResponse = response as! HTTPURLResponse

        guard 200...299 ~= httpResponse.statusCode else {
            Logger.http.error("📡 HTTP error fetching \(mutableRequest.url!.absoluteString): \(httpResponse.statusCode)")

            if let wpError = try? JSONDecoder().decode(WPError.self, from: data) {
                throw ClientError.wpError(wpError)
            }

            throw ClientError.unknown(response: data, statusCode: httpResponse.statusCode)
        }

        return (data, httpResponse)
    }

    public func download(_ urlRequest: URLRequest) async throws -> (URL, HTTPURLResponse) {
        var mutableRequest = urlRequest
        mutableRequest.addValue(self.authHeader, forHTTPHeaderField: "Authorization")
        mutableRequest.timeoutInterval = self.requestTimeout

        let (url, response) = try await self.urlSession.download(for: mutableRequest)

        let httpResponse = response as! HTTPURLResponse

        guard 200...299 ~= httpResponse.statusCode else {
            Logger.http.error("📡 HTTP error fetching \(mutableRequest.url!.absoluteString): \(httpResponse.statusCode)")

            throw ClientError.downloadFailed(statusCode: httpResponse.statusCode)
        }

        return (url, response as! HTTPURLResponse)
    }
}
