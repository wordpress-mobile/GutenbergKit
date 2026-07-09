import SwiftUI
import OSLog
import WebKit
import GutenbergKit

final class Navigation: ObservableObject {
    @Published var path = NavigationPath()

    @Published var hasEditor: Bool = false

    @Published var editor: RunnableEditor?

    func push(_ path: any Hashable) {
        self.path.append(path)
    }

    func present(_ editor: RunnableEditor) {
        self.hasEditor = true
        self.editor = editor
    }
}

extension EnvironmentValues {
    private struct NavigationKey: EnvironmentKey {
        static let defaultValue = Navigation()
    }

    var navigation: Navigation {
        get { self[NavigationKey.self] }
        set { self[NavigationKey.self] = newValue }
    }
}

@main
struct GutenbergApp: App {
    @StateObject
    private var navigation = Navigation()

    // swiftlint:disable:next force_try
    // ConfigurationStorage uses SecureEnclave, which is available on all supported devices and Simulator.
    private let configurationStorage = try! ConfigurationStorage()

    init() {
        // Configure logger for GutenbergKit
        EditorLogger.shared = OSLogEditorLogger()
        EditorLogger.logLevel = .debug

        // Keep the device awake while the demo app is foregrounded — the
        // debugging workflows here (probes, Web Inspector, devicectl console)
        // break when the device auto-locks.
        UIApplication.shared.isIdleTimerDisabled = true

        OriginProbeRunner.runIfRequested()
    }

    var body: some Scene {
        WindowGroup {
            NavigationStack(path: $navigation.path) {
                AppRootView()
                .navigationDestination(for: ConfigurationItem.self) { item in
                    SitePreparationView(site: item)
                }
                .fullScreenCover(isPresented: $navigation.hasEditor) {
                    let editor = navigation.editor!

                    NavigationStack {
                        EditorView(
                            configuration: editor.configuration,
                            dependencies: editor.dependencies,
                            apiClient: editor.apiClient,
                            enableNativeMediaUpload: editor.enableNativeMediaUpload
                        )
                    }
                }
            }
        }
        .environment(\.navigation, navigation)
        .environmentObject(configurationStorage)
    }
}

/// Serves a trivial HTML page for the custom-scheme origin probe variant.
final class ProbeSchemeHandler: NSObject, WKURLSchemeHandler {
    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url else { return }
        let html = Data("<html><body>probe</body></html>".utf8)
        let response = URLResponse(url: url, mimeType: "text/html", expectedContentLength: html.count, textEncodingName: "utf-8")
        urlSchemeTask.didReceive(response)
        urlSchemeTask.didReceive(html)
        urlSchemeTask.didFinish()
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}
}

/// Debug automation: probes network capabilities from bare web views with
/// different page origins to characterize Lockdown Mode restrictions.
/// Enabled with GUTENBERG_ORIGIN_PROBE=1; results print to stdout.
@MainActor
final class OriginProbeRunner: NSObject, WKNavigationDelegate {
    static let shared = OriginProbeRunner()

    /// The CORS-instrumented echo server run on the Mac during investigation.
    private let echoBase = "http://192.168.0.57:8890"

    private var webViews: [WKWebView] = []
    private var loadContinuations: [ObjectIdentifier: CheckedContinuation<Void, Never>] = [:]

    static func runIfRequested() {
        guard ProcessInfo.processInfo.environment["GUTENBERG_ORIGIN_PROBE"] == "1" else { return }
        Task { @MainActor in
            await shared.run()
        }
    }

    private enum LoadMode {
        case file
        case htmlString(base: URL?)
        case customScheme
    }

    private func run() async {
        print("ORIGIN_PROBE_START")
        await runVariant(name: "custom_scheme", universalPrefs: false, load: .customScheme)
        await runVariant(name: "file_with_universal_prefs", universalPrefs: true, load: .file)
        print("ORIGIN_PROBE_DONE")
        webViews.removeAll()
    }

