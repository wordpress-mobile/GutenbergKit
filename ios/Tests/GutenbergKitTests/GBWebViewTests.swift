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
        XCTAssertTrue(customUserAgent.contains("Mozilla"), 
                     "User agent should contain Mozilla identifier from default user agent")
    }
    
    func testCustomUserAgentEndsWithGutenbergKitIdentifier() {
        // When
        let customUserAgent = GBWebView.createCustomUserAgent()
        
        // Then
        XCTAssertTrue(customUserAgent.hasSuffix(" GutenbergKit/0.11.1"), 
                     "Custom user agent should end with GutenbergKit identifier")
    }
    
    func testCustomUserAgentIsConsistent() {
        // Given
        let firstCall = GBWebView.createCustomUserAgent()
        
        // When
        let secondCall = GBWebView.createCustomUserAgent()
        
        // Then
        XCTAssertEqual(firstCall, secondCall, 
                      "Custom user agent should be consistent across calls")
    }
}
