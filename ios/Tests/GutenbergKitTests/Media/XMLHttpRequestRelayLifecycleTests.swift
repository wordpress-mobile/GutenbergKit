#if canImport(UIKit)
import Foundation
import Testing
import UIKit
import WebKit

@testable import GutenbergKit

/// Runs each `XMLHttpRequest` scenario in `xhr-lifecycle.js` twice in a real web
/// view: once with the browser's own `XMLHttpRequest` straight to a local server,
/// and once through the relay (`src/utils/xhr-relay.js`) and `RestRelaySchemeHandler`
/// to the same server. The caller must see the same events, in the same order, and
/// the same result.
///
/// WebKit treats a request a scheme handler answers differently from one it sends
/// itself, and the relay makes up for each difference. Only real WebKit shows
/// whether it does.
@MainActor
@Suite("XMLHttpRequest relay lifecycle", .serialized)
struct XMLHttpRequestRelayLifecycleTests {
    @Test("the caller sees what the browser's own XMLHttpRequest shows", arguments: [
        "get",
        "getJSON",
        "postString",
        "postStringWithoutUploadListener",
        "postArrayBuffer",
        "postEmptyString",
        "postEmptyArrayBuffer",
        "postBlob",
        "postFormData",
        "abortBeforeResponse",
        "abortAfterHeaders",
        "abortFromUploadProgress",
        "abortFromUploadLoad",
        "abortWhileBlobIsRead",
        "abortWhileFormDataIsRead",
        "timeoutBeforeResponse",
        "timeoutAfterHeaders",
        "unreachable",
        "cutAfterHeaders",
        "callsAfterSend",
        "callsWhileBlobIsRead",
        "callsWhileFormDataIsRead",
        "startOfBlob",
        "startOfFormData",
        "startOfEmptyBlob",
        "abortFromBlobLoadStart",
        "synchronousGet",
        "synchronousPost",
        "reopenFromSynchronousLoad",
    ])
    func matchesTheBrowser(_ scenario: String) async throws {
        let page = try await LifecyclePage.shared()

        let direct = try await page.run(scenario, relayed: false)
        let relayed = try await page.run(scenario, relayed: true)

        #expect(relayed == direct)
    }

    @Test("pre-existing relay differences", arguments: ["postUntypedBlob", "cutChunkedAfterHeaders"])
    func preExistingRelayDifferences(_ scenario: String) async throws {
        let page = try await LifecyclePage.shared()

        let direct = try await page.run(scenario, relayed: false)
        let relayed = try await page.run(scenario, relayed: true)

        withKnownIssue {
            #expect(relayed == direct)
        }
    }
}

/// A web view with the relay installed, shared by every scenario, and the server the
/// scenarios send requests to.
@MainActor
private final class LifecyclePage {
    private static var instance: LifecyclePage?

    private let server: LifecycleHTTPServer
    private let handler: RestRelaySchemeHandler
    private let window: UIWindow
    private let webView: WKWebView

    static func shared() async throws -> LifecyclePage {
        if let instance {
            return instance
        }
        let page = try await LifecyclePage()
        instance = page
        return page
    }

    private init() async throws {
        server = try await LifecycleHTTPServer()
        handler = RestRelaySchemeHandler(relay: RestRelay(
            configuration: EditorConfigurationBuilder(
                postType: .post,
                siteURL: URL(string: server.origin)!,
                siteApiRoot: URL(string: "\(server.origin)/wp-json/")!
            ).build()
        ))

        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(handler, forURLScheme: RestRelaySchemeHandler.scheme)
        webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 320, height: 480), configuration: configuration)
        // On screen, so WebKit doesn't slow the page's timers.
        window = UIWindow(frame: webView.frame)
        window.addSubview(webView)
        window.isHidden = false

        // A `file://` page, as the editor is.
        let directory = URL.temporaryDirectory.appending(component: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let page = directory.appending(component: "index.html")
        try Data("<!doctype html><title>XMLHttpRequest lifecycle</title>".utf8).write(to: page)
        webView.loadFileURL(page, allowingReadAccessTo: directory)
        try await waitUntilLoaded()

        _ = try await webView.evaluateJavaScript(try Self.relayScript() + ";true")
    }

    /// The scenario's record, as JSON.
    func run(_ scenario: String, relayed: Bool) async throws -> String {
        let result = try await webView.callAsyncJavaScript(
            try Self.scenarioScript(),
            arguments: ["scenario": scenario, "relayed": relayed, "origin": server.origin],
            in: nil,
            contentWorld: .page
        )
        return try #require(result as? String)
    }

    private func waitUntilLoaded() async throws {
        let deadline = ContinuousClock.now + .seconds(60)
        while ContinuousClock.now < deadline {
            let readyState = try? await webView.evaluateJavaScript("document.readyState")
            if !webView.isLoading && readyState as? String == "complete" {
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("The page did not load")
    }

    /// The relay's own source, which defines `window.XMLHttpRequestRelay`.
    ///
    /// Read from `src/` rather than the built editor, so the test runs the code as it
    /// is now. The modules are joined into one script, with their imports and exports
    /// taken out and the two imports from elsewhere stubbed.
    private static func relayScript() throws -> String {
        // `ios/Tests/GutenbergKitTests/Media/` holds this file.
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 {
            root.deleteLastPathComponent()
        }
        let source = root.appending(path: "src/utils")
        let modules = try ["fetch-relay.js", "xhr-relay.js"].map { name in
            let lines = try String(contentsOf: source.appending(path: name), encoding: .utf8)
                .components(separatedBy: "\n")
                .filter { !$0.hasPrefix("import ") }
                .map { $0.hasPrefix("export ") ? String($0.dropFirst("export ".count)) : $0 }
            return lines.joined(separator: "\n")
        }
        return """
        (() => {
        const restRelay = { endpoint: '\(RestRelaySchemeHandler.endpoint)' };
        const getGBKit = () => ( { restRelay } );
        const debug = () => {};
        const warn = () => {};
        \(modules.joined(separator: "\n"))
        window.XMLHttpRequestRelay = createRelayXMLHttpRequest( XMLHttpRequest, { restRelay } );
        })()
        """
    }

    private static func scenarioScript() throws -> String {
        let url = try #require(Bundle.module.url(forResource: "xhr-lifecycle", withExtension: "js"))
        return try String(contentsOf: url, encoding: .utf8)
    }
}
#endif
