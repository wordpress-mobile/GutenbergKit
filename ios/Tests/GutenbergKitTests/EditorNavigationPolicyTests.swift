import Foundation
import Testing
import WebKit

@testable import GutenbergKit

@Suite
struct EditorNavigationPolicyTests {

    // MARK: - Allowed Schemes

    @Test("allows file:// URLs for bundled editor resources")
    func allowsFileScheme() {
        let policy = EditorNavigationPolicy()
        let url = URL(string: "file:///path/to/index.html")!

        #expect(policy.isAllowedScheme(url))
    }

    @Test("allows gbk-cache-https:// URLs for cached remote assets")
    func allowsCacheScheme() {
        let policy = EditorNavigationPolicy()
        let url = URL(string: "gbk-cache-https://public-api.wordpress.com/wpcom/v2/editor-assets")!

        #expect(policy.isAllowedScheme(url))
    }

    @Test("allows gbk-media-file:// URLs for local media files")
    func allowsMediaFileScheme() {
        let policy = EditorNavigationPolicy()
        let url = URL(string: "gbk-media-file:///Uploads/test-image.jpg")!

        #expect(policy.isAllowedScheme(url))
    }

    @Test("allowedSchemes contains expected values")
    func allowedSchemesContainsExpectedValues() {
        #expect(EditorNavigationPolicy.allowedSchemes.contains("file"))
        #expect(EditorNavigationPolicy.allowedSchemes.contains("gbk-cache-https"))
        #expect(EditorNavigationPolicy.allowedSchemes.contains("gbk-media-file"))
        #expect(EditorNavigationPolicy.allowedSchemes.count == 3)
    }

    // MARK: - External URL Schemes

    @Test("does not allow https:// scheme")
    func doesNotAllowHttpsScheme() {
        let policy = EditorNavigationPolicy()
        let url = URL(string: "https://wordpress.com/checkout/example.wordpress.com/premium")!

        #expect(!policy.isAllowedScheme(url))
    }

    @Test("does not allow http:// scheme")
    func doesNotAllowHttpScheme() {
        let policy = EditorNavigationPolicy()
        let url = URL(string: "http://example.com/page")!

        #expect(!policy.isAllowedScheme(url))
    }

    @Test("does not allow URLs with nil scheme")
    func doesNotAllowNilScheme() {
        let policy = EditorNavigationPolicy()
        let url = URL(string: "//example.com/path")!

        #expect(!policy.isAllowedScheme(url))
    }

    // MARK: - Dev Server

    @Test("recognizes configured dev server URL")
    func recognizesDevServerUrl() {
        let devServerURL = URL(string: "http://localhost:5173")!
        let policy = EditorNavigationPolicy(devServerURL: devServerURL)

        let url = URL(string: "http://localhost:5173/index.html")!
        #expect(policy.isDevServerURL(url))
    }

    @Test("recognizes dev server with different paths")
    func recognizesDevServerPaths() {
        let devServerURL = URL(string: "http://localhost:5173")!
        let policy = EditorNavigationPolicy(devServerURL: devServerURL)

        let paths = ["/", "/index.html", "/assets/main.js", "/node_modules/@wordpress/block-editor"]
        for path in paths {
            let url = URL(string: "http://localhost:5173\(path)")!
            #expect(policy.isDevServerURL(url), "Should recognize dev server path: \(path)")
        }
    }

    @Test("does not recognize localhost when dev server is not configured")
    func doesNotRecognizeLocalhostWithoutDevServer() {
        let policy = EditorNavigationPolicy()
        let url = URL(string: "http://localhost:5173/index.html")!

        #expect(!policy.isDevServerURL(url))
    }

    @Test("does not recognize other hosts as dev server")
    func doesNotRecognizeOtherHostsAsDevServer() {
        let devServerURL = URL(string: "http://localhost:5173")!
        let policy = EditorNavigationPolicy(devServerURL: devServerURL)

        let url = URL(string: "https://wordpress.com/checkout")!
        #expect(!policy.isDevServerURL(url))
    }

    // MARK: - Navigation Policy: Allowed Schemes Always Pass

    @Test("allows file:// URLs regardless of navigation type")
    func allowsFileUrlsRegardlessOfNavigationType() {
        let policy = EditorNavigationPolicy()
        let url = URL(string: "file:///path/to/editor.html")!

        // Should allow even for link clicks or JS navigation
        #expect(policy.shouldAllowNavigation(url: url, navigationType: .linkActivated, isMainFrame: true))
        #expect(policy.shouldAllowNavigation(url: url, navigationType: .other, isMainFrame: true))
    }

    @Test("allows gbk-cache-https:// URLs regardless of navigation type")
    func allowsCacheUrlsRegardlessOfNavigationType() {
        let policy = EditorNavigationPolicy()
        let url = URL(string: "gbk-cache-https://example.com/asset.js")!

        #expect(policy.shouldAllowNavigation(url: url, navigationType: .linkActivated, isMainFrame: true))
        #expect(policy.shouldAllowNavigation(url: url, navigationType: .other, isMainFrame: true))
    }

    // MARK: - Navigation Policy: Subframe Navigation (Video/Embed Support)

