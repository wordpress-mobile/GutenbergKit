import Foundation
import Testing

@testable import GutenbergKit

#if canImport(UIKit)

/// Pins that ``EditorViewController/stopMediaHandling()`` opens the ownership cycle a host
/// can form, and that a host which doesn't form one needs nothing.
///
/// The editor holds `mediaProcessor` strongly so an in-flight upload can't lose it
/// mid-request. The cost is that a host which holds the editor back closes a cycle ARC
/// cannot break — and `deinit`, which does this work on every other path, is exactly what
/// a cycle prevents. `stopMediaHandling()` is the way out, and it has to be the host's
/// call: not because UIKit can't report a teardown, but because it can't report whether
/// one is permanent. A host may re-present or re-attach the same editor, and the call is
/// terminal, so guessing wrong disables media in an editor that survived.
///
/// Also runs the page side of the native upload protocol inside the editor's own web
/// view, so the scheme handler is exercised by real WebKit.
@Suite("EditorViewController media teardown")
struct EditorViewControllerMediaTeardownTests: MakesTestFixtures {
    static let testSiteURL = URL(string: "https://test.example.com")!
    static let testApiRoot = URL(string: "https://test.example.com/wp-json/wp/v2")!

    @MainActor
    @Test("stopMediaHandling frees the editor and the host processor that owns it")
    func stopMediaHandlingBreaksTheOwnershipCycle() async {
        weak var weakEditor: EditorViewController?
        weak var weakHost: EditorOwningProcessor?

        do {
            let host = EditorOwningProcessor(configuration: makeConfiguration())
            weakEditor = host.editor
            weakHost = host
            host.editor.stopMediaHandling()
        }

        await waitForRelease { weakHost == nil && weakEditor == nil }

        #expect(weakHost == nil, "host processor leaked — stopMediaHandling did not release it")
        #expect(weakEditor == nil, "EditorViewController leaked — cycle through mediaProcessor")
    }

    @MainActor
    @Test("a host that does not retain the editor is freed without stopMediaHandling")
    func standaloneProcessorIsFreed() async {
        weak var weakEditor: EditorViewController?

        do {
            let editor = EditorViewController(
                configuration: makeConfiguration(),
                mediaProcessor: StandaloneProcessor()
            )
            weakEditor = editor
        }

        await waitForRelease { weakEditor == nil }

        #expect(weakEditor == nil, "EditorViewController leaked — nothing here retains it")
    }

    // MARK: - Which handlers enable native uploads

    /// Android pins the same gate (`GutenbergViewUploadServerTest`, "the upload server
    /// starts for an uploader with no processor"). An uploader-only host once had its
    /// native upload path silently disabled on iOS, so each combination is pinned.
    @MainActor
    @Test(
        "native uploads are enabled for whichever handler the host supplied",
        arguments: [
            ("uploader only", false, true),
            ("processor only", true, false),
            ("both", true, true)
        ]
    )
    func nativeUploadsEnabledForAnyHandler(_ label: String, processor: Bool, uploader: Bool) {
        let editor = EditorViewController(
            configuration: makeConfiguration(),
            mediaProcessor: processor ? StandaloneProcessor() : nil,
            mediaUploader: uploader ? InertUploader() : nil
        )
        defer { editor.stopMediaHandling() }

        #expect(editor.mediaUploadSchemeHandler.isEnabled, "\(label): the host's media handling would never run")
        #expect(editor.webView.configuration.urlSchemeHandler(forURLScheme: MediaUploadSchemeHandler.scheme) != nil)
    }

    @MainActor
    @Test("no handler leaves native uploads disabled")
    func noHandlerLeavesNativeUploadsDisabled() {
        let editor = EditorViewController(configuration: makeConfiguration())

        #expect(!editor.mediaUploadSchemeHandler.isEnabled, "enabled native uploads with nothing to route them through")
    }

    @MainActor
    @Test("a processor without site credentials leaves native uploads disabled")
    func processorWithoutCredentials() {
        let configuration = makeConfigurationBuilder().setAuthHeader("").build()
        let editor = EditorViewController(configuration: configuration, mediaProcessor: StandaloneProcessor())

        #expect(!editor.mediaUploadSchemeHandler.isEnabled)
    }

