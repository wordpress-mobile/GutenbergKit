import SwiftUI
import WebKit

/// A view that displays a live WKWebView preview of a block pattern, scaled to fit
struct BlockPreviewView: View {
    let pattern: PatternType

    private let previewHeight: CGFloat = 120

    @StateObject private var viewModel: BlockPreviewViewModel

    init(pattern: PatternType) {
        self.pattern = pattern
        self._viewModel = StateObject(wrappedValue: BlockPreviewViewModel(
            html: pattern.previewHTML,
            viewportWidth: pattern.viewportWidth ?? 1200
        ))
    }

    var body: some View {
        GeometryReader { geometry in
            WebViewRepresentable(viewModel: viewModel, containerWidth: geometry.size.width)
                .background(Color.white)
                .cornerRadius(8)
                .clipped()
        }
        .frame(height: previewHeight)
    }
}

// MARK: - ViewModel

@MainActor
class BlockPreviewViewModel: ObservableObject {
    let html: String
    let viewportWidth: Int

    @Published var contentHeight: CGFloat = 100
    @Published var isLoaded = false

    init(html: String, viewportWidth: Int) {
        self.html = html
        self.viewportWidth = viewportWidth
    }

    func generateFullHTML() -> String {
        return """
        <!DOCTYPE html>
        <html style="margin: 0; padding: 0;">
        <head>
            <meta name="viewport" content="width=\(viewportWidth), initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
            <style>
                * { box-sizing: border-box; }
                body {
                    margin: 0;
                    padding: 0;
                    width: \(viewportWidth)px;
                    background: white;
                }
            </style>
            <style>
                \(GutenbergCSSLoader.shared.css)
            </style>
        </head>
        <body class="block-editor-iframe__body editor-styles-wrapper wp-embed-responsive">
            \(html)
        </body>
        </html>
        """
    }
}

// MARK: - CSS Loader Singleton

@MainActor
class GutenbergCSSLoader {
    static let shared = GutenbergCSSLoader()

    /// Cached Gutenberg CSS
    let css: String

    private init() {
        self.css = Self.loadGutenbergCSS() ?? ""
    }

    /// Loads the Gutenberg CSS from the bundled assets
    private static func loadGutenbergCSS() -> String? {
        guard let assetsURL = Bundle.module.url(forResource: "Gutenberg", withExtension: nil),
              let assetsPath = try? FileManager.default.contentsOfDirectory(
                at: assetsURL.appendingPathComponent("assets"),
                includingPropertiesForKeys: nil
              ) else {
            return nil
        }

        guard let cssURL = assetsPath.first(where: { url in
            let filename = url.lastPathComponent
            return filename.hasPrefix("index-") && filename.hasSuffix(".css")
        }) else {
            return nil
        }

        return try? String(contentsOf: cssURL, encoding: .utf8)
    }
}

// MARK: - WebView Representable

struct WebViewRepresentable: UIViewRepresentable {
    @ObservedObject var viewModel: BlockPreviewViewModel
    let containerWidth: CGFloat

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.suppressesIncrementalRendering = true

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.backgroundColor = .white
        webView.isOpaque = true
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.navigationDelegate = context.coordinator

        // Load the HTML
        let html = viewModel.generateFullHTML()
        webView.loadHTMLString(html, baseURL: nil)

        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        // Calculate scale to fit
        let scale = containerWidth / CGFloat(viewModel.viewportWidth)

        // Apply transform to scale content
        webView.transform = CGAffineTransform(scaleX: scale, y: scale)

        // Adjust frame for scaled content
        let scaledHeight = viewModel.contentHeight * scale
        webView.frame = CGRect(
            x: 0,
            y: 0,
            width: CGFloat(viewModel.viewportWidth),
            height: viewModel.contentHeight
        )

        // Position the scaled webview
        webView.layer.anchorPoint = CGPoint(x: 0, y: 0)
        webView.layer.position = CGPoint(x: 0, y: 0)
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        // Stop loading when view is removed/reused
        webView.stopLoading()
        webView.navigationDelegate = nil
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        let viewModel: BlockPreviewViewModel

        init(viewModel: BlockPreviewViewModel) {
            self.viewModel = viewModel
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // Get content height
            webView.evaluateJavaScript("document.readyState") { [weak self] complete, _ in
                guard complete != nil else { return }

                webView.evaluateJavaScript("document.documentElement.scrollHeight") { height, _ in
                    guard let height = height as? CGFloat else {
                        self?.viewModel.contentHeight = 100
                        self?.viewModel.isLoaded = true
                        return
                    }

                    let maxHeight: CGFloat = 2000
                    self?.viewModel.contentHeight = min(height, maxHeight)
                    self?.viewModel.isLoaded = true
                }
            }
        }
    }
}
