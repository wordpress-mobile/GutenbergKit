import Foundation
import WebKit

/// The requests a URL scheme handler has started and WebKit hasn't stopped, with the work
/// answering each.
///
/// WebKit raises an Objective-C exception if a stopped task is answered, so a handler
/// answers a task only through this, which does nothing for one WebKit has stopped. Tasks
/// are held strongly: a finished task's identity can be reused by the next one, so
/// tracking tasks by identifier alone would answer the wrong request.
@MainActor
struct ActiveSchemeTasks {
    private var entries: [ObjectIdentifier: Entry] = [:]

    private struct Entry {
        let task: any WKURLSchemeTask
        var work: Task<Void, Never>?
    }

    var count: Int { entries.count }

    /// Tracks `task`, answered by the work `answer` starts. `answer` is given the key the
    /// task is answered under.
    mutating func start(_ task: any WKURLSchemeTask, answer: (ObjectIdentifier) -> Task<Void, Never>) {
        let key = ObjectIdentifier(task)
        entries[key] = Entry(task: task, work: nil)
        entries[key]?.work = answer(key)
    }

    /// Stops tracking `task` and cancels its work: WebKit stopped it, because the page
    /// aborted its `fetch` or went away.
    mutating func stop(_ task: any WKURLSchemeTask) {
        entries.removeValue(forKey: ObjectIdentifier(task))?.work?.cancel()
    }

    /// Cancels the work answering every task. Each is still answered, as its work
    /// answers a cancellation.
    func cancelAll() {
        for entry in entries.values {
            entry.work?.cancel()
        }
    }

    /// The task under `key`, or `nil` once WebKit has stopped it.
    func task(for key: ObjectIdentifier) -> (any WKURLSchemeTask)? {
        entries[key]?.task
    }

    /// Stops tracking the task under `key` and returns it, for a handler that answers it
    /// in parts. `nil` once WebKit has stopped it.
    mutating func remove(_ key: ObjectIdentifier) -> (any WKURLSchemeTask)? {
        entries.removeValue(forKey: key)?.task
    }

    /// Answers the task under `key` with `response` and stops tracking it, unless WebKit
    /// has stopped it.
    mutating func answer(_ key: ObjectIdentifier, with response: SchemeResponse) {
        guard let task = remove(key) else { return }
        guard let url = task.request.url,
              let httpResponse = HTTPURLResponse(
                url: url,
                statusCode: response.status,
                httpVersion: "HTTP/1.1",
                headerFields: response.headers
              ) else {
            task.didFailWithError(URLError(.badServerResponse))
            return
        }
        task.didReceive(httpResponse)
        if !response.body.isEmpty {
            task.didReceive(response.body)
        }
        task.didFinish()
    }

    /// Fails the task under `key` with `error` and stops tracking it, unless WebKit has
    /// stopped it.
    mutating func fail(_ key: ObjectIdentifier, with error: any Error) {
        remove(key)?.didFailWithError(error)
    }
}
