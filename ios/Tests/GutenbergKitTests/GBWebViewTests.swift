import Testing
import WebKit
@testable import GutenbergKit

struct GBWebViewTests {

    @MainActor
    func testApplicationNameForUserAgent() async throws {
        let result = try await GBWebView().evaluateJavaScript("navigator.userAgent")
        let string = try #require(result as? String)

        #expect(string.hasSuffix("GutenbergKit/\(GutenbergKitVersion.version)"))
    }

    func testVersionConstantExists() {
        #expect(!GutenbergKitVersion.version.isEmpty, "Version constant should not be empty")
        #expect(GutenbergKitVersion.version.contains("."), "Version should be in semantic versioning format")
    }
}
