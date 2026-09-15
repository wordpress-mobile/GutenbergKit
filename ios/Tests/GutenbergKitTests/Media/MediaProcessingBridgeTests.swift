import Foundation
import Testing
import WebKit

@testable import GutenbergKit

@Suite("Media Processing Bridge")
struct MediaProcessingBridgeTests {
    @Test("processes every chunk and keeps upload in JavaScript")
    func processesFileWithoutNativeUpload() async throws {
        let input = Data((0..<(MediaProcessingStore.chunkSize + 17)).map { UInt8($0 % 251) })
        let processed = Data(input.reversed())
        let delegate = RecordingProcessingDelegate(processedData: processed)
        let store = MediaProcessingStore()
        await store.configure(delegate: delegate)

        let id = UUID().uuidString
        let begin = try await store.handle(.begin(id: id, filename: "photo.jpg", mimeType: "image/jpeg", size: input.count))
        #expect(begin.accepted == true)

        let firstChunk = input.prefix(MediaProcessingStore.chunkSize)
        let secondChunk = input.dropFirst(MediaProcessingStore.chunkSize)
        _ = try await store.handle(.append(id: id, offset: 0, data: Data(firstChunk)))
        _ = try await store.handle(.append(id: id, offset: firstChunk.count, data: Data(secondChunk)))
        let reply = try await store.handle(.finish(id: id))

        #expect(await delegate.inputData == input)
        #expect(await delegate.processedMimeType == "image/jpeg")
        #expect(await delegate.processedFilename == "photo.jpg")
        #expect(await delegate.uploadCallCount == 0)
        #expect(reply.filename == "photo.webp")
        #expect(reply.mimeType == "image/webp")
        #expect(reply.size == processed.count)

        let outputURL = try #require(reply.url.flatMap(URL.init(string:)))
        let output = try await store.output(for: outputURL)
        #expect(try Data(contentsOf: output.url) == processed)
        #expect(output.filename == "photo.webp")
        #expect(output.mimeType == "image/webp")

        _ = try await store.handle(.release(id: id))
        #expect(!(await outputExists(in: store, at: outputURL)))
        #expect(!FileManager.default.fileExists(atPath: output.url.path))

        let secondID = UUID().uuidString
        _ = try await store.handle(.begin(id: secondID, filename: "second.jpg", mimeType: "image/jpeg", size: 1))
        _ = try await store.handle(.append(id: secondID, offset: 0, data: Data([1])))
        let secondReply = try await store.handle(.finish(id: secondID))
        let secondURL = try #require(secondReply.url.flatMap(URL.init(string:)))
        let secondOutput = try await store.output(for: secondURL)
        await store.removeAll()
        #expect(!(await outputExists(in: store, at: secondURL)))
        #expect(!FileManager.default.fileExists(atPath: secondOutput.url.path))
    }

    @Test("rejects incomplete and out-of-order transfers")
    func rejectsInvalidTransfers() async throws {
        let delegate = RecordingProcessingDelegate(processedData: Data("processed".utf8))
        let store = MediaProcessingStore()
        await store.configure(delegate: delegate)

        let incompleteID = UUID().uuidString
        _ = try await store.handle(.begin(id: incompleteID, filename: "clip.mov", mimeType: "video/quicktime", size: 4))
        _ = try await store.handle(.append(id: incompleteID, offset: 0, data: Data([1, 2])))
        #expect(await requestFails(in: store, .finish(id: incompleteID)))

        let outOfOrderID = UUID().uuidString
        _ = try await store.handle(.begin(id: outOfOrderID, filename: "clip.mov", mimeType: "video/quicktime", size: 4))
        #expect(await requestFails(in: store, .append(id: outOfOrderID, offset: 1, data: Data([1]))))
        #expect(await delegate.uploadCallCount == 0)

        await store.removeAll()
    }

    @Test("cancelled processing discards its eventual output")
    func cancellationCleansUpAfterProcessorReturns() async throws {
        let delegate = SuspendedProcessingDelegate()
        let store = MediaProcessingStore()
        await store.configure(delegate: delegate)

        let id = UUID().uuidString
        let input = Data("source".utf8)
        _ = try await store.handle(.begin(id: id, filename: "photo.jpg", mimeType: "image/jpeg", size: input.count))
        _ = try await store.handle(.append(id: id, offset: 0, data: input))

        let finish = Task { try await store.handle(.finish(id: id)) }
        let inputURL = await delegate.waitUntilStarted()
        #expect(FileManager.default.fileExists(atPath: inputURL.path))

        _ = try await store.handle(.cancel(id: id))
        await delegate.resume()

        do {
            _ = try await finish.value
            Issue.record("Cancelled processing unexpectedly produced output")
        } catch is CancellationError {
        } catch {
            Issue.record("Expected CancellationError, got \(error)")
        }
        #expect(!FileManager.default.fileExists(atPath: inputURL.path))
        #expect(await delegate.uploadCallCount == 0)
    }

