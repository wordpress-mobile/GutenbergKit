import XCTest
import WebKit
@testable import GutenbergKit

final class GBWebViewTests: XCTestCase {
    
    func testApplicationNameForUserAgent() {
        // Given
        let webView = GBWebView()
        
        // When
        webView.applicationNameForUserAgent = "GutenbergKit/\(GBKVersion.version)"
        
        // Then
        XCTAssertEqual(webView.applicationNameForUserAgent, "GutenbergKit/\(GBKVersion.version)",
                      "Application name should be set correctly")
    }
    
    func testVersionConstantExists() {
        // Then
        XCTAssertFalse(GBKVersion.version.isEmpty,
                      "Version constant should not be empty")
        XCTAssertTrue(GBKVersion.version.contains("."),
                     "Version should be in semantic versioning format")
    }
}