    private func runVariant(name: String, universalPrefs: Bool, load: LoadMode) async {
        let config = WKWebViewConfiguration()
        if universalPrefs {
            config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
            config.setValue(true, forKey: "allowUniversalAccessFromFileURLs")
        }
        if case .customScheme = load {
            config.setURLSchemeHandler(ProbeSchemeHandler(), forURLScheme: "gbk-probe")
        }

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isInspectable = true
        webView.navigationDelegate = self
        webViews.append(webView)

        let lockdown = config.defaultWebpagePreferences.isLockdownModeEnabled
        print("ORIGIN_PROBE_VARIANT name=\(name) lockdown=\(lockdown)")

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            loadContinuations[ObjectIdentifier(webView)] = continuation
            switch load {
            case .file:
                let dir = FileManager.default.temporaryDirectory.appendingPathComponent("origin-probe", isDirectory: true)
                let file = dir.appendingPathComponent("probe.html")
                try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                try? "<html><body>probe</body></html>".write(to: file, atomically: true, encoding: .utf8)
                webView.loadFileURL(file, allowingReadAccessTo: dir)
            case .htmlString(let base):
                webView.loadHTMLString("<html><body>probe</body></html>", baseURL: base)
            case .customScheme:
                webView.load(URLRequest(url: URL(string: "gbk-probe://probe-host/probe.html")!))
            }
        }

        do {
            let result = try await webView.callAsyncJavaScript(
                Self.probeJS,
                arguments: ["echoBase": echoBase],
                contentWorld: .page
            )
            print("ORIGIN_PROBE_RESULT name=\(name) \(result ?? "nil")")
        } catch {
            print("ORIGIN_PROBE_ERROR name=\(name) \(error)")
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let id = ObjectIdentifier(webView)
        Task { @MainActor in
            loadContinuations.removeValue(forKey: id)?.resume()
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        let id = ObjectIdentifier(webView)
        Task { @MainActor in
            loadContinuations.removeValue(forKey: id)?.resume()
        }
    }

    private static let probeJS = """
    const out = {};
    const S = e => (e && e.name ? e.name + ': ' + e.message : String(e));
    const T = () => AbortSignal.timeout(8000);
    const j = async (p) => { try { const r = await p; return r.status; } catch (e) { return 'REJECT ' + S(e); } };
    out.origin = String(location.origin);
    out.href = location.href.split('?')[0].slice(0, 90);
    out.star_get = await j(fetch(echoBase + '/star/get', {signal: T()}));
    out.star_post_text = await j(fetch(echoBase + '/star/post', {method: 'POST', body: 'x', signal: T()}));
    const fd = new FormData();
    fd.append('probe', 'x');
    out.star_post_formdata = await j(fetch(echoBase + '/star/fd', {method: 'POST', body: fd, signal: T()}));
    out.star_post_preflight = await j(fetch(echoBase + '/star/pf', {method: 'POST', headers: {'X-Probe': '1'}, body: 'x', signal: T()}));
    out.star_put = await j(fetch(echoBase + '/star/put', {method: 'PUT', body: 'x', signal: T()}));
    out.echo_post_text = await j(fetch(echoBase + '/echo/post', {method: 'POST', body: 'x', signal: T()}));
    try { const r = await fetch(echoBase + '/star/nc', {method: 'POST', mode: 'no-cors', body: 'x', signal: T()}); out.nocors_post = 'ok type=' + r.type + ' status=' + r.status; } catch (e) { out.nocors_post = 'REJECT ' + S(e); }
    out.https_get = await j(fetch('https://public-api.wordpress.com/rest/v1.1/sites/en.blog.wordpress.com', {signal: T()}));
    out.https_post = await j(fetch('https://public-api.wordpress.com/rest/v1.1/sites/en.blog.wordpress.com/posts/new', {method: 'POST', body: 'x', signal: T()}));
    try { const b = new Blob(['xy']); out.blob_arrayBuffer = 'ok len=' + (await b.arrayBuffer()).byteLength; } catch (e) { out.blob_arrayBuffer = 'FAIL ' + S(e); }
    return JSON.stringify(out, null, 1);
    """
}

struct OSLogEditorLogger: GutenbergKit.EditorLogging {
    private let logger: Logger

    init(subsystem: String = "com.gutenbergkit.demo", category: String = "GutenbergKit") {
        self.logger = Logger(subsystem: subsystem, category: category)
    }

    func log(_ level: GutenbergKit.EditorLogLevel, _ message: String) {
        switch level {
        case .debug: logger.debug("\(message)")
        case .info: logger.info("\(message)")
        case .warn: logger.warning("\(message)")
        case .error: logger.error("\(message)")
        }
    }
}
