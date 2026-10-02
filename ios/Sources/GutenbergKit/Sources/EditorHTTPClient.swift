import Foundation
import OSLog

/// A protocol for making authenticated HTTP requests to the WordPress REST API.
public protocol EditorHTTPClientProtocol: Sendable {
    func perform(_ urlRequest: URLRequest) async throws -> (Data, HTTPURLResponse)

    /// Like ``perform(_:)`` but does **not** throw on a non-2xx status — returns
    /// the raw response so the caller can relay WordPress's exact status and body.
    /// Used for native media uploads, which forward WordPress's response (and its
    /// errors) to the editor unchanged.
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

    /// The shortest inactivity timeout a media upload is allowed.
    ///
    /// `URLRequest.timeoutInterval` is an inactivity timer, and an upload goes silent
    /// once its body is sent: WordPress creates the attachment and then generates image
    /// sub-sizes before it answers. A slow host can take well over a minute, and a timer
    /// that fires in that window reports a failure for an attachment that already exists
    /// — an orphan the user then duplicates by retrying. Ten minutes outlasts the gateway
    /// timeouts hosts put in front of PHP, so the host's own limit is the one that ends a
    /// request that really is stuck.
    public static let uploadInactivityTimeout: TimeInterval = 600

    private let urlSession: URLSessionProtocol
    private let authHeader: String
    private let delegate: EditorHTTPClientDelegate?
    private let requestTimeout: TimeInterval?
    private let minimumTimeout: TimeInterval?

    /// Requests in flight that an identical `perform(_:)` joins instead of sending again. Every
    /// editor and service builds its own client, so this is shared across all of them.
    static let inFlightRequests = InFlightTasks<SharedRequest, (Data, HTTPURLResponse)>()

    /// A request other callers can share: the request as it goes out, and the session it goes
    /// out on. `URLRequest`'s own `==` ignores the timeout and the network service type, so
    /// those are compared here; it ignores the body too, but a request with one isn't shared.
    struct SharedRequest: Hashable, Sendable {
        let request: URLRequest
        let timeout: TimeInterval
        let networkServiceType: URLRequest.NetworkServiceType
        let session: ObjectIdentifier
    }

    public init(
        urlSession: URLSessionProtocol,
        authHeader: String,
        delegate: EditorHTTPClientDelegate? = nil,
        requestTimeout: TimeInterval? = nil
    ) {
        self.init(
            urlSession: urlSession,
            authHeader: authHeader,
            delegate: delegate,
            requestTimeout: requestTimeout,
            minimumTimeout: nil
        )
    }

    private init(
        urlSession: URLSessionProtocol,
        authHeader: String,
        delegate: EditorHTTPClientDelegate?,
        requestTimeout: TimeInterval?,
        minimumTimeout: TimeInterval?
    ) {
        self.urlSession = urlSession
        self.authHeader = authHeader
        self.delegate = delegate
        self.requestTimeout = requestTimeout
        self.minimumTimeout = minimumTimeout
    }

    /// Sends `urlRequest`, throwing for a non-2xx status.
    ///
    /// A request identical to one already in flight joins it rather than going out again, so
    /// callers after the same site data — an editor and a prefetch, say — pay for one round
    /// trip. Only a safe request without a body is shared, and only between clients no delegate
    /// is watching. A request whose cache policy asks to skip the cache goes out alone: its
    /// caller wants an answer no older than the call, and a request already in flight may
    /// predate a write made since. Cancelling a caller ends its own wait; the request is
    /// cancelled once no caller is left waiting on it.
    public func perform(_ urlRequest: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let configuredRequest = self.configureRequest(urlRequest)
        guard let sharedRequest = sharedRequest(forConfigured: configuredRequest) else {
            return try await send(configuredRequest)
        }
        return try await Self.inFlightRequests.value(for: sharedRequest) { _ in
            try await self.send(configuredRequest)
        }
    }

    /// For tests: what `perform(_:)` shares `urlRequest` under, or `nil` if it goes out alone.
    func sharedRequest(for urlRequest: URLRequest) -> SharedRequest? {
        sharedRequest(forConfigured: configureRequest(urlRequest))
    }

    /// `nil` for a request that must go out alone: an unsafe method or a body, a cache policy
    /// that asks for a fresh answer, a delegate that expects to see each request it asked for,
    /// or a session that isn't an object — a shared request is keyed by the session's identity,
    /// which only an object keeps.
    private func sharedRequest(forConfigured request: URLRequest) -> SharedRequest? {
        guard delegate == nil,
            Self.sharableMethods.contains(request.httpMethod ?? "GET"),
            request.httpBody == nil,
            request.httpBodyStream == nil,
            !Self.freshAnswerPolicies.contains(request.cachePolicy),
            type(of: urlSession) is AnyClass
        else {
            return nil
        }
        return SharedRequest(
            request: request,
            timeout: request.timeoutInterval,
            networkServiceType: request.networkServiceType,
            session: ObjectIdentifier(urlSession as AnyObject)
        )
    }

    private static let sharableMethods: Set<String> = ["GET", "HEAD", "OPTIONS"]

    /// The cache policies that ask the server afresh rather than trust a stored response, and
    /// so won't take one already on its way.
    private static let freshAnswerPolicies: Set<URLRequest.CachePolicy> = [
        .reloadIgnoringLocalCacheData,
        .reloadIgnoringLocalAndRemoteCacheData,
        .reloadRevalidatingCacheData,
    ]

    private func send(_ configuredRequest: URLRequest) async throws -> (Data, HTTPURLResponse) {
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
    /// drops the REST `requestTimeout`, and raises every request's inactivity
    /// timeout to at least ``uploadInactivityTimeout``.
    ///
    /// Both halves guard the same window: the silence while WordPress generates image
    /// sub-sizes inside `POST /wp/v2/media`. A short REST timeout would fire there, and
    /// so does `URLRequest`'s own 60s default on a slow host — measured against a
    /// WordPress whose response was held back 90s, the upload failed with
    /// `NSURLErrorTimedOut` while the attachment it created stayed on the site. A
    /// request that already asks for longer keeps its own value.
    ///
    /// The request-observing `delegate` is carried over, so a host that installs
    /// one observes media uploads like every other request. Sharing the observer
    /// across both clients is sound because `EditorHTTPClientDelegate` is `Sendable`.
    public nonisolated func uploadClient() -> any EditorHTTPClientProtocol {
        EditorHTTPClient(
            urlSession: urlSession,
            authHeader: authHeader,
            delegate: delegate,
            requestTimeout: nil,
            minimumTimeout: Self.uploadInactivityTimeout
        )
    }

    private func configureRequest(_ request: URLRequest) -> URLRequest {
        var mutableRequest = request
        mutableRequest.addValue(self.authHeader, forHTTPHeaderField: "Authorization")
        mutableRequest.addValue("\(Self.baseUserAgent) GutenbergKit/\(GutenbergKitVersion.version)", forHTTPHeaderField: "User-Agent")

        if let requestTimeout {
            mutableRequest.timeoutInterval = requestTimeout
        }
        if let minimumTimeout, mutableRequest.timeoutInterval < minimumTimeout {
            mutableRequest.timeoutInterval = minimumTimeout
        }

        // Prevent wordpress_logged_in cookies from being sent, which could interfere with
        // application password authentication in the Authorization header.
        // See: https://github.com/wordpress-mobile/GutenbergKit/commit/30ebac210924ecc8e9dee3980c101ef24b1befa6
        mutableRequest.httpShouldHandleCookies = false

        return mutableRequest
    }
}
