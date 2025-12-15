import Foundation
import Testing
import WebKit
@testable import GutenbergKit

@Suite("GBWebView Tests")
struct GBWebViewTests {
    
    @Test("Application name for user agent is set correctly")
    func testApplicationNameForUserAgent() async throws {
        // Given
        let webView = GBWebView()
        
        // When
        webView.applicationNameForUserAgent = "GutenbergKit/\(GBKVersion.version)"
        
        // Then
        #expect(webView.applicationNameForUserAgent == "GutenbergKit/\(GBKVersion.version)")
    }
    
    @Test("Version constant exists and is valid")
    func testVersionConstantExists() async throws {
        // Then
        #expect(!GBKVersion.version.isEmpty)
        #expect(GBKVersion.version.contains("."))
    }
    
    @Test("Navigator user agent includes GutenbergKit identifier")
    func testNavigatorUserAgentIncludesGutenbergKit() async throws {
        // Given
        let webView = GBWebView()
        webView.applicationNameForUserAgent = "GutenbergKit/\(GBKVersion.version)"
        
        // Load a simple HTML page to ensure the WebView is ready
        let html = "<html><body>Test</body></html>"
        webView.loadHTMLString(html, baseURL: nil)
        
        // Wait for the page to load
        try await Task.sleep(for: .milliseconds(500))
        
        // When - evaluate navigator.userAgent in the WebView
        let userAgent = try await webView.evaluateJavaScript("navigator.userAgent") as? String
        
        // Then
        #expect(userAgent != nil)
        if let userAgent = userAgent {
            #expect(userAgent.contains("GutenbergKit/\(GBKVersion.version)"))
        }
    }
}
