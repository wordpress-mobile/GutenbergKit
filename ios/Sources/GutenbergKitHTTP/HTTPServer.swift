#if canImport(Network)

import Foundation
import Network
import OSLog

/// A lightweight local HTTP/1.1 server built on Network.framework.
///
/// The server binds to `127.0.0.1` on a specified or system-assigned port and
/// dispatches each incoming request to a caller-provided handler. Requests are
/// parsed incrementally using ``HTTPRequestParser``, so large bodies are buffered
/// to disk rather than held in memory.
///
/// ```swift
/// let server = try await HTTPServer.start(name: "media-proxy", port: 0) { req in
///     print("\(req.parsed.method) \(req.parsed.target) (\(req.parseDuration))")
///     return HTTPResponse(status: 200, body: Data("OK".utf8))
/// }
/// print("Listening on port \(server.port)")
/// // ...
/// server.stop()
/// ```
///
/// ## Security
///
/// The server itself is a generic request dispatcher — it does not forward
/// requests or act as a proxy. SSRF protection is intentionally left to the
/// `handler` implementation, since the server cannot know which upstream hosts
/// are legitimate. The server provides two layers of defence by default:
///
/// 1. Binds to `127.0.0.1` (localhost only) unless `listenOnAllInterfaces` is set.
/// 2. Requires a randomly-generated bearer token on every request (when
///    `requiresAuthentication` is enabled). Accepts the token in either
///    `Proxy-Authorization` (RFC 9110 §11.7.1, for native clients) or
///    `Relay-Authorization` (for browser `fetch()`, where `Proxy-*` headers
///    are forbidden). Both keep `Authorization` free for upstream credentials.
///
/// ## CORS
///
/// When `requiresAuthentication` is enabled, `OPTIONS` requests are exempt
/// from authentication because CORS preflight requests never include
/// credentials (Fetch spec §3.3.5). However, the server does not generate
/// CORS response headers — this is the handler's responsibility.
///
/// When proxying to a remote server, the upstream response will typically
/// include the correct CORS headers already — pass it through unaltered.
/// When serving local content, the handler must return appropriate headers
/// for `OPTIONS` requests, typically:
///
///     Access-Control-Allow-Origin: <origin>
///     Access-Control-Allow-Methods: GET, POST, PUT, DELETE, OPTIONS
///     Access-Control-Allow-Headers: Authorization, Relay-Authorization, Content-Type
///     Access-Control-Max-Age: 86400
///
/// Without these headers, browsers will reject the preflight and block
/// the actual request. A handler that returns 404 for unrecognized methods
/// will silently break CORS for browser clients.
///
/// ## Connection Model
///
/// Each connection handles exactly one request (`Connection: close`). HTTP
/// keep-alive / pipelining is intentionally unsupported. This simplifies body
/// framing — in particular, GET/DELETE requests with unexpected body data are
/// safe because leftover bytes are discarded when the connection closes. If
/// keep-alive were ever added, body framing for all methods would need to be
/// enforced to prevent request smuggling.
///
/// Lifecycle is managed explicitly: call ``stop()`` when the server is no longer
/// needed, or let `deinit` cancel the listener.
public final class HTTPServer: Sendable {

    /// A received HTTP request with server-side metadata.
    public struct Request: Sendable {
        /// The parsed HTTP request.
        public let parsed: ParsedHTTPRequest
        /// Time spent receiving and parsing the request.
        public let parseDuration: Duration

        init(parsed: ParsedHTTPRequest, parseDuration: Duration) {
            self.parsed = parsed
            self.parseDuration = parseDuration
        }
    }

    public typealias Response = HTTPResponse

    public typealias Error = HTTPServerError

    /// The port the server is listening on.
    public let port: UInt16

    /// A bearer token required on every request (via `Proxy-Authorization`
    /// or `Relay-Authorization`). Generated randomly on each server start.
    public let token: String

    private let listener: NWListener
    private let queue: DispatchQueue
    private let connectionTasks: ConnectionTasks

    /// Sweeps crash-orphaned temp files off the caller's startup path.
    /// Exposed so tests can await completion.
    let cleanupTask: Task<Void, Never>

    private init(listener: NWListener, port: UInt16, queue: DispatchQueue, token: String, connectionTasks: ConnectionTasks, cleanupTask: Task<Void, Never>) {
        self.listener = listener
        self.port = port
        self.queue = queue
        self.token = token
        self.connectionTasks = connectionTasks
        self.cleanupTask = cleanupTask
    }

    /// The default maximum number of concurrent connections.
    public static let defaultMaxConnections: Int = 5

    /// The default read timeout for receiving a complete request (30 seconds).
    public static let defaultReadTimeout: Duration = .seconds(30)

