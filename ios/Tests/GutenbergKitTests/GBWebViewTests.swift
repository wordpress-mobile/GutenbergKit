import XCTest
import WebKit
@testable import GutenbergKit

final class GBWebViewTests: XCTestCase {
    
    func testCreateCustomUserAgent() {
        // When
        let customUserAgent = GBWebView.createCustomUserAgent()
        
        // Then
        XCTAssertTrue(customUserAgent.contains("GutenbergKit/"), 
                     "User agent should contain GutenbergKit identifier")
        XCTAssertTrue(customUserAgent.contains("GutenbergKit/0.11.1"), 
                     "User agent should contain version number")
    }
    
    func testCustomUserAgentAppendsToDefault() {
        // Given
        let defaultWebView = WKWebView()
        let defaultUserAgent = defaultWebView.value(forKey: "userAgent") as? String ?? ""
        
        // When
        let customUserAgent = GBWebView.createCustomUserAgent()
        
        // Then
        XCTAssertTrue(customUserAgent.hasPrefix(defaultUserAgent), 
                     "Custom user agent should start with default user agent")
        XCTAssertTrue(customUserAgent.hasSuffix(" GutenbergKit/0.11.1"), 
                     "Custom user agent should end with GutenbergKit identifier")
    }
}
