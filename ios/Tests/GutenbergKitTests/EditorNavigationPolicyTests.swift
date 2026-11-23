import Foundation
import Testing
import WebKit

@testable import GutenbergKit

@Suite
struct EditorNavigationPolicyTests {

    // MARK: - Allowed Schemes

    @Test("allows the editor page's scheme (file)")
    func allowsInternalSchemes() {
        let policy = EditorNavigationPolicy()
        #expect(policy.isAllowedScheme(URL(string: "file:///path/to/index.html")!))
    }

    @Test("does not allow external or resource URL schemes")
    func doesNotAllowExternalSchemes() {
        let policy = EditorNavigationPolicy()
        let disallowedUrls = [
            "https://wordpress.com/checkout/example.wordpress.com/premium",
            "http://example.com/page",
            "//example.com/path",
            "gbk-cache-https://public-api.wordpress.com/wpcom/v2/editor-assets",
            "gbk-media-file:///Uploads/test-image.jpg"
        ]

        for urlString in disallowedUrls {
            let url = URL(string: urlString)!
            #expect(!policy.isAllowedScheme(url), "Should not allow scheme for: \(urlString)")
        }
    }

    // MARK: - Dev Server

    @Test("recognizes configured dev server URL with various paths")
    func recognizesDevServerUrl() {
        let devServerURL = URL(string: "http://localhost:5173")!
        let policy = EditorNavigationPolicy(devServerURL: devServerURL)

        let paths = ["/", "/index.html", "/assets/main.js", "/node_modules/@wordpress/block-editor"]
        for path in paths {
            let url = URL(string: "http://localhost:5173\(path)")!
            #expect(policy.isDevServerURL(url), "Should recognize dev server path: \(path)")
        }
    }

    @Test("does not recognize dev server when not configured or for other hosts")
    func doesNotRecognizeDevServerWhenNotConfiguredOrOtherHosts() {
        // Not configured
        let policyWithoutDevServer = EditorNavigationPolicy()
        let localhostUrl = URL(string: "http://localhost:5173/index.html")!
        #expect(!policyWithoutDevServer.isDevServerURL(localhostUrl))

        // Other hosts
        let devServerURL = URL(string: "http://localhost:5173")!
        let policyWithDevServer = EditorNavigationPolicy(devServerURL: devServerURL)
        let externalUrl = URL(string: "https://wordpress.com/checkout")!
        #expect(!policyWithDevServer.isDevServerURL(externalUrl))
    }

    // MARK: - Editor Origin

    @Test("recognizes the bundled editor page's origin")
    func recognizesBundledEditorOrigin() {
        let policy = EditorNavigationPolicy()
        #expect(policy.isEditorOrigin(scheme: "file", host: "", port: 0))
    }

    @Test("recognizes the dev server's origin when configured")
    func recognizesDevServerOrigin() {
        let policy = EditorNavigationPolicy(devServerURL: URL(string: "http://localhost:5173")!)
        #expect(policy.isEditorOrigin(scheme: "http", host: "localhost", port: 5173))
        #expect(!policy.isEditorOrigin(scheme: "http", host: "localhost", port: 8080))
        #expect(!policy.isEditorOrigin(scheme: "https", host: "localhost", port: 5173))
        #expect(!policy.isEditorOrigin(scheme: "http", host: "example.com", port: 5173))
    }

    @Test("recognizes the dev server's origin when its URL spells out the default port")
    func recognizesDevServerOriginWithExplicitDefaultPort() {
        let httpPolicy = EditorNavigationPolicy(devServerURL: URL(string: "http://localhost:80/")!)
        #expect(httpPolicy.isEditorOrigin(scheme: "http", host: "localhost", port: 0))
        #expect(!httpPolicy.isEditorOrigin(scheme: "http", host: "localhost", port: 8080))

        let httpsPolicy = EditorNavigationPolicy(devServerURL: URL(string: "https://example.test:443/")!)
        #expect(httpsPolicy.isEditorOrigin(scheme: "https", host: "example.test", port: 0))
        #expect(!httpsPolicy.isEditorOrigin(scheme: "http", host: "example.test", port: 0))
    }

