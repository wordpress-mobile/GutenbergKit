import Foundation
import OSLog
import WebKit

/// Receives the editor's media uploads over a `gbk-upload:` URL scheme and delivers
/// them to WordPress through a ``MediaUploading`` service.
///
/// The page's `nativeMediaUploadMiddleware` sends a file in chunks rather than as one
/// request: WebKit hands a scheme handler only bodies it has already buffered, and it
/// drops a `Blob` body — including a `FormData` that holds one — without an error. An
/// `ArrayBuffer` of a few megabytes always arrives. The table of what was measured is in
/// `docs/code/media-uploads.md`. The protocol:
///
/// | Request | Body | Response |
/// |---|---|---|
/// | `POST gbk-upload://upload/sessions` | JSON `{filename, mimeType, size}` | `201 {"id"}` |
/// | `POST …/sessions/<id>/chunks?offset=N` | the chunk's bytes | `200 {"received"}` |
/// | `POST …/sessions/<id>/finish` | JSON `{fields, query}` | WordPress's response, verbatim |
/// | `POST …/sessions/<id>/cancel` | — | `204` |
/// | `POST …/media/<attachmentId>/delete` | JSON `{query}` | WordPress's response, verbatim |
///
/// Only the editor's own web view can load this scheme, so there is no token to check.
/// Every response carries CORS headers: under Lockdown Mode WebKit enforces CORS on
/// scheme responses too, and core's upload middleware reads
/// `x-wp-upload-attachment-id` off a failed upload to recover it.
@MainActor
final class MediaUploadSchemeHandler: NSObject, WKURLSchemeHandler {
    nonisolated static let scheme = "gbk-upload"

    /// How long a session may sit without a chunk before it is abandoned.
    static let sessionIdleTimeout: TimeInterval = 3600

    let store: MediaUploadSessionStore
    private var service: (any MediaUploading)?

    /// Every request WebKit has started and not stopped, held strongly: a finished
    /// task's identity can be reused by the next one, so tracking tasks by identifier
    /// alone answers the wrong request.
    private var active: [ObjectIdentifier: ActiveRequest] = [:]

    private struct ActiveRequest {
        let task: any WKURLSchemeTask
        var work: Task<Void, Never>?
    }

    init(service: (any MediaUploading)?, store: MediaUploadSessionStore = MediaUploadSessionStore()) {
        self.service = service
        self.store = store
        super.init()
        Task.detached(priority: .utility) {
            MediaUploadSessionStore.removeAbandonedStaging()
        }
    }

    /// Whether uploads are accepted. `false` once ``disable()`` has run, or when the
    /// editor had no media handling to begin with.
    var isEnabled: Bool { service != nil }

    /// Stops accepting uploads, cancels the ones in flight, and deletes every staged
    /// file. Requests after this get a `503`, which the page takes as the cue to upload
    /// through the web view instead.
    func disable() {
        service = nil
        for request in active.values {
            request.work?.cancel()
        }
        let store = store
        Task { await store.removeAll() }
    }

    // MARK: - WKURLSchemeHandler

    func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
        start(urlSchemeTask)
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {
        stop(urlSchemeTask)
    }

    /// `webView(_:start:)` without the web view, for tests.
    func start(_ task: any WKURLSchemeTask) {
        let key = ObjectIdentifier(task)
        let request = task.request
        active[key] = ActiveRequest(task: task, work: nil)
        active[key]?.work = Task { [weak self] in
            guard let self else { return }
            let response = await self.response(to: request)
            self.reply(to: key, with: response)
        }
    }

    /// `webView(_:stop:)` without the web view, for tests.
    ///
    /// WebKit stops a task when the page aborts its `fetch` or goes away. Cancelling the
    /// work cancels an upload to WordPress in flight — nobody is left to read its
    /// response — and dropping the task keeps `reply` from answering it: answering a
    /// stopped task raises an Objective-C exception.
    func stop(_ task: any WKURLSchemeTask) {
        active.removeValue(forKey: ObjectIdentifier(task))?.work?.cancel()
    }

