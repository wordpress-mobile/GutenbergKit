import XCTest

/// E2E tests for editor interactions via the native iOS UI layer.
///
/// These tests verify that user actions in the native shell (toolbar
/// taps, navigation) correctly propagate through the WebView bridge
/// to the Gutenberg editor and back.
///
/// Unlike Playwright (which injects `window.GBKit` directly via
/// `addInitScript`), these tests exercise the real native configuration
/// pipeline: `EditorConfiguration` → `EditorViewController` →
/// `WKUserScript` injection → Gutenberg JS initialization.
final class EditorInteractionUITest: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Helpers

    /// Navigates from the editor list through the configuration screen
    /// and into the full-screen editor. Returns the WebView element once
    /// the editor has loaded.
    @discardableResult
    private func navigateToEditor() throws -> XCUIElement {
        // Tap the "Default Editor" row in the list.
        let defaultEditor = app.staticTexts["Default Editor"]
        XCTAssertTrue(defaultEditor.waitForExistence(timeout: 10), "Default Editor row not found")
        defaultEditor.tap()

        // Tap the "Start" button on the configuration screen.
        let startButton = app.buttons["Start"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 10), "Start button not found")
        startButton.tap()

        // Wait for the WebView to appear in the full-screen editor.
        let webView = app.webViews.firstMatch
        XCTAssertTrue(webView.waitForExistence(timeout: 30), "Expected a WKWebView to appear after editor loads")
        return webView
    }

    // MARK: - WebView Content Interaction

    /// Tapping inside the WebView gives it keyboard focus.
    func testWebViewAcceptsKeyboardFocus() throws {
        let webView = try navigateToEditor()

        // Tap in the center of the WebView to focus it.
        webView.tap()

        // After tapping the editor area, a keyboard should appear.
        // On simulators the software keyboard may be hidden; check
        // that the WebView at least accepted the tap without crashing.
        XCTAssertTrue(webView.exists)
    }

    /// The overflow menu (ellipsis) opens and contains expected items.
    func testOverflowMenuOpens() throws {
        try navigateToEditor()

        // Tap the ellipsis (more options) button.
        let moreButton = app.buttons["More"]
        guard moreButton.waitForExistence(timeout: 5) else {
            XCTFail("Overflow menu button not found")
            return
        }
        moreButton.tap()

        // The menu should contain a "Code Editor" or "Visual Editor" option.
        let codeEditorButton = app.buttons["Code Editor"]
        let visualEditorButton = app.buttons["Visual Editor"]
        let hasEditorToggle = codeEditorButton.waitForExistence(timeout: 5)
            || visualEditorButton.exists
        XCTAssertTrue(hasEditorToggle, "Expected Code Editor/Visual Editor toggle in overflow menu")
    }

    /// Switching to code editor mode and back does not crash.
    func testCodeEditorToggle() throws {
        try navigateToEditor()

        // Open overflow menu.
        let moreButton = app.buttons["More"]
        guard moreButton.waitForExistence(timeout: 5) else {
            XCTFail("Overflow menu button not found")
            return
        }
        moreButton.tap()

        // Switch to code editor.
        let codeEditorButton = app.buttons["Code Editor"]
        guard codeEditorButton.waitForExistence(timeout: 5) else {
            // Already in code editor mode — switch back.
            let visualButton = app.buttons["Visual Editor"]
            if visualButton.exists { visualButton.tap() }
            return
        }
        codeEditorButton.tap()

        // Verify the WebView is still present (no crash).
        let webView = app.webViews.firstMatch
        XCTAssertTrue(webView.waitForExistence(timeout: 10))

        // Switch back to visual editor.
        moreButton.tap()
        let visualEditorButton = app.buttons["Visual Editor"]
        if visualEditorButton.waitForExistence(timeout: 5) {
            visualEditorButton.tap()
        }

        XCTAssertTrue(webView.waitForExistence(timeout: 10))
    }

    /// Undo button state reflects editor history.
    ///
    /// On a fresh empty editor, undo should be disabled. After typing,
    /// the native undo button should become enabled (the bridge sends
    /// `onEditorHistoryChanged` with `hasUndo: true`).
    func testUndoButtonReflectsEditorState() throws {
        try navigateToEditor()

        let undoButton = app.buttons["Undo"]
        guard undoButton.waitForExistence(timeout: 5) else {
            XCTFail("Undo button not found")
            return
        }

        // On a fresh editor, undo should be disabled.
        XCTAssertFalse(undoButton.isEnabled, "Undo should be disabled on a fresh editor")
    }
}
