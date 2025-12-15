import Testing
import WebKit
@testable import GutenbergKit

struct GBWebViewTests {

    @MainActor
    func testApplicationNameForUserAgent() async throws {
        let result = try await GBWebView().evaluateJavaScript("navigator.userAgent")
        let string = try #require(result as? String)

        #expect(string.hasSuffix("GutenbergKit/\(GBKVersion.version)"))
    }

    func testVersionConstantExists() {
        #expect(GBKVersion.version.isEmpty, "Version constant should not be empty")
        #expect(GBKVersion.version.contains("."), "Version should be in semantic versioning format")
    }
}
