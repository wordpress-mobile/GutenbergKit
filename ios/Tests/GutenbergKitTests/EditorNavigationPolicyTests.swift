import Foundation
import Testing
import WebKit

@testable import GutenbergKit

@Suite
struct EditorNavigationPolicyTests {

    // MARK: - Allowed Schemes

    @Test("allows internal URL schemes (file, gbk-cache-https, gbk-media-file)")
    func allowsInternalSchemes() {
        let policy = EditorNavigationPolicy()
        let allowedUrls = [
            "file:///path/to/index.html",
            "gbk-cache-https://public-api.wordpress.com/wpcom/v2/editor-assets",
            "gbk-media-file:///Uploads/test-image.jpg"
        ]

        for urlString in allowedUrls {
            let url = URL(string: urlString)!
            #expect(policy.isAllowedScheme(url), "Should allow scheme for: \(urlString)")
        }
    }

    @Test("does not allow external URL schemes (https, http, nil)")
    func doesNotAllowExternalSchemes() {
        let policy = EditorNavigationPolicy()
        let disallowedUrls = [
            "https://wordpress.com/checkout/example.wordpress.com/premium",
            "http://example.com/page",
            "//example.com/path"
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

    // MARK: - Navigation Policy: Allowed Schemes Always Pass

    @Test("allows internal scheme URLs regardless of navigation type")
    func allowsInternalSchemeUrlsRegardlessOfNavigationType() {
        let policy = EditorNavigationPolicy()
        let urls = [
            "file:///path/to/editor.html",
            "gbk-cache-https://example.com/asset.js"
        ]

        for urlString in urls {
            let url = URL(string: urlString)!
            #expect(
                policy.shouldAllowNavigation(url: url, navigationType: .linkActivated, isMainFrame: true),
                "Should allow link click to: \(urlString)"
            )
            #expect(
                policy.shouldAllowNavigation(url: url, navigationType: .other, isMainFrame: true),
                "Should allow JS navigation to: \(urlString)"
            )
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

    @Test("allows navigation when URL is nil")
    func allowsNavigationWithNilUrl() {
        let policy = EditorNavigationPolicy()

        #expect(policy.shouldAllowNavigation(url: nil, navigationType: .other, isMainFrame: true))
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
