import Testing
import WebKit
@testable import GutenbergKit

struct GBWebViewTests {

    @MainActor
    func testApplicationNameForUserAgent() async throws {
        let result = try await GBWebView().evaluateJavaScript("navigator.userAgent")
        let string = try #require(result as? String)

        #expect(string.hasSuffix("GutenbergKit/\(GutenbergKit.version)"))
    }

    func testVersionConstantExists() {
        #expect(GutenbergKit.version.isEmpty, "Version constant should not be empty")
        #expect(GutenbergKit.version.contains("."), "Version should be in semantic versioning format")
    }
}