    /// The default idle timeout between consecutive reads (5 seconds).
    /// If no data arrives within this interval, the connection is closed with a 408 response.
    public static let defaultIdleTimeout: Duration = .seconds(5)

    /// The default ceiling on waiting for the listener to become ready (5 seconds).
    /// A loopback bind completes near-instantly; this only bounds a pathological
    /// listener stuck in a non-terminal state so the caller isn't hung forever.
    public static let defaultStartTimeout: Duration = .seconds(5)

    /// The maximum number of bytes to read from the network in a single receive call.
    private static let readChunkSize: Int = 65536

    /// Creates and starts a new HTTP server.
    ///
    /// - Parameters:
    ///   - name: A stable identifier for this server instance. Must be consistent across
    ///     runs of the same logical server. Used to:
    ///     - Namespace temporary files so that multiple server instances don't interfere
    ///       with each other's orphan cleanup.
    ///     - Label the server's dispatch queue (`com.gutenbergkit.http-server.<name>`).
    ///
    ///     Each distinct server should have a unique name. It is the caller's responsibility
    ///     to choose a descriptive, collision-free identifier (e.g. `"media-proxy"`,
    ///     `"editor-assets"`).
    ///   - port: The port to listen on. Pass `nil` or omit to let the system assign an available port.
    ///   - maxRequestBodySize: The maximum allowed request body size in bytes.
    ///     Requests exceeding this limit receive a 413 response. Defaults to 4 GB.
    ///   - maxConnections: The maximum number of concurrent connections. New connections
    ///     beyond this limit are immediately closed. Defaults to 5.
    ///   - readTimeout: The maximum time to wait for the pre-body phase of a request —
    ///     receiving the headers and draining any oversized body — before closing the
    ///     connection. This bounds the unauthenticated-reachable portion of the request.
    ///     Defaults to 30 seconds.
    ///   - bodyReadTimeout: The maximum total time to wait for an accepted (authenticated)
    ///     request body, as a backstop above the per-read `idleTimeout`. A large body that
    ///     streams steadily is bounded by this ceiling rather than by `readTimeout`, so it
    ///     is not aborted mid-transfer. Pass `nil` (the default) to reuse `readTimeout`;
    ///     consumers expecting large uploads should pass a generous value.
    ///   - idleTimeout: The maximum time to wait between consecutive reads before closing
    ///     the connection. Prevents slow-loris attacks. Defaults to 5 seconds.
    ///   - startTimeout: The maximum time to wait for the listener to become ready
    ///     before giving up with ``HTTPServerError/failedToStart``. Bounds a listener
    ///     stuck in the `.waiting` state. Defaults to 5 seconds.
    ///   - handler: A closure invoked for each fully-parsed request. Return an ``HTTPResponse``
    ///     to send back to the client.
    /// - Returns: A running ``HTTPServer`` instance.
    /// - Throws: ``HTTPServerError/failedToStart`` if the listener cannot bind to the port
    ///   or does not become ready within `startTimeout`.
    public static func start(
        name: String,
        port: UInt16? = nil,
        listenOnAllInterfaces: Bool = false,
        requiresAuthentication: Bool = true,
        maxRequestBodySize: Int64 = HTTPRequestParser.defaultMaxBodySize,
        maxConnections: Int = HTTPServer.defaultMaxConnections,
        readTimeout: Duration = HTTPServer.defaultReadTimeout,
        bodyReadTimeout: Duration? = nil,
        idleTimeout: Duration = HTTPServer.defaultIdleTimeout,
        startTimeout: Duration = HTTPServer.defaultStartTimeout,
        cors: CORSPolicy = .none,
        delegate: HTTPServerDelegate? = nil,
        handler: @escaping @Sendable (HTTPServer.Request) async -> HTTPResponse
    ) async throws -> HTTPServer {
        // Sanitize to prevent path traversal — only allow safe filename characters.
        let safeName = sanitizeName(name)

        // Temp files are namespaced into a server-specific subdirectory so that
        // multiple server instances (with different names) don't interfere with
        // each other's orphan cleanup.
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GutenbergKitHTTP-\(safeName)")

        // Clean up temp files left behind by previous runs (e.g., crash or process
        // kill), off the caller's startup path. Swift's ARC guarantees deterministic
        // cleanup during normal operation, but a crash can leave orphaned files in
        // the system temp directory. The sweep's one-hour age threshold means it
        // cannot race temp files written by this (or any live) server instance.
        let cleanupTask = Task.detached(priority: .utility) {
            cleanOrphanedTempFiles(in: tempDirectory)
        }
        try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        let parameters = NWParameters.tcp
        let requestedPort = NWEndpoint.Port(rawValue: port ?? 0) ?? .any
        let host: NWEndpoint.Host = listenOnAllInterfaces ? .ipv4(.any) : .ipv4(.loopback)
        parameters.requiredLocalEndpoint = NWEndpoint.hostPort(host: host, port: requestedPort)

        let token = generateToken()
        let connectionCounter = ConnectionCounter(limit: maxConnections)
        let connectionTasks = ConnectionTasks()
        let listener = try NWListener(using: parameters)
        let queue = DispatchQueue(label: "com.gutenbergkit.http-server.\(safeName)")

        let requiresAuth = requiresAuthentication
        // Falls back to `readTimeout` so consumers that don't distinguish the two
        // keep the prior whole-request behavior.
        let resolvedBodyReadTimeout = bodyReadTimeout ?? readTimeout
        listener.newConnectionHandler = { connection in
            guard connectionCounter.tryIncrement() else {
                Logger.httpServer.warning("Connection limit reached, rejecting connection")
                connection.cancel()
                return
            }
            handleConnection(
                connection, queue: queue, token: token,
                requiresAuthentication: requiresAuth,
                maxRequestBodySize: maxRequestBodySize, readTimeout: readTimeout,
                bodyReadTimeout: resolvedBodyReadTimeout,
                idleTimeout: idleTimeout, cors: cors, tempDirectory: tempDirectory,
                connectionCounter: connectionCounter, connectionTasks: connectionTasks,
                delegate: delegate, handler: handler
            )
        }

        // Bridge listener state callbacks to an AsyncStream so we can await readiness.
        // The listener is started synchronously — only the wait is async.
        let (states, statesContinuation) = AsyncStream.makeStream(of: NWListener.State.self)
        listener.stateUpdateHandler = { state in
            statesContinuation.yield(state)
        }
        listener.start(queue: queue)

        // Bound the wait for readiness. The listener can sit in a non-terminal
        // state (e.g. `.waiting` when it can't establish an endpoint) indefinitely;
        // since callers await this — the editor load awaits the upload server's
        // bind — an unbounded wait would hang the caller, not just fail the server.
        // Race the readiness wait against a timeout, and tear the listener down on
        // any failure path so its socket isn't leaked. On `.ready` the group
        // returns the server without throwing, so a successfully-started server
        // never has its listener cancelled out from under it.
        do {
            return try await withStartTimeout(startTimeout) {
                for await state in states {
                    switch state {
                    case .ready:
                        listener.stateUpdateHandler = nil
                        guard let p = listener.port else {
                            throw HTTPServerError.failedToStart
                        }
                        let server = HTTPServer(listener: listener, port: p.rawValue, queue: queue, token: token, connectionTasks: connectionTasks, cleanupTask: cleanupTask)
                        Logger.httpServer.info("HTTP server started on port \(p.rawValue)")
                        return server
                    case .failed(let error):
                        Logger.httpServer.error("Listener failed: \(error)")
                        throw HTTPServerError.failedToStart
                    case .cancelled:
                        throw HTTPServerError.failedToStart
                    default:
                        continue
                    }
                }
                throw HTTPServerError.failedToStart
            }
        } catch {
            // Failure or timeout: the listener may still be started, so cancel it
            // to release the socket. (On success the returned server owns it.)
            listener.cancel()
            throw error
        }
    }

