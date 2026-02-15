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

    // MARK: - Editor Loading

    /// The app launches and displays the editor list (or an editor).
    func testAppLaunches() {
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
    }

    /// A WebView becomes visible after the editor finishes loading.
    func testEditorWebViewBecomesVisible() throws {
        // Navigate to an editor if the app starts on a list screen.
        // The bundled offline config creates a local editor that loads from
        // the asset bundle without network access.
        let webView = app.webViews.firstMatch
        let exists = webView.waitForExistence(timeout: 30)
        XCTAssertTrue(exists, "Expected a WKWebView to appear after editor loads")
    }

    /// The editor toolbar is rendered inside the WebView.
    func testEditorToolbarExists() throws {
        let webView = app.webViews.firstMatch
        XCTAssertTrue(webView.waitForExistence(timeout: 30))

        // The toolbar is a native-layer element above the WebView in the
        // navigation bar. Check for standard toolbar buttons.
        let undoButton = app.buttons["arrow.uturn.backward"]
        let redoButton = app.buttons["arrow.uturn.forward"]

        // At least one of the undo/redo buttons should exist in the toolbar.
        let toolbarExists = undoButton.exists || redoButton.exists
        XCTAssertTrue(toolbarExists, "Expected undo/redo toolbar buttons to be present")
    }

    /// The close/dismiss button is present in the navigation bar.
    func testCloseButtonExists() throws {
        let webView = app.webViews.firstMatch
        XCTAssertTrue(webView.waitForExistence(timeout: 30))

        let closeButton = app.buttons["xmark"]
        XCTAssertTrue(closeButton.exists, "Expected close (xmark) button in the toolbar")
    }
}
