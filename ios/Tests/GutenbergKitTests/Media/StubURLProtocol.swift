#if canImport(Network)

import Foundation

/// A `URLProtocol` that answers from a canned response and records the request
/// it was asked to send, so a `URLSession` client can be tested without a
/// server.
///
/// The stub and the recorder are held per-session rather than in a global: two
/// tests running in parallel each build their own session, and a shared slot
/// would hand one test the other's request.
final class StubURLProtocol: URLProtocol {

    /// The canned response one session answers with.
    struct Stub: Sendable {
        var status: Int = 200
        var headers: [String: String] = [:]
        var body = Data()
        /// When set, the request fails with this error instead of responding.
        var failure: (any Error)?
    }

    /// The request that reached the stub, if any.
    final class Recorder: @unchecked Sendable {
        private let lock = NSLock()
        private var _request: URLRequest?

        var request: URLRequest? {
            lock.withLock { _request }
        }

        func record(_ request: URLRequest) {
            lock.withLock { _request = request }
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

    /// A session that answers every request with `stub`, plus the recorder that
    /// captures what it was asked to send.
    ///
    /// Invalidate the session when the test finishes; the registration is
    /// released with it.
    static func makeSession(stub: Stub) -> (URLSession, Recorder) {
        let token = UUID().uuidString
        let recorder = Recorder()

        lock.withLock {
            registrations[token] = Registration(stub: stub, recorder: recorder)
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        configuration.httpAdditionalHeaders = [tokenHeader: token]
        return (URLSession(configuration: configuration), recorder)
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

        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: registration.stub.status,
            httpVersion: "HTTP/1.1",
            headerFields: registration.stub.headers
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: registration.stub.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

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

#endif
