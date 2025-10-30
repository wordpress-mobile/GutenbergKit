import SwiftUI
import WebKit

/// A view that renders block HTML content in a WKWebView for pattern previews
struct BlockPreviewView: UIViewRepresentable {
    let html: String
    let viewportWidth: Int

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.suppressesIncrementalRendering = true

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.isOpaque = false
        webView.backgroundColor = .white

        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        let fullHTML = generateFullHTML(content: html, viewportWidth: viewportWidth)
        webView.loadHTMLString(fullHTML, baseURL: nil)
    }

    /// Generates a complete HTML document with proper styling for block preview
    private func generateFullHTML(content: String, viewportWidth: Int) -> String {
        return """
        <!DOCTYPE html>
        <html>
        <head>
            <meta name="viewport" content="width=\(viewportWidth), initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
            <style>
                * {
                    box-sizing: border-box;
                }

                html, body {
                    margin: 0;
                    padding: 16px;
                    background: white;
                    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Oxygen-Sans, Ubuntu, Cantarell, "Helvetica Neue", sans-serif;
                    font-size: 16px;
                    line-height: 1.5;
                    color: #1e1e1e;
                    overflow-x: hidden;
                }

                body {
                    width: \(viewportWidth)px;
                }

                /* WordPress block styles */
                .wp-block-image img {
                    max-width: 100%;
                    height: auto;
                }

                .wp-block-image {
                    margin: 0 0 1em 0;
                }

                .wp-block-heading,
                h1, h2, h3, h4, h5, h6 {
                    font-weight: 600;
                    margin: 0.67em 0;
                    line-height: 1.3;
                }

                .wp-block-paragraph,
                p {
                    margin: 0 0 1em 0;
                }

                .wp-block-quote {
                    margin: 1em 0;
                    padding-left: 1em;
                    border-left: 4px solid #e0e0e0;
                }

                .wp-block-list,
                ul, ol {
                    margin: 0 0 1em 0;
                    padding-left: 1.5em;
                }

                .wp-block-button {
                    margin: 0.5em 0;
                }

                .wp-block-button__link {
                    background-color: #007cba;
                    border: none;
                    border-radius: 4px;
                    color: white;
                    padding: 0.5em 1em;
                    text-decoration: none;
                    display: inline-block;
                }

                .wp-block-columns {
                    display: flex;
                    gap: 2em;
                    margin: 1em 0;
                }

                .wp-block-column {
                    flex: 1;
                }

                .wp-block-group {
                    margin: 1em 0;
                }

                /* Hide elements that don't render well in preview */
                .wp-block-embed,
                .wp-block-video,
                .wp-block-audio {
                    background: #f0f0f0;
                    padding: 2em;
                    text-align: center;
                    color: #666;
                }

                /* Ensure images load properly */
                img {
                    max-width: 100%;
                    height: auto;
                    display: block;
                }

                /* Figcaption styling */
                figcaption {
                    font-size: 0.875em;
                    color: #666;
                    margin-top: 0.5em;
                }

                /* Cover block */
                .wp-block-cover {
                    min-height: 200px;
                    display: flex;
                    align-items: center;
                    justify-content: center;
                    padding: 1em;
                    background: #f0f0f0;
                }
            </style>
        </head>
        <body>
            \(content)
        </body>
        </html>
        """
    }
}

#if DEBUG
#Preview {
    BlockPreviewView(
        html: "<p>Hello World</p>",
        viewportWidth: 800
    )
    .frame(height: 120)
}
#endif
