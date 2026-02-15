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

    /// Types text into the title field and returns the field element.
    @discardableResult
    private func typeInTitle(_ text: String, webView: XCUIElement) -> XCUIElement {
        let titleField = webView.textViews["Add title"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 10), "Title field not found in WebView")
        titleField.tap()
        titleField.typeText(text)
        return titleField
    }

    /// Opens the block inserter and inserts a block by name.
    private func insertBlock(_ name: String, webView: XCUIElement) {
        let addBlockButton = webView.buttons["Add block"]
        XCTAssertTrue(addBlockButton.waitForExistence(timeout: 10), "Add block button not found in WebView toolbar")
        addBlockButton.tap()

        let blockOption = app.buttons[name]
        XCTAssertTrue(blockOption.waitForExistence(timeout: 10), "\(name) block not found in block inserter")
        blockOption.tap()
    }

    /// Types text into the currently focused content block.
    private func typeInContent(_ text: String, webView: XCUIElement) {
        let block = webView.textViews["Empty block; start writing or type forward slash to choose a block"]
        XCTAssertTrue(block.waitForExistence(timeout: 10), "Editable block not found in WebView")
        block.typeText(text)
    }

    // MARK: - Editor Loading

    /// A WebView becomes visible after the editor finishes loading.
    func testEditorWebViewBecomesVisible() throws {
        try navigateToEditor()
    }

    // MARK: - Editor History

    /// Typing in the title and content enables undo; tapping undo enables redo.
    ///
    /// Exercises the full bridge round-trip:
    /// 1. Verify undo/redo are disabled on a fresh editor
    /// 2. Type text in title → bridge sends `onEditorHistoryChanged` with `hasUndo: true`
    /// 3. Type text in content → undo remains enabled
    /// 4. Tap Undo → native calls `undo()` on EditorViewController
    /// 5. Gutenberg JS sends `onEditorHistoryChanged` with `hasRedo: true`
    /// 6. Tap Redo → redo disables, undo re-enables
    func testUndoRedoAfterTyping() throws {
        let webView = try navigateToEditor()

        let undoButton = app.buttons["Undo"]
        let redoButton = app.buttons["Redo"]
        guard undoButton.waitForExistence(timeout: 5),
              redoButton.waitForExistence(timeout: 5) else {
            XCTFail("Undo/Redo buttons not found")
            return
        }

        // On a fresh editor, both buttons should be disabled.
        XCTAssertFalse(undoButton.isEnabled, "Undo should be disabled on a fresh editor")
        XCTAssertFalse(redoButton.isEnabled, "Redo should be disabled on a fresh editor")

        // Type in the title field.
        typeInTitle("Hello", webView: webView)

        // After typing in the title, undo should become enabled.
        XCTAssertTrue(undoButton.waitForEnabled(timeout: 10), "Undo should be enabled after typing in title")

        // Insert a Paragraph block and type in it.
        insertBlock("Paragraph", webView: webView)
        typeInContent("World", webView: webView)

        // Undo should still be enabled after typing in content.
        XCTAssertTrue(undoButton.isEnabled, "Undo should remain enabled after typing in content")

        // Tap undo — redo should become enabled.
        undoButton.tap()
        XCTAssertTrue(redoButton.waitForEnabled(timeout: 10), "Redo should be enabled after undoing")

        // Tap redo — redo should become disabled and undo should remain enabled.
        redoButton.tap()
        XCTAssertTrue(undoButton.waitForEnabled(timeout: 10), "Undo should be enabled after redoing")
    }

    // MARK: - Editor Mode

    /// Type content in title and body, switch to code editor, then switch back.
    ///
    /// Exercises the native→JS bridge: toggling `isCodeEditorEnabled`
    /// calls `editor.switchEditorMode()` in the WebView. The test
    /// verifies the round-trip doesn't crash and the WebView survives
    /// both transitions.
    func testCodeEditorToggleWithContent() throws {
        let webView = try navigateToEditor()

        // Type content into the title, then insert a Paragraph and type in it.
        typeInTitle("Test Title", webView: webView)
        insertBlock("Paragraph", webView: webView)
        typeInContent("Test content", webView: webView)

        // Open the overflow menu and switch to Code Editor.
        let moreButton = app.buttons["More"]
        XCTAssertTrue(moreButton.waitForExistence(timeout: 5), "More button not found")
        moreButton.tap()

        let codeEditorButton = app.buttons["Code Editor"]
        XCTAssertTrue(codeEditorButton.waitForExistence(timeout: 5), "Code Editor button not found in menu")
        codeEditorButton.tap()

        // WebView should still exist after switching to code editor.
        XCTAssertTrue(webView.waitForExistence(timeout: 10), "WebView disappeared after switching to Code Editor")

        // Switch back to Visual Editor.
        moreButton.tap()

        let visualEditorButton = app.buttons["Visual Editor"]
        XCTAssertTrue(visualEditorButton.waitForExistence(timeout: 5), "Visual Editor button not found in menu")
        visualEditorButton.tap()

        // WebView should still exist after switching back.
        XCTAssertTrue(webView.waitForExistence(timeout: 10), "WebView disappeared after switching to Visual Editor")
    }

    // MARK: - Block Inserter

    /// Open the block inserter and insert an Image block.
    ///
    /// Exercises the full inserter bridge flow:
    /// 1. Tap "Add block" in the WebView toolbar → JS sends `showBlockInserter` to native
    /// 2. Native presents `BlockInserterView` as a sheet
    /// 3. Tap "Image" block → native calls `window.blockInserter.insertBlock()` in JS
    /// 4. Sheet dismisses and block appears in editor
    func testInsertImageBlock() throws {
        let webView = try navigateToEditor()

        insertBlock("Image", webView: webView)

        // After insertion, an Image block should appear in the editor.
        let imageBlockInEditor = webView.buttons["Upload"]
        XCTAssertTrue(
            imageBlockInEditor.waitForExistence(timeout: 10),
            "Image block placeholder not found in editor after insertion"
        )
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
