import Foundation
import OSLog

extension RestRelay {
    /// The relay's answer to the page: the upstream status and headers, then the
    /// body as it arrives.
    struct Response: Sendable {
        let status: Int
        let headers: [String: String]

        /// The body, in chunks as they arrive. Throws if the upstream request fails
        /// partway.
        ///
        /// Dropping it before the end cancels the upstream request.
        let body: AsyncThrowingStream<Data, any Error>

        /// The URL the page reads as the response's `url`, or `nil` for the URL the
        /// page requested, which is the relay's own. WebKit ignores one with a
        /// fragment and reports the requested URL instead.
        let url: URL?

        init(status: Int, headers: [String: String], body: AsyncThrowingStream<Data, any Error>, url: URL? = nil) {
            self.status = status
            self.headers = headers
            self.body = body
            self.url = url
        }

        /// A response the relay makes itself, such as a refusal, with its whole body
        /// in one chunk.
        init(_ response: SchemeResponse) {
            self.init(status: response.status, headers: response.headers, body: .single(response.body))
        }
    }

    /// Sends one relayed request, and passes its response on as it arrives: the
    /// status and headers first, then the body in chunks. This is what lets a
    /// streamed response, such as Jetpack AI's answer, reach the page as the
    /// server writes it.
    ///
    /// It's the `URLSession` task's delegate. It forwards redirects to
    /// ``RedirectGuard``, and reports the task to the observer.
    ///
    /// `URLSession` holds back a response that has no `Content-Type`, or is
    /// `text/plain`, until it has 512 bytes to guess the type from. Such a response
    /// streams only after its first 512 bytes, unless the server sends
    /// `X-Content-Type-Options: nosniff`. Event streams, JSON, and the other types
    /// tested stream from the first byte.
    ///
    /// It keeps a copy of the body only when there's an observer, which gets the
    /// whole body at the end.
    ///
    /// `@unchecked Sendable`: the mutable state is guarded by `lock`; everything
    /// else is a `let`.
    final class UpstreamTask: NSObject, URLSessionDataDelegate, @unchecked Sendable {
        private let request: URLRequest
        private let redirectGuard: RedirectGuard
        private let observer: (any EditorHTTPClientDelegate)?
        private let reporter: NetworkTaskReporter?

        private let lock = NSLock()
        private var head: CheckedContinuation<URLResponse, any Error>?
        private var body: AsyncThrowingStream<Data, any Error>.Continuation?
        private var received = Data()

        init(_ request: URLRequest, redirectGuard: RedirectGuard, observer: (any EditorHTTPClientDelegate)?) {
            self.request = request
            self.redirectGuard = redirectGuard
            self.observer = observer
            self.reporter = observer.map(NetworkTaskReporter.init(reportingTo:))
        }

        /// Starts the request on `session`. Returns as soon as the response's
        /// status and headers arrive, along with the body to read. Throws if the
        /// server can't be reached.
        ///
        /// Cancelling the calling task, or dropping the body before it ends,
        /// cancels the request.
        func start(on session: URLSession) async throws -> (URLResponse, AsyncThrowingStream<Data, any Error>) {
            let task = session.dataTask(with: request)
            task.delegate = self
            let (stream, continuation) = AsyncThrowingStream<Data, any Error>.makeStream()
            continuation.onTermination = { [weak task] termination in
                if case .cancelled = termination {
                    task?.cancel()
                }
            }
            // `URLSession` only calls `didCreateTask` on a delegate passed in when
            // the task is created, so report the task here.
            reporter?.urlSession(session, didCreateTask: task)

            let response = try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { head in
                    lock.withLock {
                        self.head = head
                        self.body = continuation
                    }
                    task.resume()
                }
            } onCancel: {
                task.cancel()
            }
            return (response, stream)
        }

        // MARK: - URLSessionDataDelegate

        func urlSession(
            _ session: URLSession,
            dataTask: URLSessionDataTask,
            didReceive response: URLResponse,
            completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
        ) {
            lock.withLock { head.take() }?.resume(returning: response)
            completionHandler(.allow)
        }

        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
            let body = lock.withLock {
                if observer != nil {
                    received.append(data)
                }
                return self.body
            }
            body?.yield(data)
        }

        func urlSession(
            _ session: URLSession,
            task: URLSessionTask,
            willPerformHTTPRedirection response: HTTPURLResponse,
            newRequest request: URLRequest,
            completionHandler: @escaping (URLRequest?) -> Void
        ) {
            redirectGuard.urlSession(
                session,
                task: task,
                willPerformHTTPRedirection: response,
                newRequest: request,
                completionHandler: completionHandler
            )
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
            reporter?.urlSession(session, task: task, didFinishCollecting: metrics)
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
            let (head, body, received) = lock.withLock {
                (self.head.take(), self.body.take(), self.received)
            }
            reporter?.complete(with: error == nil ? .bytes(received) : nil, error: error)

            if let error {
                // Don't log a cancellation: it means the page stopped reading.
                if head == nil, (error as? URLError)?.code != .cancelled {
                    Logger.restRelay.error("Upstream response failed partway: \(error.localizedDescription)")
                }
                head?.resume(throwing: error)
                body?.finish(throwing: error)
                return
            }
            // No response arrived, which shouldn't happen over HTTP. Fail the
            // caller rather than leave it waiting.
            head?.resume(throwing: URLError(.badServerResponse))

            // Don't report a refused redirect's 3xx response as an answer: the
            // relay doesn't pass it on to the page.
            if redirectGuard.refusal == nil, let response = task.response {
                observer?.didPerformRequest(request, response: response, data: .bytes(received))
            }
            body?.finish()
        }
    }
}

extension AsyncThrowingStream where Element == Data, Failure == any Error {
    /// A stream with `data` as its only chunk, or an empty stream when `data` is
    /// empty.
    static func single(_ data: Data) -> Self {
        AsyncThrowingStream { continuation in
            if !data.isEmpty {
                continuation.yield(data)
            }
            continuation.finish()
        }
    }
}
