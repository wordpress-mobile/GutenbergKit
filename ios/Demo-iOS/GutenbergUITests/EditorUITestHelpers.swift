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
        // Tap the "Standalone Editor" row in the list.
        let standaloneEditor = app.staticTexts["Standalone Editor"]
        XCTAssertTrue(standaloneEditor.waitForExistence(timeout: 10), "Standalone Editor row not found")
        standaloneEditor.tap()

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

        // Use firstMatch because the same block can appear in multiple
        // inserter sections (e.g. most-used and its category section).
        let blockOption = app.buttons[name].firstMatch
        XCTAssertTrue(blockOption.waitForExistence(timeout: 10), "\(name) block not found in block inserter")
        blockOption.tap()
    }

    /// Types text into the currently focused content block.
    static func typeInContent(_ text: String, webView: XCUIElement) {
        let block = webView.textViews["Empty block; start writing or type forward slash to choose a block"]
        XCTAssertTrue(block.waitForExistence(timeout: 10), "Editable block not found in WebView")
        block.typeText(text)
    }

    // MARK: - Mode Switching

    /// Switches the editor to Code Editor mode via the More menu.
    static func switchToCodeEditor(app: XCUIApplication) {
        let moreButton = app.buttons["More"]
        XCTAssertTrue(moreButton.waitForExistence(timeout: 5), "More button not found")
        moreButton.tap()

        let codeEditorButton = app.buttons["Code Editor"]
        XCTAssertTrue(codeEditorButton.waitForExistence(timeout: 5), "Code Editor button not found in menu")
        codeEditorButton.tap()
    }

    /// Switches the editor back to Visual Editor mode via the More menu.
    static func switchToVisualEditor(app: XCUIApplication) {
        let moreButton = app.buttons["More"]
        XCTAssertTrue(moreButton.waitForExistence(timeout: 5), "More button not found")
        moreButton.tap()

        let visualEditorButton = app.buttons["Visual Editor"]
        XCTAssertTrue(visualEditorButton.waitForExistence(timeout: 5), "Visual Editor button not found in menu")
        visualEditorButton.tap()
    }

    // MARK: - Content Reading (Code Editor Mode)

    /// Reads the current title from the code editor's title textarea.
    /// The editor must already be in Code Editor mode.
    static func readTitle(webView: XCUIElement) -> String? {
        let titleField = webView.textViews["Add title"]
        guard titleField.waitForExistence(timeout: 10) else {
            XCTFail("Title textarea not found in Code Editor mode")
            return nil
        }
        return titleField.value as? String
    }

    /// Reads the current raw HTML content from the code editor's content textarea.
    /// The editor must already be in Code Editor mode.
    static func readContent(webView: XCUIElement) -> String? {
        let contentField = webView.textViews["Start writing with text or HTML"]
        guard contentField.waitForExistence(timeout: 10) else {
            XCTFail("Content textarea not found in Code Editor mode")
            return nil
        }
        return contentField.value as? String
    }

    // MARK: - Content Assertion Helpers

    /// Switches to Code Editor, reads both title and content, then switches back.
    /// Returns (title, content) tuple for custom assertions.
    @discardableResult
    static func readTitleAndContent(
        webView: XCUIElement,
        app: XCUIApplication
    ) -> (title: String, content: String)? {
        switchToCodeEditor(app: app)
        let title = readTitle(webView: webView)
        let content = readContent(webView: webView)
        switchToVisualEditor(app: app)
        guard let title, let content else { return nil }
        return (title: title, content: content)
    }

    /// Switches to Code Editor, reads both title and content, then switches back.
    /// Optionally asserts the title equals `expectedTitle` and/or the content
    /// contains `expectedContentSubstring`. Uses a single mode toggle regardless
    /// of how many assertions are requested.
    @discardableResult
    static func assertContent(
        expectedTitle: String? = nil,
        expectedContentSubstring: String? = nil,
        webView: XCUIElement,
        app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> (title: String, content: String)? {
        let result = readTitleAndContent(webView: webView, app: app)
        if let expectedTitle {
            XCTAssertEqual(result?.title, expectedTitle, "Title mismatch", file: file, line: line)
        }
        if let expectedContentSubstring, let content = result?.content {
            XCTAssertTrue(
                content.contains(expectedContentSubstring),
                "Expected content to contain \"\(expectedContentSubstring)\" but got \"\(content)\"",
                file: file,
                line: line
            )
        }
        return result
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