    @Test("does not recognize other origins as the editor's")
    func doesNotRecognizeOtherOrigins() {
        let policy = EditorNavigationPolicy()
        #expect(!policy.isEditorOrigin(scheme: "gbk-cache-https", host: "example.com", port: 0))
        #expect(!policy.isEditorOrigin(scheme: "gbk-media-file", host: "", port: 0))
        #expect(!policy.isEditorOrigin(scheme: "https", host: "example.com", port: 0))
        #expect(!policy.isEditorOrigin(scheme: "http", host: "localhost", port: 5173))
        #expect(!policy.isEditorOrigin(scheme: "", host: "", port: 0))
    }

    // MARK: - Navigation Policy: Allowed Schemes Always Pass

    @Test("allows the editor page regardless of navigation type")
    func allowsInternalSchemeUrlsRegardlessOfNavigationType() {
        let policy = EditorNavigationPolicy()
        let url = URL(string: "file:///path/to/editor.html")!

        // A reload after the web content process ends arrives as `.backForward`.
        for navigationType: WKNavigationType in [.linkActivated, .other, .backForward, .reload] {
            #expect(
                policy.shouldAllowNavigation(url: url, navigationType: navigationType, isMainFrame: true),
                "Should allow \(navigationType.rawValue) navigation to the editor page"
            )
        }
    }

    // MARK: - Navigation Policy: Resource Schemes

    @Test("recognizes the editor's resource schemes")
    func recognizesResourceSchemes() {
        let policy = EditorNavigationPolicy()
        #expect(policy.isResourceScheme(URL(string: "gbk-cache-https://example.com/asset.js")!))
        #expect(policy.isResourceScheme(URL(string: "gbk-media-file:///Uploads/test-image.jpg")!))
        #expect(policy.isResourceScheme(URL(string: "gbk-rest://example.com/wp-json/wp/v2/posts")!))
        #expect(policy.isResourceScheme(URL(string: "gbk-upload://localhost/sessions")!))
        #expect(!policy.isResourceScheme(URL(string: "file:///path/to/editor.html")!))
        #expect(!policy.isResourceScheme(URL(string: "https://example.com/page")!))
    }

    @Test("blocks resource scheme URLs from replacing the editor page")
    func blocksResourceSchemesInMainFrame() {
        let policy = EditorNavigationPolicy()
        let urls = [
            "gbk-cache-https://example.com/page.html",
            "gbk-media-file:///Uploads/page.html"
        ]

        for urlString in urls {
            let url = URL(string: urlString)!
            for navigationType: WKNavigationType in [.linkActivated, .other] {
                #expect(
                    !policy.shouldAllowNavigation(url: url, navigationType: navigationType, isMainFrame: true),
                    "Should block main frame navigation to: \(urlString)"
                )
            }
            #expect(
                !policy.shouldAllowNavigation(url: url, navigationType: .other, isMainFrame: nil),
                "Should block new window navigation to: \(urlString)"
            )
            #expect(
                policy.shouldAllowNavigation(url: url, navigationType: .other, isMainFrame: false),
                "Should allow subframe navigation to: \(urlString)"
            )
        }
    }

    @Test("blocks resource scheme URLs on the dev server's host from replacing the editor page")
    func blocksResourceSchemesOnDevServerHostInMainFrame() {
        let policy = EditorNavigationPolicy(devServerURL: URL(string: "http://localhost:5173")!)
        let urls = [
            "gbk-cache-https://localhost:8888/wp-content/plugins/example/index.js",
            "gbk-rest://localhost/wp-json/wp/v2/posts",
            "gbk-upload://localhost/sessions"
        ]

        for urlString in urls {
            let url = URL(string: urlString)!
            #expect(!policy.shouldAllowNavigation(url: url, navigationType: .other, isMainFrame: true))
            #expect(!policy.shouldAllowNavigation(url: url, navigationType: .linkActivated, isMainFrame: true))
            #expect(policy.shouldAllowNavigation(url: url, navigationType: .other, isMainFrame: false))
        }
    }

    // MARK: - Navigation Policy: Subframe Navigation (Video/Embed Support)

    @Test("allows subframe navigation to external URLs (videos, embeds)")
    func allowsSubframeNavigation() {
        let policy = EditorNavigationPolicy()
        let embedUrls = [
            "https://videos.files.wordpress.com/abc123/video.mp4",
            "https://www.youtube.com/embed/dQw4w9WgXcQ",
            "https://platform.twitter.com/embed/Tweet.html",
            "https://player.vimeo.com/video/123456"
        ]

        for urlString in embedUrls {
            let url = URL(string: urlString)!
            #expect(
                policy.shouldAllowNavigation(url: url, navigationType: .other, isMainFrame: false),
                "Should allow subframe navigation to: \(urlString)"
            )
        }
    }

    // MARK: - Navigation Policy: Main Frame External Navigation (Should Open in Browser)

    @Test("blocks link clicks to external URLs in main frame")
    func blocksLinkClicksToExternalUrls() {
        let policy = EditorNavigationPolicy()
        let url = URL(string: "https://example.com/page")!

        #expect(!policy.shouldAllowNavigation(url: url, navigationType: .linkActivated, isMainFrame: true))
    }

    @Test("blocks JavaScript main frame navigation to external URLs")
    func blocksJavaScriptMainFrameNavigation() {
        let policy = EditorNavigationPolicy()
        let url = URL(string: "https://wordpress.com/checkout/example.wordpress.com/videopress")!

        // This simulates window.top.location.href = url (upsell button behavior)
        #expect(!policy.shouldAllowNavigation(url: url, navigationType: .other, isMainFrame: true))
    }

    // MARK: - Navigation Policy: Other Navigation Types

    @Test("allows reload navigation")
    func allowsReloadNavigation() {
        let policy = EditorNavigationPolicy()
        let url = URL(string: "https://example.com/editor")!

        #expect(policy.shouldAllowNavigation(url: url, navigationType: .reload, isMainFrame: true))
    }

    @Test("blocks back/forward and form navigation types")
    func blocksOtherNavigationTypes() {
        let policy = EditorNavigationPolicy()
        let url = URL(string: "https://example.com/page")!

        let blockedTypes: [WKNavigationType] = [.backForward, .formSubmitted, .formResubmitted]
        for navigationType in blockedTypes {
            #expect(
                !policy.shouldAllowNavigation(url: url, navigationType: navigationType, isMainFrame: true),
                "Should block navigation type: \(navigationType)"
            )
        }
    }

    // MARK: - Navigation Policy: Edge Cases

    @Test("blocks navigation when URL is nil")
    func blocksNavigationWithNilUrl() {
        let policy = EditorNavigationPolicy()

        // The editor should only load known content
        #expect(!policy.shouldAllowNavigation(url: nil, navigationType: .other, isMainFrame: true))
    }

    @Test("blocks external navigation when isMainFrame is nil")
    func blocksExternalNavigationWithNilMainFrame() {
        let policy = EditorNavigationPolicy()
        let url = URL(string: "https://example.com/page")!

        // When targetFrame is nil (unknown), block external navigation
        #expect(!policy.shouldAllowNavigation(url: url, navigationType: .other, isMainFrame: nil))
        #expect(!policy.shouldAllowNavigation(url: url, navigationType: .linkActivated, isMainFrame: nil))
    }

    @Test("allows dev server navigation regardless of navigation type")
    func allowsDevServerRegardlessOfType() {
        let devServerURL = URL(string: "http://localhost:5173")!
        let policy = EditorNavigationPolicy(devServerURL: devServerURL)
        let url = URL(string: "http://localhost:5173/hot-update.js")!

        #expect(policy.shouldAllowNavigation(url: url, navigationType: .linkActivated, isMainFrame: true))
        #expect(policy.shouldAllowNavigation(url: url, navigationType: .other, isMainFrame: true))
    }

    @Test("blocks protocol-relative URLs in main frame")
    func blocksProtocolRelativeUrls() {
        let policy = EditorNavigationPolicy()
        // Protocol-relative URLs have a nil scheme, which should not be allowed
        let url = URL(string: "//example.com/path")!

        #expect(!policy.shouldAllowNavigation(url: url, navigationType: .linkActivated, isMainFrame: true))
        #expect(!policy.shouldAllowNavigation(url: url, navigationType: .other, isMainFrame: true))
    }
}
