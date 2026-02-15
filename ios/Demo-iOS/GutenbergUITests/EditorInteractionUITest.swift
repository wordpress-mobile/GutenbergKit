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

    // MARK: - Editor History

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

    /// Typing in the editor enables undo; tapping undo enables redo.
    ///
    /// Exercises the full bridge round-trip:
    /// 1. Type text → Gutenberg JS sends `onEditorHistoryChanged` with `hasUndo: true`
    /// 2. Tap Undo  → native calls `undo()` on EditorViewController
    /// 3. Gutenberg JS sends `onEditorHistoryChanged` with `hasRedo: true`
    func testUndoRedoAfterTyping() throws {
        let webView = try navigateToEditor()

        let undoButton = app.buttons["Undo"]
        let redoButton = app.buttons["Redo"]
        guard undoButton.waitForExistence(timeout: 5),
              redoButton.waitForExistence(timeout: 5) else {
            XCTFail("Undo/Redo buttons not found")
            return
        }

        // Precondition: both buttons are disabled on a fresh editor.
        XCTAssertFalse(undoButton.isEnabled, "Undo should be disabled before typing")
        XCTAssertFalse(redoButton.isEnabled, "Redo should be disabled before typing")

        // Tap the title field inside the WebView to gain keyboard focus,
        // then type some text.
        let titleField = webView.textViews["Add title"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 10), "Title field not found in WebView")
        titleField.tap()
        titleField.typeText("Hello")

        // After typing, the bridge should report undo history available.
        let undoEnabled = undoButton.waitForEnabled(timeout: 10)
        XCTAssertTrue(undoEnabled, "Undo should be enabled after typing")

        // Tap undo — the bridge should now report redo history available.
        undoButton.tap()

        let redoEnabled = redoButton.waitForEnabled(timeout: 10)
        XCTAssertTrue(redoEnabled, "Redo should be enabled after undoing")
    }
}

extension XCUIElement {
    /// Polls until `isEnabled` becomes `true` or the timeout expires.
    func waitForEnabled(timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "isEnabled == true")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: self)
        let result = XCTWaiter.wait(for: [expectation], timeout: timeout)
        return result == .completed
    }
}
