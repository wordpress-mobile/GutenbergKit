import Foundation
import Network

/// A server that reads an upload's headers, then stops reading its body until the test calls
/// `resume()`. It then reads the rest of the body, and answers `201` once the test calls
/// `answer()`.
///
/// `URLSession` reports how much of a body it has sent only as the body leaves for the
/// connection. Over loopback, a server that reads straight away takes a large body in one go,
/// and `URLSession` reports it all at once. While this server isn't reading, the connection's
/// buffers fill, and `URLSession` reports the part it got into them.
final class StalledUploadServer: @unchecked Sendable {
    private(set) var port: UInt16 = 0

    private let listener: NWListener
    private let queue = DispatchQueue(label: "StalledUploadServer")
    private let lock = NSLock()
    private var resumed = false
    private var waiting: [@Sendable () -> Void] = []
    private var answered = false
    private var waitingToAnswer: [@Sendable () -> Void] = []

    private init(listener: NWListener) {
        self.listener = listener
    }

    static func start() async throws -> StalledUploadServer {
        let server = StalledUploadServer(listener: try NWListener(using: .tcp, on: .any))
        // A listener without a connection handler fails to start.
        server.listener.newConnectionHandler = { [weak server] connection in
            server?.serve(connection)
        }
        server.port = try await withCheckedThrowingContinuation { continuation in
            let once = Once()
            server.listener.stateUpdateHandler = { [weak server] state in
                switch state {
                case .ready:
                    once.run { continuation.resume(returning: server?.listener.port?.rawValue ?? 0) }
                case .failed(let error):
                    once.run { continuation.resume(throwing: error) }
                default:
                    break
                }
            }
            server.listener.start(queue: server.queue)
        }
        return server
    }

    /// Lets the server read the rest of the body and answer.
    func resume() {
        let waiting = lock.withLock {
            resumed = true
            return self.waiting
        }
        waiting.forEach { $0() }
    }

    /// Lets the server answer once it has read the whole body.
    func answer() {
        let waiting = lock.withLock {
            answered = true
            return self.waitingToAnswer
        }
        waiting.forEach { $0() }
    }

    func stop() {
        resume()
        answer()
        listener.cancel()
    }

    private func serve(_ connection: NWConnection) {
        connection.start(queue: queue)
        readHeaders(connection, received: Data())
    }

    private func readHeaders(_ connection: NWConnection, received: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1024) { [weak self] data, _, isComplete, error in
            guard let self, error == nil, !isComplete || data != nil else { return connection.cancel() }
            let received = received + (data ?? Data())
            guard let end = received.range(of: Data("\r\n\r\n".utf8)) else {
                return self.readHeaders(connection, received: received)
            }
            let head = String(decoding: received[..<end.lowerBound], as: UTF8.self)
            let length = head.split(separator: "\r\n")
                .first { $0.lowercased().hasPrefix("content-length:") }
                .flatMap { Int($0.split(separator: ":")[1].trimmingCharacters(in: .whitespaces)) } ?? 0
            let remaining = length - (received.count - end.upperBound)
            self.whenResumed {
                self.readBody(connection, remaining: remaining)
            }
        }
    }

    private func readBody(_ connection: NWConnection, remaining: Int) {
        guard remaining > 0 else {
            whenAnswered {
                let response = "HTTP/1.1 201 Created\r\nContent-Type: application/json\r\nContent-Length: 2\r\nConnection: close\r\n\r\n{}"
                connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in connection.cancel() })
            }
            return
        }
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1 << 20) { [weak self] data, _, _, error in
            guard let self, error == nil, let data else { return connection.cancel() }
            self.readBody(connection, remaining: remaining - data.count)
        }
    }

    private func whenResumed(_ action: @escaping @Sendable () -> Void) {
        let runNow = lock.withLock {
            if !resumed { waiting.append(action) }
            return resumed
        }
        if runNow { action() }
    }

    private func whenAnswered(_ action: @escaping @Sendable () -> Void) {
        let runNow = lock.withLock {
            if !answered { waitingToAnswer.append(action) }
            return answered
        }
        if runNow { action() }
    }

    /// Runs its action the first time only.
    private final class Once: @unchecked Sendable {
        private let lock = NSLock()
        private var done = false

        func run(_ action: () -> Void) {
            let first = lock.withLock {
                defer { done = true }
                return !done
            }
            if first { action() }
        }
    }
}
