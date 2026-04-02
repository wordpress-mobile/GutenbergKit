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
        let url = configuredRequest.url!.absoluteString
        let method = configuredRequest.httpMethod ?? "GET"
        Logger.http.debug("📡 \(method) \(url)")
        Logger.http.debug("📡 Request headers: \(self.redactHeaders(configuredRequest.allHTTPHeaderFields))")

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await self.urlSession.data(for: configuredRequest)
        } catch {
            Logger.http.error("📡 \(method) \(url) – network error: \(error.localizedDescription)")
            throw error
        }

        self.delegate?.didPerformRequest(configuredRequest, response: response, data: .bytes(data))

        let httpResponse = response as! HTTPURLResponse
        Logger.http.debug("📡 \(method) \(url) – \(httpResponse.statusCode) (\(data.count) bytes)")
        Logger.http.debug("📡 Response headers: \(self.redactHeaders(httpResponse.allHeaderFields))")

        guard 200...299 ~= httpResponse.statusCode else {
            Logger.http.error("📡 \(method) \(url) – HTTP error: \(httpResponse.statusCode)")
            // Log the raw body to aid debugging unexpected error formats.
            // This is acceptable because the WordPress REST API should never
            // include sensitive information (tokens, credentials) in responses.
            Logger.http.error("📡 Response body: \(String(data: data, encoding: .utf8) ?? "<non-utf8>")")

            if let wpError = try? JSONDecoder().decode(WPError.self, from: data) {
                Logger.http.error("📡 WP error – code: \(wpError.code), message: \(wpError.message)")
                throw ClientError.wpError(wpError)
            }

            throw ClientError.unknown(response: data, statusCode: httpResponse.statusCode)
        }

        return (data, httpResponse)
    }

    public func download(_ urlRequest: URLRequest) async throws -> (URL, HTTPURLResponse) {

        let configuredRequest = self.configureRequest(urlRequest)
        let requestURL = configuredRequest.url!.absoluteString
        Logger.http.debug("📡 DOWNLOAD \(requestURL)")
        Logger.http.debug("📡 Request headers: \(self.redactHeaders(configuredRequest.allHTTPHeaderFields))")

        let (url, response): (URL, URLResponse)
        do {
            (url, response) = try await self.urlSession.download(for: configuredRequest, delegate: nil)
        } catch {
            Logger.http.error("📡 DOWNLOAD \(requestURL) – network error: \(error.localizedDescription)")
            throw error
        }

        self.delegate?.didPerformRequest(configuredRequest, response: response, data: .file(url))

        let httpResponse = response as! HTTPURLResponse
        Logger.http.debug("📡 DOWNLOAD \(requestURL) – \(httpResponse.statusCode)")
        Logger.http.debug("📡 Downloaded to: \(url.path)")
        Logger.http.debug("📡 Response headers: \(self.redactHeaders(httpResponse.allHeaderFields))")

        guard 200...299 ~= httpResponse.statusCode else {
            Logger.http.error("📡 DOWNLOAD \(requestURL) – HTTP error: \(httpResponse.statusCode)")

            throw ClientError.downloadFailed(statusCode: httpResponse.statusCode)
        }

        return (url, response as! HTTPURLResponse)
    }

    private static let sensitiveHeaders: Set<String> = ["authorization", "cookie", "set-cookie"]

    private func redactHeaders(_ headers: [String: String]?) -> String {
        guard let headers else { return "[:]" }
        let redacted = headers.map { key, value in
            Self.sensitiveHeaders.contains(key.lowercased()) ? "\(key): <redacted>" : "\(key): \(value)"
        }
        return "[\(redacted.joined(separator: ", "))]"
    }

    private func redactHeaders(_ headers: [AnyHashable: Any]) -> String {
        let redacted = headers.map { key, value in
            let name = "\(key)"
            return Self.sensitiveHeaders.contains(name.lowercased()) ? "\(name): <redacted>" : "\(name): \(value)"
        }
        return "[\(redacted.joined(separator: ", "))]"
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
