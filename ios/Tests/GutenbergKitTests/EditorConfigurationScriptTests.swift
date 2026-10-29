import Foundation
import Testing

@testable import GutenbergKit

#if canImport(UIKit)

@Suite("Editor configuration script")
struct EditorConfigurationScriptTests {

    @MainActor
    @Test("injects the configuration without persisting it")
    func doesNotPersistTheConfiguration() {
        // The injected configuration carries the site credential.
        let script = EditorViewController.configurationScript(
            gbkitGlobal: #"{"authHeader":"Bearer secret"}"#
        )

        #expect(script.contains(#"window.GBKit = {"authHeader":"Bearer secret"};"#))
        #expect(script.contains("localStorage.removeItem('GBKit')"))
        #expect(!script.contains("localStorage.setItem"))
    }
}

#endif
