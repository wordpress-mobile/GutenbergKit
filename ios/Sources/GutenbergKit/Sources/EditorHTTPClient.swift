import Foundation
import OSLog

/// A protocol for making authenticated HTTP requests to the WordPress REST API.
public protocol EditorHTTPClientProtocol: Sendable {
    func perform(_ urlRequest: URLRequest) async throws -> (Data, HTTPURLResponse)

    /// Like ``perform(_:)`` but does **not** throw on a non-2xx status — returns
    /// the raw response so the caller can relay WordPress's exact status and body.
    /// Used by the media upload server, which forwards WordPress's response (and
    /// its errors) to the editor unchanged.
    func performRaw(_ urlRequest: URLRequest) async throws -> (Data, HTTPURLResponse)

    func download(_ urlRequest: URLRequest) async throws -> (URL, HTTPURLResponse)

    /// Returns a client tuned for large media uploads. The default returns the
    /// client unchanged; ``EditorHTTPClient`` overrides it to drop the REST
    /// request timeout so a silent server-side window — WordPress synchronously
    /// generating image sub-sizes inside `POST /wp/v2/media` — can't trip an
    /// inactivity timeout and orphan the attachment.
    func uploadClient() -> any EditorHTTPClientProtocol
}

public extension EditorHTTPClientProtocol {
    /// Default implementation validates the status like ``perform(_:)``. Only
    /// clients that need to relay non-2xx responses override this.
    func performRaw(_ urlRequest: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try await perform(urlRequest)
    }

    /// Default implementation returns the client unchanged.
    func uploadClient() -> any EditorHTTPClientProtocol { self }
}

/// A delegate for observing HTTP requests made by the editor.
///
/// Implement this protocol to inspect or log all network requests — including the
/// media uploads and passthroughs routed through
/// ``EditorHTTPClientProtocol/uploadClient()``. Conformers are invoked from an
/// actor, so the protocol requires `Sendable` (implementations must be thread-safe).
public protocol EditorHTTPClientDelegate: Sendable {
    func didPerformRequest(_ request: URLRequest, response: URLResponse, data: EditorResponseData)
}

public enum EditorResponseData {
    case bytes(Data)
    case file(URL)
}

/// A WordPress REST API error response.
public struct WPError: Decodable, Sendable {
    public let code: String
    public let message: String
}

/// An HTTP client for making authenticated requests to the WordPress REST API.
///
/// This actor handles request signing, error parsing, and response validation.
/// All requests are automatically authenticated using the provided authorization header.
public actor EditorHTTPClient: EditorHTTPClientProtocol {

    /// Errors that can occur during HTTP requests.
    public enum ClientError: Error, LocalizedError, Sendable {
        /// The server returned a WordPress-formatted error response.
        case wpError(WPError, requestURL: URL)
        /// A file download failed with the given HTTP status code.
        case downloadFailed(statusCode: Int, requestURL: URL)
        /// An unexpected error occurred with the given response data and status code.
        case unknown(response: Data, statusCode: Int, requestURL: URL)

        public var errorDescription: String? {
            switch self {
            case .wpError(let error, _): error.message
            case .downloadFailed(let code, _): "Download failed (\(code))"
            case .unknown(_, let code, _): "Request failed (\(code))"
            }
        }
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
            let requestURL = configuredRequest.url!
            Logger.http.error("📡 HTTP error fetching \(requestURL.absoluteString): \(httpResponse.statusCode)")

            if let wpError = try? JSONDecoder().decode(WPError.self, from: data) {
                throw ClientError.wpError(wpError, requestURL: requestURL)
            }

            throw ClientError.unknown(
                response: data,
                statusCode: httpResponse.statusCode,
                requestURL: requestURL
            )
        }

        return (data, httpResponse)
    }

    public func performRaw(_ urlRequest: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let configuredRequest = self.configureRequest(urlRequest)
        let (data, response) = try await self.urlSession.data(for: configuredRequest)
        self.delegate?.didPerformRequest(configuredRequest, response: response, data: .bytes(data))
        return (data, response as! HTTPURLResponse)
    }

    public func download(_ urlRequest: URLRequest) async throws -> (URL, HTTPURLResponse) {

        let configuredRequest = self.configureRequest(urlRequest)
        let (url, response) = try await self.urlSession.download(for: configuredRequest, delegate: nil)
        self.delegate?.didPerformRequest(configuredRequest, response: response, data: .file(url))

        let httpResponse = response as! HTTPURLResponse

        guard 200...299 ~= httpResponse.statusCode else {
            let requestURL = configuredRequest.url!
            Logger.http.error("📡 HTTP error fetching \(requestURL.absoluteString): \(httpResponse.statusCode)")

            throw ClientError.downloadFailed(
                statusCode: httpResponse.statusCode,
                requestURL: requestURL
            )
        }

        return (url, response as! HTTPURLResponse)
    }

    /// A sibling client tuned for large media uploads: it reuses this client's
    /// session (preserving any custom configuration or pinning) and auth header,
    /// but drops the REST `requestTimeout`. That timeout is an inactivity timer
    /// (`URLRequest.timeoutInterval`); a short value set for snappy REST calls
    /// would also fire during the silent window while WordPress synchronously
    /// generates image sub-sizes inside `POST /wp/v2/media`, orphaning the
    /// attachment server-side and duplicating it on retry. Uploads instead use
    /// the request's default 60s inactivity timeout, mirroring Android's
    /// dedicated upload client (no total-duration cap).
    ///
    /// The request-observing `delegate` is carried over, so a host that installs
    /// one observes media uploads and passthroughs like every other request; only
    /// the REST `requestTimeout` is dropped. Sharing the observer across both
    /// clients is sound because `EditorHTTPClientDelegate` is `Sendable`.
    public nonisolated func uploadClient() -> any EditorHTTPClientProtocol {
        EditorHTTPClient(urlSession: urlSession, authHeader: authHeader, delegate: delegate)
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
