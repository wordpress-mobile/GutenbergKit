import Foundation
import OSLog
import WebKit

/// Experimental file transport. Processing stays native; uploading stays in JavaScript.
@MainActor
final class MediaProcessingBridge: NSObject, WKScriptMessageHandlerWithReply, WKURLSchemeHandler {
    static let scheme = "gbk-processed-media"
    let store = MediaProcessingStore()
    private var reads: [ObjectIdentifier: Task<Void, Never>] = [:]

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) async -> (Any?, String?) {
        guard message.frameInfo.isMainFrame,
              let data = try? JSONSerialization.data(withJSONObject: message.body),
              let request = try? JSONDecoder().decode(MediaProcessingStore.Request.self, from: data) else {
            return (nil, "Invalid media processing request.")
        }
        do {
            let response = try await store.handle(request)
            let data = try JSONEncoder().encode(response)
            return (try JSONSerialization.jsonObject(with: data), nil)
        } catch {
            return (nil, error.localizedDescription)
        }
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
        let key = ObjectIdentifier(urlSchemeTask)
        reads[key] = Task {
            defer { reads[key] = nil }
            do {
                guard let url = urlSchemeTask.request.url,
                      urlSchemeTask.request.httpMethod == "GET" else {
                    throw URLError(.badURL)
                }
                let output = try await store.output(for: url)
                try Task.checkCancellation()
                let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: [
                    "Content-Type": output.mimeType,
                    "Content-Length": String(output.size),
                    "Access-Control-Allow-Origin": "*",
                    "Cache-Control": "no-store"
                ])!
                urlSchemeTask.didReceive(response)
                let file = try FileHandle(forReadingFrom: output.url)
                defer { try? file.close() }
                while let data = try file.read(upToCount: MediaProcessingStore.chunkSize), !data.isEmpty {
                    try Task.checkCancellation()
                    urlSchemeTask.didReceive(data)
                    await Task.yield()
                }
                try Task.checkCancellation()
                Logger.uploadServer.info("Media bridge served processed file: \(output.size) bytes")
                urlSchemeTask.didFinish()
            } catch {
                if !Task.isCancelled {
                    urlSchemeTask.didFailWithError(error)
                }
            }
        }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {
        reads.removeValue(forKey: ObjectIdentifier(urlSchemeTask))?.cancel()
    }
}

