import Foundation

/// A `URLProtocol` that answers from a canned response and records the request
/// it was asked to send, so a `URLSession` client can be tested without a
/// server.
///
/// The stub and the recorder are held per-session rather than in a global: two
/// tests running in parallel each build their own session, and a shared slot
/// would hand one test the other's request.
///
/// `@unchecked Sendable`: each instance's state is only touched on the thread that
/// called `startLoading()`, as `URLProtocol` requires.
final class StubURLProtocol: URLProtocol, @unchecked Sendable {

    /// The canned response one session answers with.
    struct Stub: Sendable {
        var status: Int = 200
        var headers: [String: String] = [:]
        var body = Data()
        /// When set, the request fails with this error instead of responding.
        var failure: (any Error)?
        /// When set, the stub answers with a redirect to this URL, using `status`.
        /// If the session refuses the redirect, the 3xx is the response, as it would
        /// be from a server.
        var redirect: URL?

        /// If set, the stub sends the status, headers and `body`, then waits for
        /// the test to open the gate. Then it sends `rest`, or fails with
        /// `restFailure`. This lets a test check what reached the page before the
        /// rest of the response arrived.
        var gate: Gate?
        var rest = Data()
        var restFailure: (any Error)?
        /// Redirects by path. A request for a path in here gets a `302` to the
        /// URL it maps to, which may be relative, and the session follows it.
        var redirects: [String: String] = [:]
    }

    /// Holds back the rest of a stubbed response until the test calls `open()`.
    final class Gate: @unchecked Sendable {
        private let lock = NSLock()
        private var isOpen = false
        private var waiting: [@Sendable () -> Void] = []

        func open() {
            let waiting = lock.withLock {
                isOpen = true
                return self.waiting
            }
            waiting.forEach { $0() }
        }

        fileprivate func whenOpen(_ action: @escaping @Sendable () -> Void) {
            let runNow = lock.withLock {
                if !isOpen { waiting.append(action) }
                return isOpen
            }
            if runNow { action() }
        }
    }

    /// The request that reached the stub, if any, and whether it was cancelled.
    final class Recorder: @unchecked Sendable {
        private let lock = NSLock()
        private var _request: URLRequest?
        private var _wasStopped = false

        var request: URLRequest? {
            lock.withLock { _request }
        }

        /// Whether `URLSession` cancelled the request before it finished.
        var wasStopped: Bool {
            lock.withLock { _wasStopped }
        }

        func record(_ request: URLRequest) {
            lock.withLock { _request = request }
        }

        func recordStop() {
            lock.withLock { _wasStopped = true }
        }
    }

    /// Per-session configuration, keyed by a token carried in the session's
    /// `httpAdditionalHeaders` — the only channel a `URLProtocol` subclass has
    /// to the session that instantiated it.
    private struct Registration {
        let stub: Stub
        let recorder: Recorder
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var registrations: [String: Registration] = [:]

    private static let tokenHeader = "X-Stub-Session"

    private var registration: Registration?
    private var isLoading = false

    /// A stubbed session and the recorder capturing what it was asked to send.
    ///
    /// Call ``finish()`` when the test is done. Invalidating the session alone
    /// would leave the registration — and the stub's body — held for the life
    /// of the test process.
    struct Stubbed {
        let session: URLSession
        let recorder: Recorder
        private let token: String

        init(session: URLSession, recorder: Recorder, token: String) {
            self.session = session
            self.recorder = recorder
            self.token = token
        }

        func finish() {
            session.invalidateAndCancel()
            StubURLProtocol.lock.withLock {
                StubURLProtocol.registrations[token] = nil
            }
        }
    }

    /// A session that answers every request with `stub`.
    static func makeSession(stub: Stub) -> Stubbed {
        let token = UUID().uuidString
        let recorder = Recorder()

        lock.withLock {
            registrations[token] = Registration(stub: stub, recorder: recorder)
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        configuration.httpAdditionalHeaders = [tokenHeader: token]
        return Stubbed(
            session: URLSession(configuration: configuration),
            recorder: recorder,
            token: token
        )
    }

    override class func canInit(with request: URLRequest) -> Bool {
        request.value(forHTTPHeaderField: tokenHeader) != nil
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let token = request.value(forHTTPHeaderField: Self.tokenHeader),
              let registration = Self.lock.withLock({ Self.registrations[token] }) else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }

        // `URLProtocol` hands over the body as a stream once the request is
        // built, so read it back for the recorded copy.
        var recorded = request
        recorded.setValue(nil, forHTTPHeaderField: Self.tokenHeader)
        if recorded.httpBody == nil, let stream = recorded.httpBodyStream {
            recorded.httpBody = Self.readAll(stream)
        }
        registration.recorder.record(recorded)

        if let failure = registration.stub.failure {
            client?.urlProtocol(self, didFailWithError: failure)
            return
        }

        if let redirect = registration.stub.redirect {
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: registration.stub.status,
                httpVersion: "HTTP/1.1",
                headerFields: ["Location": redirect.absoluteString]
            )!
            client?.urlProtocol(self, wasRedirectedTo: URLRequest(url: redirect), redirectResponse: response)
            // A custom protocol has to send the 3xx itself for the session to end
            // with it when the redirect is refused. Without this, the task waits
            // until it times out.
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocolDidFinishLoading(self)
            return
        }

        if let location = registration.stub.redirects[request.url!.path],
           let target = URL(string: location, relativeTo: request.url)?.absoluteURL {
            let redirect = HTTPURLResponse(
                url: request.url!,
                statusCode: 302,
                httpVersion: "HTTP/1.1",
                headerFields: ["Location": target.absoluteString]
            )!
            var next = request
            next.url = target
            client?.urlProtocol(self, wasRedirectedTo: next, redirectResponse: redirect)
            return
        }

        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: registration.stub.status,
            httpVersion: "HTTP/1.1",
            headerFields: registration.stub.headers
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if !registration.stub.body.isEmpty {
            client?.urlProtocol(self, didLoad: registration.stub.body)
        }
        guard let gate = registration.stub.gate else {
            client?.urlProtocolDidFinishLoading(self)
            return
        }

        // Send the rest of the response on this thread, as `URLProtocol`
        // requires. `thread` is only passed to `perform(_:on:with:waitUntilDone:modes:)`,
        // which is safe to call from any thread.
        self.registration = registration
        isLoading = true
        nonisolated(unsafe) let thread = Thread.current
        gate.whenOpen { [weak self] in
            guard let self else { return }
            perform(#selector(sendRest), on: thread, with: nil, waitUntilDone: false, modes: [RunLoop.Mode.common.rawValue])
        }
    }

    @objc private func sendRest() {
        guard isLoading, let stub = registration?.stub else { return }
        isLoading = false
        if let failure = stub.restFailure {
            client?.urlProtocol(self, didFailWithError: failure)
            return
        }
        if !stub.rest.isEmpty {
            client?.urlProtocol(self, didLoad: stub.rest)
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {
        guard isLoading else { return }
        isLoading = false
        registration?.recorder.recordStop()
    }

    private static func readAll(_ stream: InputStream) -> Data {
        stream.open()
        defer { stream.close() }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: buffer.count)
            guard read > 0 else { break }
            data.append(buffer, count: read)
        }
        return data
    }
}