    /// Races `operation` against `timeout`, throwing ``HTTPServerError/startTimeout``
    /// if the timeout wins. Used to bound the wait for the listener to become ready
    /// so a caller — such as the editor load awaiting the upload server's bind —
    /// isn't hung on a listener stuck in a non-terminal state.
    static func withStartTimeout<T: Sendable>(
        _ timeout: Duration,
        _ operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw HTTPServerError.startTimeout
            }
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }

    /// Stops the server and releases resources.
    ///
    /// Cancels the listener and all in-flight connection tasks. Handlers that
    /// are currently executing will receive a `CancellationError`.
    public func stop() {
        listener.cancel()
        connectionTasks.cancelAll()
        Logger.httpServer.info("HTTP server stopped")
    }

    deinit {
        listener.cancel()
        connectionTasks.cancelAll()
    }

    /// The library's default response for a parse error: the mapped status code
    /// with a plain-text body echoing the RFC reason phrase (e.g. 413 "Content Too
    /// Large"). This is what fatal errors always use, what a recoverable error uses
    /// when no delegate customizes it, and what an ``HTTPServerDelegate`` can
    /// delegate back to for cases it doesn't handle.
    public static func defaultErrorResponse(for error: HTTPRequestParseError) -> HTTPResponse {
        let statusText = String(error.httpStatusText)
        return HTTPResponse(status: error.httpStatus, statusText: statusText, body: Data(statusText.utf8))
    }

    // MARK: - Connection Handling

    private static func handleConnection(
        _ connection: NWConnection,
        queue: DispatchQueue,
        token: String,
        requiresAuthentication: Bool,
        maxRequestBodySize: Int64,
        readTimeout: Duration,
        bodyReadTimeout: Duration,
        idleTimeout: Duration,
        cors: CORSPolicy,
        tempDirectory: URL,
        connectionCounter: ConnectionCounter,
        connectionTasks: ConnectionTasks,
        delegate: HTTPServerDelegate?,
        handler: @escaping @Sendable (HTTPServer.Request) async -> HTTPResponse
    ) {
        connection.start(queue: queue)

        let taskID = UUID()
        let task = Task {
            defer {
                connectionCounter.decrement()
            }

            do {
                let parser = HTTPRequestParser(maxBodySize: maxRequestBodySize, tempDirectory: tempDirectory)
                var request: ParsedHTTPRequest!
                let duration = try await ContinuousClock().measure {
                    // Phase 1 (pre-body): receive and validate headers, authenticate,
                    // and drain any oversized body — all bounded by `readTimeout`. This is
                    // the unauthenticated-reachable portion of the request, so it keeps a
                    // strict total-duration cap.
                    let partial = try await Self.withReadTimeout(readTimeout) { () -> ParsedHTTPRequest in
                        // Receive headers only.
                        try await Self.receiveUntil(\.hasHeaders, parser: parser, on: connection, idleTimeout: idleTimeout)

                        // Validate headers (triggers full RFC validation).
                        guard let partial = try parser.parseRequest() else {
                            throw HTTPServerError.connectionClosed
                        }

                        // Check auth on headers alone, before draining or consuming any
                        // body bytes — an unauthenticated client must not be able to make
                        // the server read (and discard) an arbitrarily large body, and the
                        // handler must never see an unauthenticated request. OPTIONS is
                        // exempt because CORS preflight requests never include credentials
                        // (Fetch spec §3.3.5).
                        if requiresAuthentication && partial.method.uppercased() != "OPTIONS" {
                            guard authenticate(partial, token: token) else {
                                throw HTTPServerError.authenticationFailed
                            }
                        }

                        // Reject auth-exempt OPTIONS that carry a body. Real CORS preflight
                        // requests are bodyless; a body on the auth-exempt path would
                        // otherwise be read/drained without authentication — and the
                        // accepted-body read below is bounded only by the idle timeout.
                        if partial.method.uppercased() == "OPTIONS", (parser.expectedBodyLength ?? 0) > 0 {
                            throw HTTPServerError.unexpectedBody
                        }

                        // Drain the oversized body before responding so the (authenticated)
                        // client receives the 413 instead of a connection reset
                        // (RFC 9110 §15.5.14). Still bounded by `readTimeout`.
                        if parser.state == .draining {
                            try await Self.receiveUntil(\.isComplete, parser: parser, on: connection, idleTimeout: idleTimeout)
                        }

                        return partial
                    }

                    // If the parser detected a recoverable error (e.g. payload too
                    // large, drained above), stop reading and let the post-measure
                    // branch answer it via the delegate. `request` is the body-less
                    // partial; the main handler is never invoked for it.
                    if parser.parseError != nil {
                        request = partial
                        return
                    }

                    // Reject body-bearing methods without Content-Length. We don't support
                    // Transfer-Encoding: chunked, so Content-Length is the only way to
                    // determine body size.
                    let upperMethod = partial.method.uppercased()
                    if ["POST", "PUT", "PATCH"].contains(upperMethod) && partial.header("Content-Length") == nil {
                        throw HTTPServerError.lengthRequired
                    }

                    // Phase 2 (accepted body): the client is authenticated, so read the body
                    // bounded by `bodyReadTimeout` (a generous backstop) plus the per-read
                    // `idleTimeout`. A large upload that streams steadily is never failed on
                    // total duration — only a genuine stall (idle) or the generous ceiling
                    // ends it.
                    if !parser.state.isComplete {
                        try await Self.withReadTimeout(bodyReadTimeout) {
                            try await Self.receiveUntil(\.isComplete, parser: parser, on: connection, idleTimeout: idleTimeout)
                        }
                    }

                    guard let complete = try parser.parseRequest(), complete.isComplete else {
                        throw HTTPServerError.connectionClosed
                    }
                    request = complete
                }

                // A recoverable parse error (payload too large, drained above): the
                // request was never fully read, so it must not reach the handler.
                // The library owns the response — the delegate customizes the body if
                // it wants, otherwise a correct generic error. `send` stamps CORS.
                let response: HTTPResponse
                if let parseError = parser.parseError {
                    response = delegate?.response(forRecoverableParseError: parseError)
                        ?? Self.defaultErrorResponse(for: parseError)
                } else if cors == .permissive, request.method.uppercased() == "OPTIONS" {
                    // Under a permissive CORS policy the library answers the OPTIONS
                    // preflight itself; the send layer stamps the CORS headers.
                    response = HTTPResponse(status: 204)
                } else {
                    // Run the handler, but race it against the peer closing the
                    // connection. Once the request has been fully read, no bytes
                    // flow on this connection until the response is sent, so a
                    // handler that awaits slow outbound work — the media-upload
                    // relay awaiting `POST /wp/v2/media` — leaves the connection
                    // idle. If the client (the editor WebView) aborts the upload
                    // during that window, nothing here would otherwise notice, and
                    // the outbound request would run to completion, creating an
                    // orphaned attachment that a retry then duplicates. Watching for
                    // the close and cancelling the handler propagates cancellation
                    // through structured concurrency to the outbound URLSession
                    // task, so a cancelled upload is actually cancelled.
                    switch await Self.runHandler(
                        handler,
                        Request(parsed: request, parseDuration: duration),
                        racingCloseOf: connection
                    ) {
                    case .completed(let handlerResponse):
                        response = handlerResponse
                    case .clientDisconnected:
                        Logger.httpServer.debug("\(request.method) \(request.target) → client disconnected before response; cancelled in-flight handler")
                        connection.cancel()
                        return
                    }
                }
                // The handler type is non-throwing and maps cancellation to a 500,
                // so if the connection task was cancelled while it ran (server stop /
                // editor teardown), honor that here rather than writing a doomed
                // response: propagate so the outer handler just closes the connection.
                try Task.checkCancellation()
                await send(response, on: connection, cors: cors)
                let (sec, atto) = duration.components
                let ms = Double(sec) * 1000.0 + Double(atto) / 1_000_000_000_000_000.0
                Logger.httpServer.debug("\(request.method) \(request.target) → \(response.status) (\(String(format: "%.1f", ms))ms)")
            } catch HTTPServerError.authenticationFailed {
                await send(HTTPResponse(status: 407, headers: [("Content-Type", "text/plain"), ("Proxy-Authenticate", "Bearer")]), on: connection, cors: cors)
            } catch HTTPServerError.lengthRequired {
                await send(HTTPResponse(status: 411, statusText: "Length Required", body: Data("Length Required".utf8)), on: connection, cors: cors)
            } catch HTTPServerError.unexpectedBody {
                Logger.httpServer.warning("Rejected auth-exempt request carrying a body")
                await send(HTTPResponse(status: 400, statusText: "Bad Request", body: Data("Unexpected request body".utf8)), on: connection, cors: cors)
            } catch is CancellationError {
                Logger.httpServer.debug("Connection cancelled during shutdown")
                connection.cancel()
            } catch HTTPServerError.readTimeout {
                Logger.httpServer.warning("Read timeout, closing connection")
                await send(HTTPResponse(status: 408, statusText: "Request Timeout", body: Data("Request Timeout".utf8)), on: connection, cors: cors)
            } catch let error as HTTPRequestParseError {
                // Fatal parse error (malformed framing, smuggling-relevant, etc.):
                // always answered by the library, never routed to the delegate.
                Logger.httpServer.error("Parse error: \(error)")
                await send(Self.defaultErrorResponse(for: error), on: connection, cors: cors)
            } catch {
                Logger.httpServer.error("Unexpected error: \(error)")
                await send(HTTPResponse(status: 400, statusText: "Bad Request", body: Data("Malformed HTTP request".utf8)), on: connection, cors: cors)
            }
        }
        connectionTasks.track(taskID, task)
    }

    /// Runs `operation` under a total-duration timeout, racing it against a sleep
    /// task. Used to bound one phase of the request read (pre-body vs. accepted
    /// body). The per-read `idleTimeout` inside `operation` still applies
    /// independently, and cancellation of the enclosing task cancels both children.
    private static func withReadTimeout<T: Sendable>(
        _ timeout: Duration,
        _ operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw HTTPServerError.readTimeout
            }
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }

    /// Feeds data from the connection into the parser until the given state
    /// predicate is satisfied or the connection closes.
    ///
    /// Each individual read is guarded by `idleTimeout` to prevent slow-loris
    /// attacks where an attacker drip-feeds one byte at a time to hold a
    /// connection slot open.
    private static func receiveUntil(
        _ condition: KeyPath<HTTPRequestParser.State, Bool>,
        parser: HTTPRequestParser,
        on connection: NWConnection,
        idleTimeout: Duration
    ) async throws {
        while !parser.state[keyPath: condition] {
            let data = try await receiveWithIdleTimeout(on: connection, timeout: idleTimeout)

            guard let data else {
                throw HTTPServerError.connectionClosed
            }

            parser.append(data)
        }
    }

    /// Reads a chunk of data from the connection, enforcing an idle timeout.
    ///
    /// - Returns: The received data, or `nil` if the connection completed with no more data.
    /// - Throws: ``HTTPServerError/readTimeout`` if no data arrives within the timeout.
    private static func receiveWithIdleTimeout(on connection: NWConnection, timeout: Duration) async throws -> Data? {
        try await withThrowingTaskGroup(of: Data?.self) { group in
            group.addTask {
                try await receive(on: connection)
            }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw HTTPServerError.readTimeout
            }
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }

    /// Reads a chunk of data from the connection.
    ///
    /// - Returns: The received data, or `nil` if the connection completed with no more data.
    ///
    /// On a spurious wake (no content, no error, not complete), re-issues the
    /// receive once. Uses a class-based flag to guarantee the continuation is
    /// resumed exactly once even if `onCancel` fires concurrently with the
    /// receive callback.
    private static func receive(on connection: NWConnection) async throws -> Data? {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data?, any Swift.Error>) in
                receiveOnce(on: connection, retryOnSpuriousWake: true, continuation: continuation)
            }
        } onCancel: {
            connection.cancel()
        }
    }

    /// Issues a single `connection.receive` and resumes the continuation.
    ///
    /// If the callback delivers a spurious wake (no data, no error, not
    /// complete) and `retryOnSpuriousWake` is true, re-issues the receive once.
    /// On the second spurious wake, treats it as connection closed.
    ///
    /// The `OnceGuard` ensures the continuation is resumed at most once. If
    /// `onCancel` fires and cancels the connection, NWConnection delivers an
    /// error callback. Without the guard, that error callback could race with a
    /// legitimate resume from the data path. The guard makes the first resume
    /// win and silently drops any subsequent attempts.
    private static func receiveOnce(
        on connection: NWConnection,
        retryOnSpuriousWake: Bool,
        continuation: CheckedContinuation<Data?, any Swift.Error>
    ) {
        let guard_ = OnceGuard()
        connection.receive(minimumIncompleteLength: 1, maximumLength: readChunkSize) { content, _, isComplete, error in
            if let error {
                if guard_.claim() { continuation.resume(throwing: HTTPServerError.networkError(error)) }
            } else if let content, !content.isEmpty {
                if guard_.claim() { continuation.resume(returning: content) }
            } else if isComplete {
                if guard_.claim() { continuation.resume(returning: nil) }
            } else if retryOnSpuriousWake {
                // Spurious wake — re-issue once. The recursive call creates a
                // fresh OnceGuard, which is correct: the old callback from this
                // receive won't fire again, so the old guard is inert.
                receiveOnce(on: connection, retryOnSpuriousWake: false, continuation: continuation)
            } else {
                if guard_.claim() { continuation.resume(returning: nil) }
            }
        }
    }

    /// Thread-safe flag ensuring a continuation is resumed exactly once.
    private final class OnceGuard: @unchecked Sendable {
        private let _claimed = NSLock()
        private var _value = false
        func claim() -> Bool {
            _claimed.lock()
            defer { _claimed.unlock() }
            if _value { return false }
            _value = true
            return true
        }
    }

    /// The result of racing a request handler against the connection's peer
    /// closing it. See ``runHandler(_:_:racingCloseOf:)``.
    private enum HandlerOutcome: Sendable {
        case completed(HTTPResponse)
        case clientDisconnected
    }

    /// Runs `handler`, racing it against the connection's peer closing it.
    ///
    /// Between the end of the request and the start of the response a
    /// well-behaved HTTP/1.1 client sends nothing, so a receive posted now can
    /// only complete when the peer closes the connection (EOF) or it fails —
    /// i.e. the client went away (an aborted `fetch`). If that wins the race, the
    /// handler task is cancelled, which propagates through structured concurrency
    /// to any outbound work the handler is awaiting, and the caller skips the
    /// (doomed) send. If the handler wins, the watcher is cancelled *without*
    /// cancelling the connection, so the response can still be sent.
    ///
    /// A read EOF can't distinguish a full close from a client *write*-half-close
    /// (`shutdown(SHUT_WR)` after the request, read half kept open for the
    /// response), so both are deliberately treated as an abort. That's safe here
    /// because the only client is the editor WebView's `fetch`, which never
    /// half-closes and fully closes on abort; serving a half-closer instead would
    /// forfeit the prompt cancellation this exists for — the two are only
    /// distinguishable by attempting the write, by which point an aborted upload
    /// has already run. A regression test pins this.
    private static func runHandler(
        _ handler: @escaping @Sendable (HTTPServer.Request) async -> HTTPResponse,
        _ request: HTTPServer.Request,
        racingCloseOf connection: NWConnection
    ) async -> HandlerOutcome {
        await withTaskGroup(of: HandlerOutcome.self) { group in
            group.addTask {
                .completed(await handler(request))
            }
            group.addTask {
                await waitForConnectionClose(on: connection)
                return .clientDisconnected
            }
            let outcome = await group.next()!
            group.cancelAll()
            return outcome
        }
    }

    /// Suspends until the connection's peer closes its send half (EOF) — a full
    /// close or a write-half-close alike — or it fails, by posting a receive
    /// whose bytes are discarded (it never feeds the parser).
    /// A well-behaved client sends nothing before the response, so in the common
    /// case the receive simply stays pending until the peer closes.
    ///
    /// If the surrounding task is cancelled first (the handler finished), this
    /// returns *without* cancelling the connection, so the caller can still use
    /// it to send the response.
    private static func waitForConnectionClose(on connection: NWConnection) async {
        let watcher = ConnectionCloseWatcher()
        await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                guard watcher.store(continuation) else { return }
                watchForClose(on: connection, watcher: watcher)
            }
        } onCancel: {
            watcher.cancel()
        }
    }

    /// Posts a receive that wakes the watcher when the peer closes the
    /// connection. Re-issues on a spurious wake or on unexpected pre-response
    /// bytes (both are discarded); a normal idle connection never invokes the
    /// callback until the peer actually closes.
    private static func watchForClose(on connection: NWConnection, watcher: ConnectionCloseWatcher) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: readChunkSize) { _, _, isComplete, error in
            if error != nil || isComplete {
                watcher.resume()
            } else {
                watchForClose(on: connection, watcher: watcher)
            }
        }
    }

    /// Resumes ``waitForConnectionClose``'s continuation exactly once, whether
    /// the wake comes from the peer closing the connection or from the
    /// surrounding task being cancelled. Cancellation never touches the
    /// connection itself.
    private final class ConnectionCloseWatcher: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<Void, Never>?
        private var resumed = false
        private var cancelled = false

        /// Stores the continuation. Returns `false` — and resumes immediately —
        /// if cancellation already arrived, so the caller skips posting a receive.
        func store(_ continuation: CheckedContinuation<Void, Never>) -> Bool {
            lock.lock()
            if cancelled {
                resumed = true
                lock.unlock()
                continuation.resume()
                return false
            }
            self.continuation = continuation
            lock.unlock()
            return true
        }

        /// The peer closed the connection.
        func resume() {
            lock.lock()
            guard !resumed, let continuation else { lock.unlock(); return }
            resumed = true
            self.continuation = nil
            lock.unlock()
            continuation.resume()
        }

        /// The surrounding task was cancelled (the handler finished first).
        func cancel() {
            lock.lock()
            cancelled = true
            guard !resumed, let continuation else { lock.unlock(); return }
            resumed = true
            self.continuation = nil
            lock.unlock()
            continuation.resume()
        }
    }

    /// Sends a response on the connection and then closes it.
    private static func send(_ response: HTTPResponse, on connection: NWConnection, cors: CORSPolicy) async {
        let decorated = response.addingHeadersIfAbsent(cors.responseHeaders)
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            connection.send(content: decorated.serialized(), completion: .contentProcessed { _ in
                connection.cancel()
                continuation.resume()
            })
        }
    }

    // MARK: - Authentication

    /// Validates the proxy bearer token from the request.
    ///
    /// Accepts the token in either:
    /// - `Proxy-Authorization` — the standard HTTP header for proxy credentials
    ///   (RFC 9110 §11.7.1), usable from native HTTP clients.
    /// - `Relay-Authorization` — a non-forbidden alternative usable from
    ///   browser `fetch()`, where `Proxy-*` headers are silently stripped
    ///   (Fetch spec §2.2.2).
    ///
    /// Both headers keep the client's `Authorization` header available for
    /// upstream credentials.
    private static func authenticate(_ request: ParsedHTTPRequest, token: String) -> Bool {
        let proxyAuth = request.header("Proxy-Authorization")
            ?? request.header("Relay-Authorization")
        guard let proxyAuth else {
            return false
        }

        let prefix = "Bearer "
        guard proxyAuth.prefix(prefix.count).caseInsensitiveCompare(prefix) == .orderedSame else {
            return false
        }

        let provided = String(proxyAuth.dropFirst(prefix.count))
        return constantTimeEqual(provided, token)
    }

    /// Compares two strings in constant time to prevent timing attacks.
    ///
    /// Always iterates over the expected token (b) regardless of the input
    /// length, so timing reveals neither whether lengths match nor how many
    /// bytes are correct. When lengths differ, b is compared against itself
    /// to keep the work constant.
    ///
    /// **Do not "simplify" this to an early-return on length mismatch.**
    /// An early return would let an attacker measure response time to discover
    /// the expected token length, even though the token length is currently
    /// fixed at 64 hex characters. This implementation is intentionally
    /// branch-free in the hot path to avoid leaking any information.
    private static func constantTimeEqual(_ a: String, _ b: String) -> Bool {
        let aBytes = Array(a.utf8)
        let bBytes = Array(b.utf8)
        var result: UInt8 = aBytes.count == bBytes.count ? 0 : 1
        let comparand = aBytes.count == bBytes.count ? aBytes : bBytes
        for i in bBytes.indices {
            result |= comparand[i] ^ bBytes[i]
        }
        return result == 0
    }

    /// Strips characters from `name` that are not letters, digits, `.`, `-`, or `_`.
    ///
    /// The server `name` is embedded in filesystem paths (temp directory) and
    /// dispatch queue labels. Allowing arbitrary characters (e.g. `../`) would
    /// enable path traversal. This filter reduces the name to a safe subset.
    private static func sanitizeName(_ name: String) -> String {
        let sanitized = String(name.unicodeScalars.filter {
            CharacterSet.alphanumerics.contains($0) || $0 == "." || $0 == "-" || $0 == "_"
        })
        precondition(!sanitized.isEmpty, "Server name must contain at least one alphanumeric character, dot, hyphen, or underscore")
        return sanitized
    }

    private static func generateToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        precondition(status == noErr, "Failed to generate random token")
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    /// Removes orphaned temp files left by a previous crash.
    ///
    /// The parser creates temp files in a server-specific subdirectory under the
    /// system temp directory (e.g., `GutenbergKitHTTP-media-proxy/`). Under normal
    /// operation, `Buffer`/`TempFileOwner` delete them via ARC. After a crash these
    /// files survive — this method cleans them up on the next server start.
    ///
    /// Files currently backing an in-flight request are registered in
    /// ``ActiveTempFiles`` and skipped, so a server instance that shares a
    /// directory with a concurrently-running instance of the same name (e.g. two
    /// editors open at once, or one being torn down as another starts) does not
    /// delete the other's live buffers. Files not in the registry have no live
    /// owner in this process — they are crash orphans and are removed. The sweep
    /// runs detached from `start()` (see `cleanupTask`), off the caller's startup
    /// path; the registry keeps it safe regardless of when it runs.
    static func cleanOrphanedTempFiles(in directory: URL) {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil
        ) else { return }
        for url in contents where !ActiveTempFiles.contains(url.lastPathComponent) {
            try? FileManager.default.removeItem(at: url)
        }
    }
}