/// Owns temporary files until JavaScript has read the output or cancelled the transfer.
actor MediaProcessingStore {
    static let chunkSize = 256 * 1024

    struct Request: Codable, Sendable {
        let action: String
        let id: String
        var filename: String?
        var mimeType: String?
        var size: Int?
        var offset: Int?
        var data: String?
    }

    struct Reply: Codable, Sendable {
        var accepted: Bool?
        var url: String?
        var filename: String?
        var mimeType: String?
        var size: Int?
    }

    struct Output: Sendable {
        let url: URL
        let filename: String
        let mimeType: String
        let size: Int
    }

    private struct Entry {
        let directory: URL
        let input: URL
        let filename: String
        let mimeType: String
        let size: Int
        var received = 0
        var output: Output?
    }

    private weak var delegate: (any MediaUploadDelegate)?
    private var entries: [String: Entry] = [:]
    private var processing: [String: Task<ProcessedProxyFile, Error>] = [:]

    func configure(delegate: any MediaUploadDelegate) {
        self.delegate = delegate
    }

    func handle(_ request: Request) async throws -> Reply {
        guard UUID(uuidString: request.id) != nil else { throw Failure.invalidRequest }
        switch request.action {
        case "begin": return try begin(request)
        case "append": return try append(request)
        case "finish": return try await finish(request.id)
        case "release", "cancel":
            release(request.id)
            return Reply()
        default: throw Failure.invalidRequest
        }
    }

    private func begin(_ request: Request) throws -> Reply {
        guard entries[request.id] == nil, processing[request.id] == nil,
              entries.count < 8,
              let filename = request.filename, !filename.isEmpty,
              let mimeType = request.mimeType,
              let size = request.size, size >= 0, size <= 4 * 1024 * 1024 * 1024,
              let delegate else { throw Failure.invalidRequest }
        guard delegate.handlesFile(ofType: mimeType, named: filename) else {
            return Reply(accepted: false)
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("gbk-processing-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let input = directory.appendingPathComponent("input")
        do {
            try Data().write(to: input)
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
        entries[request.id] = Entry(directory: directory, input: input, filename: filename, mimeType: mimeType, size: size)
        Logger.uploadServer.info("Media bridge began transfer: \(size) bytes")
        return Reply(accepted: true)
    }

    private func append(_ request: Request) throws -> Reply {
        guard var entry = entries[request.id], processing[request.id] == nil, entry.output == nil,
              request.offset == entry.received,
              let encoded = request.data, encoded.utf8.count <= ((Self.chunkSize + 2) / 3) * 4,
              let data = Data(base64Encoded: encoded), !data.isEmpty, data.count <= Self.chunkSize,
              entry.received + data.count <= entry.size else { throw Failure.invalidRequest }
        let file = try FileHandle(forWritingTo: entry.input)
        defer { try? file.close() }
        try file.seekToEnd()
        try file.write(contentsOf: data)
        entry.received += data.count
        entries[request.id] = entry
        return Reply()
    }

    private func finish(_ id: String) async throws -> Reply {
        guard var entry = entries[id], entry.received == entry.size, entry.output == nil,
              processing[id] == nil, let delegate else { throw Failure.invalidRequest }
        let input = entry.input
        let mimeType = entry.mimeType
        let filename = entry.filename
        let task = Task { try await delegate.processFile(at: input, mimeType: mimeType, filename: filename) }
        processing[id] = task
        do {
            let result = try await task.value
            let outputURL: URL
            let outputFilename: String
            let outputType: String
            switch result {
            case .original:
                outputURL = entry.input
                outputFilename = entry.filename
                outputType = entry.mimeType
            case let .processed(url, mimeType, filename):
                outputURL = url
                outputFilename = filename
                outputType = mimeType
            }
            // The existing delegate contract transfers ownership of its output file.
            defer {
                if outputURL != entry.input {
                    try? FileManager.default.removeItem(at: outputURL)
                }
            }
            guard !task.isCancelled, entries[id] != nil else { throw CancellationError() }
            let ownedOutput = entry.directory.appendingPathComponent("processed-\(UUID().uuidString)")
            try FileManager.default.copyItem(at: outputURL, to: ownedOutput)
            let size = try ownedOutput.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            entry.output = Output(url: ownedOutput, filename: outputFilename, mimeType: outputType, size: size)
            entries[id] = entry
            processing[id] = nil
            Logger.uploadServer.info("Media bridge processed file: \(entry.size) -> \(size) bytes; upload remains in JavaScript")
            return Reply(url: "gbk-processed-media://\(id)/output", filename: outputFilename, mimeType: outputType, size: size)
        } catch {
            processing[id] = nil
            entries[id] = nil
            try? FileManager.default.removeItem(at: entry.directory)
            throw error
        }
    }

    func output(for url: URL) throws -> Output {
        guard url.scheme == "gbk-processed-media", let id = url.host,
              url.path == "/output", let output = entries[id]?.output else { throw Failure.invalidRequest }
        return output
    }

    private func release(_ id: String) {
        let entry = entries.removeValue(forKey: id)
        if let task = processing[id] {
            // The processor may still be reading the input; finish cleans up when it exits.
            task.cancel()
        } else if let entry {
            try? FileManager.default.removeItem(at: entry.directory)
        }
    }

    func removeAll() {
        for id in Array(entries.keys) {
            release(id)
        }
    }

    enum Failure: LocalizedError {
        case invalidRequest

        var errorDescription: String? { "The media processing transfer is invalid or has expired." }
    }
}
