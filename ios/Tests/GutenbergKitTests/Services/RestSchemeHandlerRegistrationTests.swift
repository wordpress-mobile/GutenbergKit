import Foundation
import Testing
import WebKit

@testable import GutenbergKit

#if canImport(UIKit)

@Suite("RestSchemeHandler Registration")
struct RestSchemeHandlerRegistrationTests: MakesTestFixtures {
    static let testSiteURL = URL(string: "https://test.example.com")!
    static let testApiRoot = URL(string: "https://test.example.com/wp-json/")!

    /// The relay exists to work around Lockdown Mode's CORS restrictions, so
    /// outside it the editor keeps talking to the site directly and the scheme
    /// is never registered. (The Lockdown case can't be exercised here: the
    /// forcing switch is an environment variable read at init, and the system
    /// setting is unavailable to tests.)
    @MainActor
    @Test("does not register the REST relay scheme outside Lockdown Mode")
    func doesNotRegisterWithoutLockdownMode() throws {
        let editorVC = EditorViewController(configuration: makeConfiguration())

        #expect(editorVC.webView.configuration.urlSchemeHandler(forURLScheme: RestRelay.scheme) == nil)
    }

    /// The authority is empty by design, so there is no host in a relay URL to
    /// be mistaken for a forwarding target — see `RestRelay.upstreamURL`.
    @Test("addresses the relay with an empty authority")
    func rootURLHasEmptyAuthority() throws {
        #expect(RestRelay.rootURL == "gbk-rest:///")

        let url = try #require(URL(string: RestRelay.rootURL + "wp/v2/posts"))
        #expect(url.scheme == RestRelay.scheme)
        #expect(url.host?.isEmpty != false)
        #expect(url.path == "/wp/v2/posts")
    }
}

#endif
