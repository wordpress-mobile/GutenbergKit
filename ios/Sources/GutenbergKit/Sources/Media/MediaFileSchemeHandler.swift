import Foundation
import OSLog
import UniformTypeIdentifiers
import WebKit

/// Serves imported media to the editor's page over `gbk-media-file:` URLs.
///
/// Streams each file in chunks rather than loading it: a whole-file read held the file
/// in memory twice in the app, and a 1 GB video pushed WebKit's page process past its
/// 2 GB limit before the page could read it.
///
/// Tracks every request it is serving, held strongly, so it never answers one WebKit
/// has stopped — the page cancelled its `fetch`, or went away. Answering a stopped task
/// raises an Objective-C exception.
@MainActor
final class MediaFileSchemeHandler: NSObject, WKURLSchemeHandler {
    nonisolated static let scheme = "gbk-media-file"

    /// How much of a file each `didReceive` carries.
    static let chunkSize = 1024 * 1024

    private let rootURL: URL
    private var active: [ObjectIdentifier: ActiveRequest] = [:]

    private struct ActiveRequest {
        let task: any WKURLSchemeTask
        var work: Task<Void, Never>?
    }

    init(rootURL: URL = MediaFileManager.defaultRootURL) {
        self.rootURL = rootURL
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
        start(urlSchemeTask)
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {
        stop(urlSchemeTask)
    }

    /// `webView(_:start:)` without the web view, for tests.
    func start(_ task: any WKURLSchemeTask) {
        guard let url = task.request.url,
              let fileURL = MediaFileManager.fileURL(for: url, root: rootURL) else {
            task.didFailWithError(URLError(.badURL))
            return
        }
        let key = ObjectIdentifier(task)
        active[key] = ActiveRequest(task: task, work: nil)
        active[key]?.work = Task { [weak self] in
            await self?.serve(fileURL, to: key)
        }
    }

    /// `webView(_:stop:)` without the web view, for tests.
    func stop(_ task: any WKURLSchemeTask) {
        active.removeValue(forKey: ObjectIdentifier(task))?.work?.cancel()
    }

    var activeRequestCount: Int { active.count }

    private func serve(_ fileURL: URL, to key: ObjectIdentifier) async {
        let reader: ChunkedFileReader
        do {
            reader = try await ChunkedFileReader.open(fileURL)
        } catch {
            fail(key, with: error)
            return
        }
        defer { reader.close() }

        guard let url = active[key]?.task.request.url,
              let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: [
                "Content-Type": UTType(filenameExtension: fileURL.pathExtension)?.preferredMIMEType ?? "application/octet-stream",
                "Content-Length": "\(reader.size)",
                "Access-Control-Allow-Origin": "*",
                "Access-Control-Allow-Methods": "GET, HEAD, OPTIONS",
                "Access-Control-Allow-Headers": "*",
                "Cache-Control": "no-cache",
              ]) else {
            fail(key, with: URLError(.badServerResponse))
            return
        }
        guard let task = active[key]?.task else { return }
        task.didReceive(response)

        while true {
            let chunk: Data
            do {
                chunk = try await reader.read(upToCount: Self.chunkSize)
            } catch {
                fail(key, with: error)
                return
            }
            // Stopped while the chunk was read: WebKit raises if it is answered now.
            guard let task = active[key]?.task else { return }
            if chunk.isEmpty {
                active.removeValue(forKey: key)
                task.didFinish()
                return
            }
            task.didReceive(chunk)
        }
    }

    private func fail(_ key: ObjectIdentifier, with error: any Error) {
        guard let request = active.removeValue(forKey: key) else { return }
        Logger.media.error("Failed to serve \(request.task.request.url?.absoluteString ?? "?"): \(error)")
        request.task.didFailWithError(error)
    }
}

/// Reads a file off the main actor, a chunk at a time.
private final class ChunkedFileReader: @unchecked Sendable {
    private let handle: FileHandle
    let size: Int

    private init(handle: FileHandle, size: Int) {
        self.handle = handle
        self.size = size
    }

    static func open(_ url: URL) async throws -> ChunkedFileReader {
        let size = try FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false))[.size] as? Int ?? 0
        return ChunkedFileReader(handle: try FileHandle(forReadingFrom: url), size: size)
    }

    func read(upToCount count: Int) async throws -> Data {
        try handle.read(upToCount: count) ?? Data()
    }

    func close() {
        try? handle.close()
    }
}
