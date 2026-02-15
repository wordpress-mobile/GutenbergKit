import XCTest

/// Reusable helpers for iOS E2E tests that interact with the Gutenberg editor.
///
/// All methods are `static` so they can be called from any test file
/// without needing an instance — e.g. `EditorUITestHelpers.navigateToEditor(app:)`.
enum EditorUITestHelpers {

    /// Navigates from the editor list through the configuration screen
    /// and into the full-screen editor. Returns the WebView element once
    /// the editor has loaded.
    @discardableResult
    static func navigateToEditor(app: XCUIApplication) throws -> XCUIElement {
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
    static func typeInTitle(_ text: String, webView: XCUIElement) -> XCUIElement {
        let titleField = webView.textViews["Add title"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 10), "Title field not found in WebView")
        titleField.tap()
        titleField.typeText(text)
        return titleField
    }

    /// Opens the block inserter and inserts a block by name.
    static func insertBlock(_ name: String, webView: XCUIElement, app: XCUIApplication) {
        let addBlockButton = webView.buttons["Add block"]
        XCTAssertTrue(addBlockButton.waitForExistence(timeout: 10), "Add block button not found in WebView toolbar")
        addBlockButton.tap()

        let blockOption = app.buttons[name]
        XCTAssertTrue(blockOption.waitForExistence(timeout: 10), "\(name) block not found in block inserter")
        blockOption.tap()
    }

    /// Types text into the currently focused content block.
    static func typeInContent(_ text: String, webView: XCUIElement) {
        let block = webView.textViews["Empty block; start writing or type forward slash to choose a block"]
        XCTAssertTrue(block.waitForExistence(timeout: 10), "Editable block not found in WebView")
        block.typeText(text)
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
