import Foundation
import Testing
import WebKit

@testable import GutenbergKit

#if canImport(UIKit)

@Suite("MediaFileSchemeHandler Registration")
struct MediaFileSchemeHandlerRegistrationTests: MakesTestFixtures {
    static let testSiteURL = URL(string: "https://test.example.com")!
    static let testApiRoot = URL(string: "https://test.example.com/wp-json/wp/v2")!

    @MainActor
    @Test("EditorViewController registers MediaFileSchemeHandler for gbk-media-file scheme")
    func editorViewControllerRegistersSchemeHandler() throws {
        let configuration = makeConfiguration()
        let editorVC = EditorViewController(configuration: configuration)

        let handler = editorVC.webView.configuration.urlSchemeHandler(forURLScheme: MediaFileSchemeHandler.scheme)
        #expect(handler != nil, "MediaFileSchemeHandler should be registered for \(MediaFileSchemeHandler.scheme) scheme")
    }
}

#endif