    var activeRequestCount: Int { active.count }

    // MARK: - Routing

    private func response(to request: URLRequest) async -> SchemeResponse {
        let route = Route(request)
        if case .preflight = route {
            return SchemeResponse(status: 204)
        }
        guard let service else {
            return .error(503, code: "native_upload_unavailable", message: "Native media uploads are not available in this editor.")
        }
        do {
            switch route {
            case .beginSession:
                let body = try Self.decode(BeginRequest.self, from: request)
                await store.sweep(idleFor: Self.sessionIdleTimeout)
                let id = try await store.begin(filename: body.filename, mimeType: body.mimeType, expectedSize: body.size)
                return .json(201, ["id": id])

            case let .appendChunk(id, offset):
                guard let data = request.httpBody, !data.isEmpty else {
                    // WebKit delivers an `ArrayBuffer` body; an empty one here means the
                    // page sent something WebKit dropped, and appending nothing would
                    // leave the file short without anyone noticing.
                    return .error(400, code: "native_upload_empty_chunk", message: "The upload chunk had no body.")
                }
                let received = try await store.append(data, to: id, at: offset)
                return .json(200, ["received": received])

            case let .finishSession(id):
                let body = try Self.decode(FinishRequest.self, from: request)
                let finished = try await store.take(id)
                defer { finished.cleanUp() }
                let result = try await withBackgroundActivity("gutenbergkit-media-upload") {
                    try await service.upload(finished.file, fields: body.fields, query: body.query)
                }
                return .relay(result)

            case let .cancelSession(id):
                await store.discard(id)
                return SchemeResponse(status: 204)

            case let .deleteMedia(attachmentId):
                let body = try Self.decode(DeleteRequest.self, from: request)
                return .relay(try await service.delete(attachmentId: attachmentId, query: body.query))

            case .preflight:
                return SchemeResponse(status: 204)

            case .unknown:
                return .error(404, code: "native_upload_not_found", message: "Unknown native upload request.")
            }
        } catch let failure as MediaUploadSessionStore.Failure {
            return Self.response(for: failure)
        } catch is DecodingError {
            return .error(400, code: "native_upload_bad_request", message: "The native upload request was malformed.")
        } catch is CancellationError {
            // Stopped by the page, or by `disable()`. A stopped task drops this reply.
            return .error(503, code: "native_upload_cancelled", message: "The upload was cancelled.")
        } catch {
            if Task.isCancelled {
                return .error(503, code: "native_upload_cancelled", message: "The upload was cancelled.")
            }
            Logger.mediaUpload.error("Native upload failed: \(error)")
            return .error(500, code: "upload_error", message: error.localizedDescription)
        }
    }

