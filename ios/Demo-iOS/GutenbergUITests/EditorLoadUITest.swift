import XCTest

/// E2E tests verifying that the Gutenberg editor loads correctly
/// inside the native iOS Demo app.
///
/// These tests launch the full Gutenberg Demo app via XCUIApplication
/// and interact with it through the accessibility layer. The WebView
/// content is accessed via accessibility labels exposed by WKWebView.
final class EditorLoadUITest: XCTestCase {

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

    // MARK: - Editor Loading

    /// The app launches and displays the editor list.
    func testAppLaunches() {
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
    }

    /// A WebView becomes visible after the editor finishes loading.
    func testEditorWebViewBecomesVisible() throws {
        try navigateToEditor()
    }

    /// The editor toolbar is rendered in the navigation bar.
    func testEditorToolbarExists() throws {
        try navigateToEditor()

        // The toolbar is a native-layer element above the WebView in the
        // navigation bar. Check for standard toolbar buttons.
        let undoButton = app.buttons["Undo"]
        let redoButton = app.buttons["Redo"]

        // At least one of the undo/redo buttons should exist in the toolbar.
        let toolbarExists = undoButton.exists || redoButton.exists
        XCTAssertTrue(toolbarExists, "Expected undo/redo toolbar buttons to be present")
    }

    /// The close/dismiss button is present in the navigation bar.
    func testCloseButtonExists() throws {
        try navigateToEditor()

        let closeButton = app.buttons["Close"]
        XCTAssertTrue(closeButton.exists, "Expected close (xmark) button in the toolbar")
    }
}
