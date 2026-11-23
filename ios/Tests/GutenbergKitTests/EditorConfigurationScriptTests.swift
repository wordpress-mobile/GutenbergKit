import Foundation
import Testing

@testable import GutenbergKit

#if canImport(UIKit)

@Suite("Editor configuration script")
struct EditorConfigurationScriptTests {

    @MainActor
    @Test("injects the configuration without persisting it")
    func doesNotPersistTheConfiguration() {
        // Builds before #613 kept a copy of the configuration in `localStorage`.
        let script = EditorViewController.configurationScript(
            gbkitGlobal: #"{"authHeader":"Bearer secret"}"#
        )

        #expect(script.contains(#"window.GBKit = {"authHeader":"Bearer secret"};"#))
        #expect(script.contains("localStorage.removeItem('GBKit')"))
        #expect(!script.contains("localStorage.setItem"))
    }
}

#endif
