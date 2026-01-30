import Foundation
import Testing

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

    // MARK: - External URLs

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

    @Test("does not allow WordPress.com upgrade URLs by scheme")
    func doesNotAllowUpgradeUrlSchemes() {
        let policy = EditorNavigationPolicy()
        let upgradeUrls = [
            "https://wordpress.com/checkout/example.wordpress.com/premium",
            "https://wordpress.com/plans/example.wordpress.com",
            "https://wordpress.com/checkout/example.wordpress.com/videopress"
        ]

        for urlString in upgradeUrls {
            let url = URL(string: urlString)!
            #expect(!policy.isAllowedScheme(url), "Should not allow scheme for: \(urlString)")
        }
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

    // MARK: - Edge Cases

    @Test("does not allow URLs with nil scheme")
    func doesNotAllowNilScheme() {
        let policy = EditorNavigationPolicy()
        // URL without scheme
        let url = URL(string: "//example.com/path")!

        #expect(!policy.isAllowedScheme(url))
    }

    @Test("allowedSchemes contains expected values")
    func allowedSchemesContainsExpectedValues() {
        #expect(EditorNavigationPolicy.allowedSchemes.contains("file"))
        #expect(EditorNavigationPolicy.allowedSchemes.contains("gbk-cache-https"))
        #expect(EditorNavigationPolicy.allowedSchemes.contains("gbk-media-file"))
        #expect(EditorNavigationPolicy.allowedSchemes.count == 3)
    }

    // MARK: - Video/Media URL Schemes

    @Test("does not treat video URLs as allowed scheme")
    func doesNotAllowVideoUrlScheme() {
        let policy = EditorNavigationPolicy()
        let videoUrls = [
            "https://videos.files.wordpress.com/abc123/video.mp4",
            "https://v.wordpress.com/abc123",
            "https://videopress.com/v/abc123"
        ]

        for urlString in videoUrls {
            let url = URL(string: urlString)!
            // Video URLs use https, which is not in allowedSchemes
            // They should be allowed via subframe navigation, not scheme
            #expect(!policy.isAllowedScheme(url), "Video URL should not match allowed scheme: \(urlString)")
        }
    }
}
