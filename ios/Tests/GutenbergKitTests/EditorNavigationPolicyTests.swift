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

        #expect(policy.shouldAllowNavigation(to: url))
    }

    @Test("allows gbk-cache-https:// URLs for cached remote assets")
    func allowsCacheScheme() {
        let policy = EditorNavigationPolicy()
        let url = URL(string: "gbk-cache-https://public-api.wordpress.com/wpcom/v2/editor-assets")!

        #expect(policy.shouldAllowNavigation(to: url))
    }

    @Test("allows gbk-media-file:// URLs for local media files")
    func allowsMediaFileScheme() {
        let policy = EditorNavigationPolicy()
        let url = URL(string: "gbk-media-file:///Uploads/test-image.jpg")!

        #expect(policy.shouldAllowNavigation(to: url))
    }

    // MARK: - External URLs

    @Test("blocks https:// URLs and redirects to system browser")
    func blocksHttpsUrls() {
        let policy = EditorNavigationPolicy()
        let url = URL(string: "https://wordpress.com/checkout/example.wordpress.com/premium")!

        #expect(!policy.shouldAllowNavigation(to: url))
    }

    @Test("blocks http:// URLs and redirects to system browser")
    func blocksHttpUrls() {
        let policy = EditorNavigationPolicy()
        let url = URL(string: "http://example.com/page")!

        #expect(!policy.shouldAllowNavigation(to: url))
    }

    @Test("blocks WordPress.com upgrade URLs")
    func blocksUpgradeUrls() {
        let policy = EditorNavigationPolicy()
        let upgradeUrls = [
            "https://wordpress.com/checkout/example.wordpress.com/premium",
            "https://wordpress.com/plans/example.wordpress.com",
            "https://wordpress.com/checkout/example.wordpress.com/videopress"
        ]

        for urlString in upgradeUrls {
            let url = URL(string: urlString)!
            #expect(!policy.shouldAllowNavigation(to: url), "Should block: \(urlString)")
        }
    }

    // MARK: - Dev Server

    @Test("allows navigation to configured dev server URL")
    func allowsDevServerUrl() {
        let devServerURL = URL(string: "http://localhost:5173")!
        let policy = EditorNavigationPolicy(devServerURL: devServerURL)

        let url = URL(string: "http://localhost:5173/index.html")!
        #expect(policy.shouldAllowNavigation(to: url))
    }

    @Test("allows navigation to dev server with different paths")
    func allowsDevServerPaths() {
        let devServerURL = URL(string: "http://localhost:5173")!
        let policy = EditorNavigationPolicy(devServerURL: devServerURL)

        let paths = ["/", "/index.html", "/assets/main.js", "/node_modules/@wordpress/block-editor"]
        for path in paths {
            let url = URL(string: "http://localhost:5173\(path)")!
            #expect(policy.shouldAllowNavigation(to: url), "Should allow dev server path: \(path)")
        }
    }

    @Test("blocks other localhost URLs when dev server is not configured")
    func blocksLocalhostWithoutDevServer() {
        let policy = EditorNavigationPolicy()
        let url = URL(string: "http://localhost:5173/index.html")!

        #expect(!policy.shouldAllowNavigation(to: url))
    }

    @Test("blocks other hosts even when dev server is configured")
    func blocksOtherHostsWithDevServer() {
        let devServerURL = URL(string: "http://localhost:5173")!
        let policy = EditorNavigationPolicy(devServerURL: devServerURL)

        let url = URL(string: "https://wordpress.com/checkout")!
        #expect(!policy.shouldAllowNavigation(to: url))
    }

    // MARK: - Edge Cases

    @Test("handles URLs with nil scheme gracefully")
    func handlesNilScheme() {
        let policy = EditorNavigationPolicy()
        // URL without scheme - should not be allowed
        let url = URL(string: "//example.com/path")!

        #expect(!policy.shouldAllowNavigation(to: url))
    }

    @Test("allowedSchemes contains expected values")
    func allowedSchemesContainsExpectedValues() {
        #expect(EditorNavigationPolicy.allowedSchemes.contains("file"))
        #expect(EditorNavigationPolicy.allowedSchemes.contains("gbk-cache-https"))
        #expect(EditorNavigationPolicy.allowedSchemes.contains("gbk-media-file"))
        #expect(EditorNavigationPolicy.allowedSchemes.count == 3)
    }
}
