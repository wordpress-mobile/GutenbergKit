import Foundation
import WebKit

/// The requests a URL scheme handler has started and WebKit hasn't stopped, with the work
/// answering each.
///
/// WebKit raises an Objective-C exception if a stopped task is answered, so a handler
/// answers a task only through this, which does nothing for one WebKit has stopped.
///
/// Each task is tracked under a number that is never reused, not under its address.
/// WebKit can create a new task at the address of one it just stopped, while the work for
/// the stopped task is still running. Tracked by address, that work would answer the new
/// task.
@MainActor
struct ActiveSchemeTasks {
    /// A task's number. Counts up from zero and is never reused.
    typealias Key = Int

    private var entries: [Key: Entry] = [:]

    /// The number of each task in `entries`, for `stop(_:)`, which WebKit calls with the
    /// task itself. Looking a task up by its address is safe here: a task is held while it
    /// is in `entries`, so no other task can have its address.
    private var keys: [ObjectIdentifier: Key] = [:]

    private var nextKey: Key = 0

    private struct Entry {
        let task: any WKURLSchemeTask
        var work: Task<Void, Never>?
    }

    var count: Int { entries.count }

    /// Tracks `task`, answered by the work `answer` starts. `answer` is given the key the
    /// task is answered under.
    mutating func start(_ task: any WKURLSchemeTask, answer: (Key) -> Task<Void, Never>) {
        let key = nextKey
        nextKey += 1
        keys[ObjectIdentifier(task)] = key
        entries[key] = Entry(task: task, work: nil)
        entries[key]?.work = answer(key)
    }

    /// Stops tracking `task` and cancels its work: WebKit stopped it, because the page
    /// aborted its `fetch` or went away.
    mutating func stop(_ task: any WKURLSchemeTask) {
        guard let key = keys[ObjectIdentifier(task)] else { return }
        removeEntry(key)?.work?.cancel()
    }

    /// Cancels the work answering every task. Each is still answered, as its work
    /// answers a cancellation.
    func cancelAll() {
        for entry in entries.values {
            entry.work?.cancel()
        }
    }

    /// The task under `key`, or `nil` once WebKit has stopped it.
    func task(for key: Key) -> (any WKURLSchemeTask)? {
        entries[key]?.task
    }

    /// Stops tracking the task under `key` and returns it, for a handler that answers it
    /// in parts. `nil` once WebKit has stopped it.
    mutating func remove(_ key: Key) -> (any WKURLSchemeTask)? {
        removeEntry(key)?.task
    }

    /// Answers the task under `key` with `response` and stops tracking it, unless WebKit
    /// has stopped it.
    mutating func answer(_ key: Key, with response: SchemeResponse) {
        guard let task = respond(key, status: response.status, headers: response.headers) else { return }
        if !response.body.isEmpty {
            task.didReceive(response.body)
        }
        finish(key)
    }

    /// Sends a response's status and headers to the task under `key`, and returns the
    /// task so the caller can send the body in chunks. Returns `nil` if WebKit has
    /// stopped the task, or if the headers are invalid, which also fails the task.
    mutating func respond(_ key: Key, status: Int, headers: [String: String]) -> (any WKURLSchemeTask)? {
        guard let task = task(for: key) else { return nil }
        guard let url = task.request.url,
              let httpResponse = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers) else {
            fail(key, with: URLError(.badServerResponse))
            return nil
        }
        task.didReceive(httpResponse)
        return task
    }

    /// Finishes the task under `key` and stops tracking it, unless WebKit has stopped it.
    mutating func finish(_ key: Key) {
        remove(key)?.didFinish()
    }

    /// Fails the task under `key` with `error` and stops tracking it, unless WebKit has
    /// stopped it.
    mutating func fail(_ key: Key, with error: any Error) {
        remove(key)?.didFailWithError(error)
    }

    /// Fails the task under `key` with `error`, stops tracking it, and cancels its work,
    /// unless WebKit has stopped it.
    mutating func abandon(_ key: Key, failingWith error: any Error) {
        guard let entry = removeEntry(key) else { return }
        entry.work?.cancel()
        entry.task.didFailWithError(error)
    }

    /// Stops tracking the task under `key` and returns its entry.
    private mutating func removeEntry(_ key: Key) -> Entry? {
        guard let entry = entries.removeValue(forKey: key) else { return nil }
        keys.removeValue(forKey: ObjectIdentifier(entry.task))
        return entry
    }
}
