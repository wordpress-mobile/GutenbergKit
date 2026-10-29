import Foundation
@testable import GutenbergKit

/// An ``EditorHTTPClientDelegate`` that records each call, in order, as a short event
/// name, with what the task completed with.
final class TaskEventRecorder: EditorHTTPClientDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var _events: [String] = []
    private var _tasks: [ObjectIdentifier] = []
    private var _completedData: EditorResponseData?
    private var _completionError: (any Error)?

    /// `created`, `metrics`, `completed` or `failed`, and `performed`, in the order
    /// they were reported.
    var events: [String] { lock.withLock { _events } }

    /// Every task a task callback reported, in order.
    var tasks: [ObjectIdentifier] { lock.withLock { _tasks } }

    var completedData: EditorResponseData? { lock.withLock { _completedData } }
    var completionError: (any Error)? { lock.withLock { _completionError } }

    func didPerformRequest(_ request: URLRequest, response: URLResponse, data: EditorResponseData) {
        lock.withLock { _events.append("performed") }
    }

    func didCreateTask(_ task: URLSessionTask) {
        lock.withLock {
            _events.append("created")
            _tasks.append(ObjectIdentifier(task))
        }
    }

    func task(_ task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
        lock.withLock {
            _events.append("metrics")
            _tasks.append(ObjectIdentifier(task))
        }
    }

    func task(_ task: URLSessionTask, didCompleteWith data: EditorResponseData?, error: (any Error)?) {
        lock.withLock {
            _events.append(error == nil ? "completed" : "failed")
            _tasks.append(ObjectIdentifier(task))
            _completedData = data
            _completionError = error
        }
    }
}
