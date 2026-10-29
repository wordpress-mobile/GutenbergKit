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

    /// Downloads the response body to a temporary file. The caller owns the file, and must move or delete it.
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
/// media uploads routed through ``EditorHTTPClientProtocol/uploadClient()``, and
/// the editor page's `fetch` requests, which native code relays. Those go to the
/// site's REST API and to any other host the page calls, such as a plugin's own
/// service, so don't assume a request is for the site.
/// Conformers are invoked from an actor and from `URLSession`'s delegate queue, so
/// the protocol requires `Sendable` (implementations must be thread-safe).
///
/// ``didPerformRequest(_:response:data:)`` reports a request that got a response.
/// The task callbacks report every request, whatever became of it: one that is
/// still waiting has had ``didCreateTask(_:)`` and nothing after it. They take
/// `URLSession`'s own types, so a network logger that records `URLSessionTask`s
/// can take each call as it comes.
///
/// Each request carries its `Authorization` header, as sent. That is usually the
/// site's credential, but a caller's own token is sent as it is — Jetpack AI sends
/// one to WordPress.com. Native code never adds the site's credential to a request
/// for another host, but it doesn't remove one the page sent, so such a request can
/// carry it. Redact the header on every request before storing requests anywhere it
/// shouldn't be kept, not only where it matches the site credential.
public protocol EditorHTTPClientDelegate: Sendable {
    func didPerformRequest(_ request: URLRequest, response: URLResponse, data: EditorResponseData)

    /// A request is about to go out as `task`.
    func didCreateTask(_ task: URLSessionTask)

    /// `URLSession` measured `task`: its timing, its connection, and the bytes sent
    /// and received.
    func task(_ task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics)

    /// `task` ended: with the response's body, or with the error that ended it — the
    /// request was cancelled, timed out, or couldn't reach the server.
    func task(_ task: URLSessionTask, didCompleteWith data: EditorResponseData?, error: (any Error)?)
}

public extension EditorHTTPClientDelegate {
    func didCreateTask(_ task: URLSessionTask) {}
    func task(_ task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {}
    func task(_ task: URLSessionTask, didCompleteWith data: EditorResponseData?, error: (any Error)?) {}
}

/// Reports one request's task to an ``EditorHTTPClientDelegate``.
///
/// Passed to `URLSession` as the delegate of that one task, which is how it sees the
/// task an async `URLSession` call never hands back.
final class NetworkTaskReporter: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    /// The host's delegate, held strongly: this object lives only as long as one
    /// request, and the delegate needn't be a class.
    private let observer: any EditorHTTPClientDelegate
    private let lock = NSLock()
    private var _task: URLSessionTask?

    init(reportingTo observer: any EditorHTTPClientDelegate) {
        self.observer = observer
    }

    func urlSession(_ session: URLSession, didCreateTask task: URLSessionTask) {
        lock.withLock { _task = task }
        observer.didCreateTask(task)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
        observer.task(task, didFinishCollecting: metrics)
    }

    /// Reports how the request ended, once the call that sent it returns or throws.
    func complete(with data: EditorResponseData?, error: (any Error)?) {
        guard let task = lock.withLock({ _task }) else { return }
        observer.task(task, didCompleteWith: data, error: error)
    }
}

public enum EditorResponseData {
    case bytes(Data)

    /// The temporary file a response was downloaded to. It's only guaranteed to exist during the delegate
    /// call: afterwards the caller of `download(_:)` moves or deletes it, or, for an error, the client does.
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
    /// Readable outside the actor so the editor can hand it to the REST relay, whose
    /// requests it observes too.
    nonisolated let delegate: EditorHTTPClientDelegate?
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
        let (data, response) = try await self.data(for: configuredRequest)
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
        let (data, response) = try await self.data(for: configuredRequest)
        self.delegate?.didPerformRequest(configuredRequest, response: response, data: .bytes(data))
        return (data, response as! HTTPURLResponse)
    }

    public func download(_ urlRequest: URLRequest) async throws -> (URL, HTTPURLResponse) {

        let configuredRequest = self.configureRequest(urlRequest)
        let (url, response) = try await self.download(for: configuredRequest)
        self.delegate?.didPerformRequest(configuredRequest, response: response, data: .file(url))

        let httpResponse = response as! HTTPURLResponse

        guard 200...299 ~= httpResponse.statusCode else {
            let requestURL = configuredRequest.url!
            Logger.http.error("📡 HTTP error fetching \(requestURL.absoluteString): \(httpResponse.statusCode)")

            // The file holds the error response's body. No caller receives it, so delete it here.
            try? FileManager.default.removeItem(at: url)

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

    /// Sends `request` on the session, reporting its task to the delegate, if any.
    private func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let reporter = delegate.map(NetworkTaskReporter.init(reportingTo:))
        do {
            let (data, response) = try await urlSession.data(for: request, delegate: reporter)
            reporter?.complete(with: .bytes(data), error: nil)
            return (data, response)
        } catch {
            reporter?.complete(with: nil, error: error)
            throw error
        }
    }

    /// Downloads `request` on the session, reporting its task to the delegate, if any.
    private func download(for request: URLRequest) async throws -> (URL, URLResponse) {
        let reporter = delegate.map(NetworkTaskReporter.init(reportingTo:))
        do {
            let (url, response) = try await urlSession.download(for: request, delegate: reporter)
            reporter?.complete(with: .file(url), error: nil)
            return (url, response)
        } catch {
            reporter?.complete(with: nil, error: error)
            throw error
        }
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
