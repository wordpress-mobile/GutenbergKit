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
        guard let task = remove(key) else { return }
        guard let url = response.url ?? task.request.url,
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
    mutating func fail(_ key: Key, with error: any Error) {
        remove(key)?.didFailWithError(error)
    }

    /// Stops tracking the task under `key` and returns its entry.
    private mutating func removeEntry(_ key: Key) -> Entry? {
        guard let entry = entries.removeValue(forKey: key) else { return nil }
        keys.removeValue(forKey: ObjectIdentifier(entry.task))
        return entry
    }
}