/// Thread-safe tracker for in-flight connection tasks, enabling graceful shutdown.
///
/// Completed tasks are intentionally not removed. Entries are tiny (UUID + Task
/// reference) and accumulate only for the server's lifetime. Removing on completion
/// would require a `defer` inside each Task, but if the task finishes before
/// `track()` is called the `remove()` is a no-op — leaving a stale entry anyway.
/// Skipping removal avoids that race entirely. `cancelAll()` clears everything
/// on `stop()`.
///
/// All mutable state is guarded by `lock`.
final class ConnectionTasks: @unchecked Sendable {
    private let lock = NSLock()
    private var tasks: [UUID: Task<Void, Never>] = [:]

    func track(_ id: UUID, _ task: Task<Void, Never>) {
        lock.withLock {
            tasks[id] = task
        }
    }

    func cancelAll() {
        lock.withLock {
            for task in tasks.values {
                task.cancel()
            }
            tasks.removeAll()
        }
    }
}

/// Thread-safe counter for tracking active connections.
final class ConnectionCounter: @unchecked Sendable {
    private let lock = NSLock()
    private let limit: Int
    private var _count: Int = 0

    init(limit: Int) {
        self.limit = limit
    }

    /// Attempts to increment the counter. Returns `true` if the connection is allowed.
    func tryIncrement() -> Bool {
        lock.withLock {
            guard _count < limit else { return false }
            _count += 1
            return true
        }
    }

    /// Decrements the counter when a connection completes.
    func decrement() {
        lock.withLock {
            _count -= 1
        }
    }
}

// MARK: - Logger

extension Logger {
    static let httpServer = Logger(subsystem: "com.gutenbergkit.http", category: "server")
}

#endif // canImport(Network)