    private func reply(to key: ObjectIdentifier, with response: SchemeResponse) {
        guard let request = active.removeValue(forKey: key) else {
            return  // Stopped: WebKit raises if a stopped task is answered.
        }
        let task = request.task
        guard let url = task.request.url,
              let httpResponse = HTTPURLResponse(
                url: url,
                statusCode: response.status,
                httpVersion: "HTTP/1.1",
                headerFields: response.headers.merging(Self.corsHeaders) { current, _ in current }
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

    // MARK: - Helpers

    private static let corsHeaders: [String: String] = [
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Methods": "POST, OPTIONS",
        "Access-Control-Allow-Headers": "*",
        // Core's upload middleware reads this off a failed upload to recover it; a
        // CORS response hides every header it doesn't list.
        "Access-Control-Expose-Headers": "x-wp-upload-attachment-id",
        "Cache-Control": "no-store",
    ]

    private static func response(for failure: MediaUploadSessionStore.Failure) -> SchemeResponse {
        switch failure {
        case .unknownSession:
            return .error(404, code: "native_upload_session_not_found", message: "The upload session does not exist.")
        case let .offsetMismatch(expected, offset):
            return .error(409, code: "native_upload_offset_mismatch", message: "Expected a chunk at offset \(expected), got \(offset).")
        case .tooLarge:
            return .error(413, code: "upload_file_too_big", message: "The file is too large to upload in the editor.")
        case let .incomplete(expected, received):
            return .error(409, code: "native_upload_incomplete", message: "Received \(received) of \(expected) bytes.")
        }
    }

    private static func decode<T: Decodable>(_ type: T.Type, from request: URLRequest) throws -> T {
        try JSONDecoder().decode(T.self, from: request.httpBody ?? Data("{}".utf8))
    }

    private struct BeginRequest: Decodable {
        let filename: String
        let mimeType: String
        let size: Int?
    }

    private struct FinishRequest: Decodable {
        let fields: [MediaUploadField]
        let query: String

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            fields = try container.decodeIfPresent([MediaUploadField].self, forKey: .fields) ?? []
            query = try container.decodeIfPresent(String.self, forKey: .query) ?? ""
        }

        private enum CodingKeys: String, CodingKey { case fields, query }
    }

    private struct DeleteRequest: Decodable {
        let query: String

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            query = try container.decodeIfPresent(String.self, forKey: .query) ?? ""
        }

        private enum CodingKeys: String, CodingKey { case query }
    }

    /// A request, by what it asks for.
    private enum Route {
        case beginSession
        case appendChunk(id: String, offset: Int)
        case finishSession(id: String)
        case cancelSession(id: String)
        case deleteMedia(attachmentId: String)
        case preflight
        case unknown

        init(_ request: URLRequest) {
            guard let url = request.url else { self = .unknown; return }
            if request.httpMethod == "OPTIONS" { self = .preflight; return }
            guard request.httpMethod == "POST" else { self = .unknown; return }

            let parts = url.path(percentEncoded: false).split(separator: "/").map(String.init)
            let offset = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first { $0.name == "offset" }?.value.flatMap(Int.init)

            switch parts.count {
            case 1 where parts[0] == "sessions":
                self = .beginSession
            case 3 where parts[0] == "sessions":
                switch parts[2] {
                case "chunks":
                    guard let offset, offset >= 0 else { self = .unknown; return }
                    self = .appendChunk(id: parts[1], offset: offset)
                case "finish": self = .finishSession(id: parts[1])
                case "cancel": self = .cancelSession(id: parts[1])
                default: self = .unknown
                }
            case 3 where parts[0] == "media" && parts[2] == "delete" && !parts[1].isEmpty && parts[1].allSatisfy(\.isNumber):
                self = .deleteMedia(attachmentId: parts[1])
            default:
                self = .unknown
            }
        }
    }
}

/// A response for the scheme handler to send.
struct SchemeResponse: Sendable {
    let status: Int
    var headers: [String: String] = [:]
    var body = Data()

    static func json(_ status: Int, _ object: [String: any Sendable]) -> SchemeResponse {
        let body = (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
        return SchemeResponse(status: status, headers: ["Content-Type": "application/json"], body: body)
    }

    /// A WordPress-shaped error, `{code, message, data: {status}}`, so the page
    /// surfaces it the way it surfaces WordPress's own.
    static func error(_ status: Int, code: String, message: String) -> SchemeResponse {
        json(status, ["code": code, "message": message, "data": ["status": status]])
    }

    /// WordPress's response verbatim: its status, body, and the headers worth
    /// relaying. It is JSON unless WordPress said otherwise.
    static func relay(_ response: MediaUploadResponse) -> SchemeResponse {
        var headers = response.headers
        if !headers.keys.contains(where: { $0.caseInsensitiveCompare("Content-Type") == .orderedSame }) {
            headers["Content-Type"] = "application/json"
        }
        return SchemeResponse(status: response.statusCode, headers: headers, body: response.body)
    }
}