    @MainActor
    @Test("stopMediaHandling disables native uploads")
    func stopMediaHandlingDisablesNativeUploads() {
        let editor = EditorViewController(configuration: makeConfiguration(), mediaUploader: InertUploader())

        editor.stopMediaHandling()

        #expect(!editor.mediaUploadSchemeHandler.isEnabled)
        #expect(editor.mediaUploader == nil)
    }

    // MARK: - Uploads from the editor's own web view

    @MainActor
    @Test("the page uploads a file in chunks, and the host's uploader receives it intact")
    func pageUploadsInChunks() async throws {
        let uploader = RecordingUploader()
        let editor = EditorViewController(configuration: makeConfiguration(), mediaUploader: uploader)
        defer { editor.stopMediaHandling() }
        try await loadBlankPage(in: editor)

        // Larger than two chunks, so the offsets and the final short chunk are exercised.
        let size = 9 * 1024 * 1024 + 123
        let result = try await runUpload(in: editor, size: size)

        #expect(result["status"] as? Int == 201)
        let received = try #require(uploader.receivedContents)
        #expect(received.count == size)
        #expect(received == Self.pattern(count: size), "the file was reassembled out of order or short")
        #expect(uploader.received?.filename == "clip.bin")
        #expect(uploader.received?.fields == [MediaUploadField(name: "post", value: "7")])
        #expect(uploader.received?.query == "?_embed")
    }

    @MainActor
    @Test("the page can read the attachment ID off a failed upload, so core can recover it")
    func attachmentIDIsExposedToThePage() async throws {
        let session = RelayingURLSession(statusCode: 500, headers: ["x-wp-upload-attachment-id": "42"])
        let editor = EditorViewController(
            configuration: makeConfiguration(),
            mediaProcessor: StandaloneProcessor(),
            httpClient: EditorHTTPClient(urlSession: session, authHeader: "Bearer test-token")
        )
        defer { editor.stopMediaHandling() }
        try await loadBlankPage(in: editor)

        let result = try await runUpload(in: editor, size: 16)

        #expect(result["status"] as? Int == 500)
        #expect(result["attachmentId"] as? String == "42")
        #expect(session.requestCount == 1)
    }

