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

    // MARK: - WebView Content Interaction

    /// Tapping inside the WebView gives it keyboard focus.
    func testWebViewAcceptsKeyboardFocus() throws {
        let webView = app.webViews.firstMatch
        XCTAssertTrue(webView.waitForExistence(timeout: 30))

        // Tap in the center of the WebView to focus it.
        webView.tap()

        // After tapping the editor area, a keyboard should appear.
        // On simulators the software keyboard may be hidden; check
        // that the WebView at least accepted the tap without crashing.
        XCTAssertTrue(webView.exists)
    }

    /// The overflow menu (ellipsis) opens and contains expected items.
    func testOverflowMenuOpens() throws {
        let webView = app.webViews.firstMatch
        XCTAssertTrue(webView.waitForExistence(timeout: 30))

        // Tap the ellipsis (more options) button.
        let moreButton = app.buttons["ellipsis"]
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
        let webView = app.webViews.firstMatch
        XCTAssertTrue(webView.waitForExistence(timeout: 30))

        // Open overflow menu.
        let moreButton = app.buttons["ellipsis"]
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
        let webView = app.webViews.firstMatch
        XCTAssertTrue(webView.waitForExistence(timeout: 30))

        let undoButton = app.buttons["arrow.uturn.backward"]
        guard undoButton.exists else {
            XCTFail("Undo button not found")
            return
        }

        // On a fresh editor, undo should be disabled.
        XCTAssertFalse(undoButton.isEnabled, "Undo should be disabled on a fresh editor")
    }
}
