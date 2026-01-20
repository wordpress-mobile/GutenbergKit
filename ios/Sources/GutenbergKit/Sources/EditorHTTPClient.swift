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
    func didPerformRequest(_ request: URLRequest, response: URLResponse, data: EditorResponseData)
}

public enum EditorResponseData {
    case bytes(Data)
    case file(URL)
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

    /// The base user agent string identifying the platform.
    private static let baseUserAgent: String = {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        #if os(iOS)
        return "iOS/\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
        #elseif os(macOS)
        return "macOS/\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
        #else
        return "Darwin"
        #endif
    }()

    private let urlSession: URLSessionProtocol
    private let authHeader: String
    private let delegate: EditorHTTPClientDelegate?
    private let requestTimeout: TimeInterval?

    public init(
        urlSession: URLSessionProtocol,
        authHeader: String,
        delegate: EditorHTTPClientDelegate? = nil,
        requestTimeout: TimeInterval? = nil
    ) {
        self.urlSession = urlSession
        self.authHeader = authHeader
        self.delegate = delegate
        self.requestTimeout = requestTimeout
    }

    public func perform(_ urlRequest: URLRequest) async throws -> (Data, HTTPURLResponse) {

        let configuredRequest = self.configureRequest(urlRequest)
        let (data, response) = try await self.urlSession.data(for: configuredRequest)
        self.delegate?.didPerformRequest(configuredRequest, response: response, data: .bytes(data))

        let httpResponse = response as! HTTPURLResponse

        guard 200...299 ~= httpResponse.statusCode else {
            Logger.http.error("📡 HTTP error fetching \(configuredRequest.url!.absoluteString): \(httpResponse.statusCode)")

            if let wpError = try? JSONDecoder().decode(WPError.self, from: data) {
                throw ClientError.wpError(wpError)
            }

            throw ClientError.unknown(response: data, statusCode: httpResponse.statusCode)
        }

        return (data, httpResponse)
    }

    public func download(_ urlRequest: URLRequest) async throws -> (URL, HTTPURLResponse) {

        let configuredRequest = self.configureRequest(urlRequest)
        let (url, response) = try await self.urlSession.download(for: configuredRequest, delegate: nil)
        self.delegate?.didPerformRequest(configuredRequest, response: response, data: .file(url))

        let httpResponse = response as! HTTPURLResponse

        guard 200...299 ~= httpResponse.statusCode else {
            Logger.http.error("📡 HTTP error fetching \(configuredRequest.url!.absoluteString): \(httpResponse.statusCode)")

            throw ClientError.downloadFailed(statusCode: httpResponse.statusCode)
        }

        return (url, response as! HTTPURLResponse)
    }

    private func configureRequest(_ request: URLRequest) -> URLRequest {
        var mutableRequest = request
        mutableRequest.addValue(self.authHeader, forHTTPHeaderField: "Authorization")
        mutableRequest.addValue("\(Self.baseUserAgent) GutenbergKit/\(GutenbergKitVersion.version)", forHTTPHeaderField: "User-Agent")

        if let requestTimeout {
            mutableRequest.timeoutInterval = requestTimeout
        }

        // Prevent wordpress_logged_in cookies from being sent, which could interfere with
        // application password authentication in the Authorization header.
        // See: https://github.com/wordpress-mobile/GutenbergKit/commit/30ebac210924ecc8e9dee3980c101ef24b1befa6
        mutableRequest.httpShouldHandleCookies = false

        return mutableRequest
    }
}