    @MainActor
    @Test("the page finishes a file native code registered, without sending its bytes")
    func pageFinishesRegisteredFiles() async throws {
        let uploader = RecordingUploader()
        let editor = EditorViewController(configuration: makeConfiguration(), mediaUploader: uploader)
        defer { editor.stopMediaHandling() }
        try await loadBlankPage(in: editor)
        let url = try makeTemporaryFile(Data("imported video".utf8), named: "IMG_0001.MOV")
        let id = try #require(await editor.mediaUploadSchemeHandler.register(
            MediaUploadFile(url: url, mimeType: "video/quicktime", filename: "IMG_0001.MOV")
        ))

        let result = try #require(try await editor.webView.callAsyncJavaScript(
            """
            const response = await fetch(`gbk-upload://upload/sessions/${id}/finish`, {
                method: 'POST',
                body: JSON.stringify({ fields: [], query: '' }),
            });
            return { status: response.status };
            """,
            arguments: ["id": id],
            in: nil,
            contentWorld: .page
        ) as? [String: Any])

        #expect(result["status"] as? Int == 201)
        #expect(uploader.receivedContents == Data("imported video".utf8))
    }

    @MainActor
    @Test("after stopMediaHandling the page is told to upload through the web view")
    func stoppedEditorAnswers503() async throws {
        let editor = EditorViewController(configuration: makeConfiguration(), mediaUploader: InertUploader())
        try await loadBlankPage(in: editor)
        editor.stopMediaHandling()

        let result = try await runUpload(in: editor, size: 16)

        #expect(result["beginStatus"] as? Int == 503)
    }

    /// Loads an empty `file://` page — the editor's own origin — into the editor's web view.
    @MainActor
    private func loadBlankPage(in editor: EditorViewController) async throws {
        let directory = URL.randomTemporaryDirectory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let page = directory.appending(component: "index.html")
        try Data("<!doctype html><title>upload test</title>".utf8).write(to: page)
        editor.webView.loadFileURL(page, allowingReadAccessTo: directory)
        for _ in 0..<500 {
            if !editor.webView.isLoading,
               (try? await editor.webView.evaluateJavaScript("document.readyState")) as? String == "complete" {
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("the test page never finished loading")
    }

    /// Runs the page side of the upload protocol, as `nativeMediaUploadMiddleware` does.
    @MainActor
    private func runUpload(in editor: EditorViewController, size: Int) async throws -> [String: Any] {
        let result = try await editor.webView.callAsyncJavaScript(
            """
            const base = 'gbk-upload://upload';
            const bytes = new Uint8Array(size);
            for (let i = 0; i < size; i++) bytes[i] = i % 251;
            const file = new File([bytes], 'clip.bin', { type: 'application/octet-stream' });
            const begin = await fetch(`${base}/sessions`, {
                method: 'POST',
                body: JSON.stringify({ filename: file.name, mimeType: file.type, size: file.size }),
            });
            if (!begin.ok) return { beginStatus: begin.status };
            const { id } = await begin.json();
            const chunkSize = 4 * 1024 * 1024;
            for (let offset = 0; offset < file.size; offset += chunkSize) {
                const chunk = await file.slice(offset, offset + chunkSize).arrayBuffer();
                const response = await fetch(`${base}/sessions/${id}/chunks?offset=${offset}`, { method: 'POST', body: chunk });
                if (!response.ok) return { chunkStatus: response.status, offset };
            }
            const finish = await fetch(`${base}/sessions/${id}/finish`, {
                method: 'POST',
                body: JSON.stringify({ fields: [{ name: 'post', value: '7' }], query: '?_embed' }),
            });
            return {
                status: finish.status,
                attachmentId: finish.headers.get('x-wp-upload-attachment-id'),
            };
            """,
            arguments: ["size": size],
            in: nil,
            contentWorld: .page
        )
        return try #require(result as? [String: Any])
    }

    private static func pattern(count: Int) -> Data {
        Data((0..<count).map { UInt8($0 % 251) })
    }

    /// Polls instead of asserting outright, because a `UIViewController` can sit in an
    /// autorelease pool past the end of the scope that held it. Asserting synchronously
    /// passes in isolation and fails in a full suite, where other tests keep the main
    /// actor busy and the pool drains later. A real leak still fails this, a second later.
    @MainActor
    private func waitForRelease(_ isReleased: () -> Bool) async {
        for _ in 0..<100 where !isReleased() {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }
}

/// The shape that cycles: owns the editor *and* is its processor. Hosts reach for this
/// because the coordinator driving the editor already has the site context.
@MainActor
private final class EditorOwningProcessor: MediaProcessor {
    /// Implicitly unwrapped so `self` can be passed as the editor's processor: every stored
    /// property then has a value (nil) on entry to `init`, which is what makes `self`
    /// available there. Taking the processor at `init` doesn't prevent this shape — it just
    /// moves where the host writes it.
    private(set) var editor: EditorViewController!

    init(configuration: EditorConfiguration) {
        editor = EditorViewController(configuration: configuration, mediaProcessor: self)
    }

    nonisolated func handlesFile(ofType mimeType: String, named filename: String) -> Bool { false }

    nonisolated func processFile(at url: URL, mimeType: String, filename: String) async throws -> ProcessedProxyFile {
        .original
    }
}

private final class StandaloneProcessor: MediaProcessor {
    func handlesFile(ofType mimeType: String, named filename: String) -> Bool { false }

    func processFile(at url: URL, mimeType: String, filename: String) async throws -> ProcessedProxyFile {
        .original
    }
}

#endif

/// Supplied only to enable native uploads; never invoked by these tests.
private struct InertUploader: MediaUploader {
    func upload(_ upload: MediaUpload) async throws -> Data { Data() }
}

/// Answers every request with a canned status and headers, draining the body first as
/// URLSession would.
private final class RelayingURLSession: URLSessionProtocol, @unchecked Sendable {
    private let statusCode: Int
    private let headers: [String: String]
    private let lock = NSLock()
    private var count = 0

    var requestCount: Int { lock.withLock { count } }

    init(statusCode: Int, headers: [String: String]) {
        self.statusCode = statusCode
        self.headers = headers
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        if let stream = request.httpBodyStream {
            _ = readAllFromStream(stream)
        }
        lock.withLock { count += 1 }
        let response = HTTPURLResponse(url: request.url!, statusCode: statusCode, httpVersion: "HTTP/1.1", headerFields: headers)!
        return (Data(#"{"code":"rest_upload_sideload_error"}"#.utf8), response)
    }

    func download(for request: URLRequest, delegate: (any URLSessionTaskDelegate)?) async throws -> (URL, URLResponse) {
        throw URLError(.unsupportedURL)
    }
}