    #if canImport(UIKit)
    @MainActor
    @Test("WKWebView reads processed bytes as an XMLHttpRequest Blob")
    func webViewReadsCustomSchemeAsBlob() async throws {
        let expected = Data([0, 1, 2, 127, 128, 254, 255])
        let delegate = RecordingProcessingDelegate(processedData: expected)
        let bridge = MediaProcessingBridge()
        await bridge.store.configure(delegate: delegate)

        let id = UUID().uuidString
        _ = try await bridge.store.handle(.begin(id: id, filename: "photo.jpg", mimeType: "image/jpeg", size: 1))
        _ = try await bridge.store.handle(.append(id: id, offset: 0, data: Data([42])))
        let reply = try await bridge.store.handle(.finish(id: id))
        let url = try #require(reply.url)

        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(bridge, forURLScheme: MediaProcessingBridge.scheme)
        let webView = WKWebView(frame: .zero, configuration: configuration)
        let navigation = NavigationWaiter()
        webView.navigationDelegate = navigation
        try await navigation.loadHTML("<html><body>media bridge</body></html>", in: webView)

        let result = try await webView.callAsyncJavaScript(
            """
            return await new Promise((resolve, reject) => {
                const request = new XMLHttpRequest();
                request.open('GET', url);
                request.responseType = 'blob';
                request.onload = async () => {
                    try {
                        const bytes = Array.from(new Uint8Array(await request.response.arrayBuffer()));
                        resolve({ bytes, type: request.response.type, status: request.status });
                    } catch (error) {
                        reject(error);
                    }
                };
                request.onerror = () => reject(new Error('XMLHttpRequest failed'));
                request.send();
            });
            """,
            arguments: ["url": url],
            in: nil,
            contentWorld: .page
        )
        let response = try #require(result as? [String: Any])
        let bytes = try #require(response["bytes"] as? [NSNumber])
        #expect(bytes.map(\.uint8Value) == Array(expected))
        #expect(response["type"] as? String == "image/webp")
        #expect(response["status"] as? Int == 200)

        _ = try await bridge.store.handle(.release(id: id))
    }
    #endif
}

private extension MediaProcessingStore.Request {
    static func begin(id: String, filename: String, mimeType: String, size: Int) -> Self {
        .init(action: "begin", id: id, filename: filename, mimeType: mimeType, size: size)
    }

    static func append(id: String, offset: Int, data: Data) -> Self {
        .init(action: "append", id: id, offset: offset, data: data.base64EncodedString())
    }

    static func finish(id: String) -> Self {
        .init(action: "finish", id: id)
    }

    static func release(id: String) -> Self {
        .init(action: "release", id: id)
    }

    static func cancel(id: String) -> Self {
        .init(action: "cancel", id: id)
    }
}

private func requestFails(in store: MediaProcessingStore, _ request: MediaProcessingStore.Request) async -> Bool {
    do {
        _ = try await store.handle(request)
        return false
    } catch {
        return true
    }
}

private func outputExists(in store: MediaProcessingStore, at url: URL) async -> Bool {
    do {
        _ = try await store.output(for: url)
        return true
    } catch {
        return false
    }
}

private actor RecordingProcessingDelegate: MediaUploadDelegate {
    private(set) var inputData: Data?
    private(set) var processedMimeType: String?
    private(set) var processedFilename: String?
    private(set) var uploadCallCount = 0
    private let processedData: Data

    init(processedData: Data) {
        self.processedData = processedData
    }

    func processFile(at url: URL, mimeType: String, filename: String) async throws -> ProcessedProxyFile {
        inputData = try Data(contentsOf: url)
        processedMimeType = mimeType
        processedFilename = filename
        let output = url.deletingLastPathComponent().appendingPathComponent("delegate-output")
        try processedData.write(to: output)
        return .processed(output, mimeType: "image/webp", filename: "photo.webp")
    }

    func uploadFile(at url: URL, mimeType: String, filename: String) async throws -> MediaUploadResponse? {
        uploadCallCount += 1
        return nil
    }
}

private actor SuspendedProcessingDelegate: MediaUploadDelegate {
    private var processContinuation: CheckedContinuation<Void, Never>?
    private var startContinuations: [CheckedContinuation<URL, Never>] = []
    private var inputURL: URL?
    private(set) var uploadCallCount = 0

    func processFile(at url: URL, mimeType: String, filename: String) async throws -> ProcessedProxyFile {
        inputURL = url
        startContinuations.forEach { $0.resume(returning: url) }
        startContinuations.removeAll()
        await withCheckedContinuation { processContinuation = $0 }
        return .original
    }

    func uploadFile(at url: URL, mimeType: String, filename: String) async throws -> MediaUploadResponse? {
        uploadCallCount += 1
        return nil
    }

    func waitUntilStarted() async -> URL {
        if let inputURL {
            return inputURL
        }
        return await withCheckedContinuation { startContinuations.append($0) }
    }

    func resume() {
        processContinuation?.resume()
        processContinuation = nil
    }
}

#if canImport(UIKit)
@MainActor
private final class NavigationWaiter: NSObject, WKNavigationDelegate {
    private var continuation: CheckedContinuation<Void, Error>?

    func loadHTML(_ html: String, in webView: WKWebView) async throws {
        try await withCheckedThrowingContinuation {
            continuation = $0
            webView.loadHTMLString(html, baseURL: nil)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation?) {
        continuation?.resume()
        continuation = nil
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation?, withError error: any Error) {
        continuation?.resume(throwing: error)
        continuation = nil
    }
}
#endif