    @Test("allows subframe navigation to video URLs")
    func allowsSubframeVideoNavigation() {
        let policy = EditorNavigationPolicy()
        let videoUrls = [
            "https://videos.files.wordpress.com/abc123/video.mp4",
            "https://v.wordpress.com/abc123",
            "https://videopress.com/v/abc123"
        ]

        for urlString in videoUrls {
            let url = URL(string: urlString)!
            // Subframe navigation (isMainFrame = false) should be allowed
            #expect(
                policy.shouldAllowNavigation(url: url, navigationType: .other, isMainFrame: false),
                "Should allow subframe navigation to: \(urlString)"
            )
        }
    }

    @Test("allows subframe navigation to YouTube embeds")
    func allowsSubframeYouTubeNavigation() {
        let policy = EditorNavigationPolicy()
        let url = URL(string: "https://www.youtube.com/embed/dQw4w9WgXcQ")!

        #expect(policy.shouldAllowNavigation(url: url, navigationType: .other, isMainFrame: false))
    }

    @Test("allows subframe navigation to Twitter embeds")
    func allowsSubframeTwitterNavigation() {
        let policy = EditorNavigationPolicy()
        let url = URL(string: "https://platform.twitter.com/embed/Tweet.html")!

        #expect(policy.shouldAllowNavigation(url: url, navigationType: .other, isMainFrame: false))
    }

    @Test("allows subframe navigation to Vimeo embeds")
    func allowsSubframeVimeoNavigation() {
        let policy = EditorNavigationPolicy()
        let url = URL(string: "https://player.vimeo.com/video/123456")!

        #expect(policy.shouldAllowNavigation(url: url, navigationType: .other, isMainFrame: false))
    }

    // MARK: - Navigation Policy: Link Clicks (Should Open in Browser)

    @Test("blocks link clicks to external URLs")
    func blocksLinkClicksToExternalUrls() {
        let policy = EditorNavigationPolicy()
        let url = URL(string: "https://example.com/page")!

        #expect(!policy.shouldAllowNavigation(url: url, navigationType: .linkActivated, isMainFrame: true))
    }

    @Test("blocks link clicks to WordPress.com checkout URLs")
    func blocksLinkClicksToCheckout() {
        let policy = EditorNavigationPolicy()
        let checkoutUrls = [
            "https://wordpress.com/checkout/example.wordpress.com/premium",
            "https://wordpress.com/plans/example.wordpress.com",
            "https://wordpress.com/checkout/example.wordpress.com/videopress"
        ]

        for urlString in checkoutUrls {
            let url = URL(string: urlString)!
            #expect(
                !policy.shouldAllowNavigation(url: url, navigationType: .linkActivated, isMainFrame: true),
                "Should block link click to: \(urlString)"
            )
        }
    }

    // MARK: - Navigation Policy: JavaScript Navigation (Upsell Buttons)

    @Test("blocks JavaScript main frame navigation to external URLs")
    func blocksJavaScriptMainFrameNavigation() {
        let policy = EditorNavigationPolicy()
        let url = URL(string: "https://wordpress.com/checkout/example.wordpress.com/videopress")!

        // This simulates window.top.location.href = url (upsell button behavior)
        #expect(!policy.shouldAllowNavigation(url: url, navigationType: .other, isMainFrame: true))
    }

    @Test("blocks JavaScript navigation to upgrade URLs in main frame")
    func blocksJavaScriptUpgradeNavigation() {
        let policy = EditorNavigationPolicy()
        let upgradeUrls = [
            "https://wordpress.com/checkout/example.wordpress.com/premium",
            "https://wordpress.com/plans/example.wordpress.com",
            "https://wordpress.com/checkout/example.wordpress.com/videopress"
        ]

        for urlString in upgradeUrls {
            let url = URL(string: urlString)!
            #expect(
                !policy.shouldAllowNavigation(url: url, navigationType: .other, isMainFrame: true),
                "Should block JS navigation to: \(urlString)"
            )
        }
    }

    // MARK: - Navigation Policy: Other Navigation Types (Should Allow)

    @Test("allows reload navigation")
    func allowsReloadNavigation() {
        let policy = EditorNavigationPolicy()
        let url = URL(string: "https://example.com/editor")!

        #expect(policy.shouldAllowNavigation(url: url, navigationType: .reload, isMainFrame: true))
    }

    @Test("allows back/forward navigation")
    func allowsBackForwardNavigation() {
        let policy = EditorNavigationPolicy()
        let url = URL(string: "https://example.com/editor")!

        #expect(policy.shouldAllowNavigation(url: url, navigationType: .backForward, isMainFrame: true))
    }

    @Test("allows form submitted navigation")
    func allowsFormSubmittedNavigation() {
        let policy = EditorNavigationPolicy()
        let url = URL(string: "https://example.com/form-handler")!

        #expect(policy.shouldAllowNavigation(url: url, navigationType: .formSubmitted, isMainFrame: true))
    }

    @Test("allows form resubmitted navigation")
    func allowsFormResubmittedNavigation() {
        let policy = EditorNavigationPolicy()
        let url = URL(string: "https://example.com/form-handler")!

        #expect(policy.shouldAllowNavigation(url: url, navigationType: .formResubmitted, isMainFrame: true))
    }

    // MARK: - Navigation Policy: Edge Cases

    @Test("allows navigation when URL is nil")
    func allowsNavigationWithNilUrl() {
        let policy = EditorNavigationPolicy()

        #expect(policy.shouldAllowNavigation(url: nil, navigationType: .other, isMainFrame: true))
    }

    @Test("allows navigation when isMainFrame is nil")
    func allowsNavigationWithNilMainFrame() {
        let policy = EditorNavigationPolicy()
        let url = URL(string: "https://example.com/page")!

        // When targetFrame is nil (unknown), we allow navigation except for linkActivated
        #expect(policy.shouldAllowNavigation(url: url, navigationType: .other, isMainFrame: nil))
    }

    @Test("blocks link clicks even when isMainFrame is nil")
    func blocksLinkClicksWithNilMainFrame() {
        let policy = EditorNavigationPolicy()
        let url = URL(string: "https://example.com/page")!

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
}
