package com.example.gutenbergkit

import androidx.compose.ui.test.assertIsEnabled
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.junit4.AndroidComposeTestRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.test.espresso.web.model.Atoms.script
import androidx.test.espresso.web.sugar.Web.onWebView
import androidx.test.espresso.web.webdriver.DriverAtoms.findElement
import androidx.test.espresso.web.webdriver.DriverAtoms.webClick
import androidx.test.espresso.web.webdriver.Locator
import androidx.test.ext.junit.rules.ActivityScenarioRule
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue

/**
 * Reusable helpers for Android E2E tests that interact with the Gutenberg editor.
 *
 * All methods are on a companion-style object so they can be called from any
 * test file — e.g. `EditorTestHelpers.navigateToEditor(rule)`.
 *
 * Mirrors `EditorUITestHelpers` on iOS.
 */
object EditorTestHelpers {

    private const val NAVIGATE_TIMEOUT_MS = 30_000L
    private const val ELEMENT_TIMEOUT_MS = 10_000L
    private const val POLL_INTERVAL_MS = 500L

    // CSS selectors matching the Gutenberg DOM — prefer aria attributes and
    // placeholders over class names so tests are resilient to CSS refactors.
    private const val TITLE_SELECTOR = "[aria-label='Add title']"
    // Scope to the Editor toolbar to avoid matching the inline block appender,
    // which also renders an identical "Add block" button.
    private const val ADD_BLOCK_SELECTOR =
        "[aria-label='Editor toolbar'] [aria-label='Add block']"
    private const val EMPTY_BLOCK_SELECTOR =
        "[aria-label='Empty block; start writing or type forward slash to choose a block']"
    private const val CODE_EDITOR_TITLE_SELECTOR =
        "textarea[placeholder='Add title']"
    private const val CODE_EDITOR_CONTENT_SELECTOR =
        "textarea[placeholder='Start writing with text or HTML']"
    private const val INSERTER_DIALOG_SELECTOR =
        "[role='dialog'][aria-modal='true']"

    /**
     * Navigates from the main list through the configuration screen
     * and into the full-screen editor. Waits for the "Add title" element
     * in the WebView to confirm the editor has loaded.
     */
    fun navigateToEditor(
        rule: AndroidComposeTestRule<ActivityScenarioRule<MainActivity>, MainActivity>
    ) {
        // Tap the "Standalone editor" card in the main list.
        rule.waitForNodeWithText("Standalone editor")
        rule.onNodeWithText("Standalone editor").performClick()

        // Wait for and tap the "Start" button on the configuration screen.
        rule.waitForNodeWithText("Start")
        rule.onNodeWithText("Start").performClick()

        // Wait for the WebView to load: poll until the title element appears.
        waitForWebViewElement(TITLE_SELECTOR, NAVIGATE_TIMEOUT_MS)
    }

    /**
     * Types text into the title field in the WebView.
     *
     * Uses JavaScript keyboard event dispatch because Espresso Web's
     * `webKeys()` fails on Gutenberg's contenteditable rich text blocks
     * with "Cannot set the selection end".
     */
    fun typeInTitle(text: String) {
        onWebView()
            .forceJavascriptEnabled()
            .withElement(findElement(Locator.CSS_SELECTOR, TITLE_SELECTOR))
            .perform(webClick())
        typeViaExecCommand(text)
    }

    /**
     * Opens the web block inserter and inserts a block by name.
     *
     * Taps the "Add block" toggle in the editor toolbar, then clicks
     * the block option matching [name] inside the inserter popover.
     * Mirrors `EditorUITestHelpers.insertBlock(_:webView:app:)` on iOS.
     */
    fun insertBlock(name: String) {
        // Tap the "Add block" toggle button in the WebView toolbar via JS click.
        // We use JS click because the toolbar button may not pass Espresso's
        // visibility check even though it is functionally present.
        clickViaJs(ADD_BLOCK_SELECTOR)
        // Wait for the inserter dialog to appear, then find and click the block
        // option by name. Block items use role="option" with their accessible
        // name from inner text — we match via XPath within the modal dialog.
        waitForWebViewElement(INSERTER_DIALOG_SELECTOR, ELEMENT_TIMEOUT_MS)
        onWebView()
            .forceJavascriptEnabled()
            .withElement(findElement(Locator.XPATH, inserterOptionXpath(name)))
            .perform(webClick())
    }

    /**
     * Inserts a Paragraph block via the web block inserter then types
     * text into the empty block placeholder.
     */
    fun typeInContent(text: String) {
        insertBlock("Paragraph")
        // Wait for the empty block to appear after insertion.
        waitForWebViewElement(EMPTY_BLOCK_SELECTOR, ELEMENT_TIMEOUT_MS)
        onWebView()
            .forceJavascriptEnabled()
            .withElement(findElement(Locator.CSS_SELECTOR, EMPTY_BLOCK_SELECTOR))
            .perform(webClick())
        typeViaExecCommand(text)
    }

    // -- Mode Switching --

    /**
     * Switches the editor to Code Editor mode via the More options menu.
     */
    fun switchToCodeEditor(
        rule: AndroidComposeTestRule<ActivityScenarioRule<MainActivity>, MainActivity>
    ) {
        rule.onNodeWithContentDescription("More options").performClick()
        rule.waitForNodeWithText("Code editor")
        rule.onNodeWithText("Code editor").performClick()
    }

    /**
     * Switches the editor back to Visual Editor mode via the More options menu.
     */
    fun switchToVisualEditor(
        rule: AndroidComposeTestRule<ActivityScenarioRule<MainActivity>, MainActivity>
    ) {
        rule.onNodeWithContentDescription("More options").performClick()
        rule.waitForNodeWithText("Visual editor")
        rule.onNodeWithText("Visual editor").performClick()
    }

    // -- Content Reading (Code Editor Mode) --

    /**
     * Reads the current title from the code editor's title field via JS.
     * The editor must already be in Code Editor mode.
     */
    fun readTitle(): String {
        return readTextViaJs(CODE_EDITOR_TITLE_SELECTOR)
    }

    /**
     * Reads the current raw HTML content from the code editor's content textarea via JS.
     * The editor must already be in Code Editor mode.
     */
    fun readContent(): String {
        return readTextViaJs(CODE_EDITOR_CONTENT_SELECTOR)
    }

    /**
     * Switches to Code Editor, reads both title and content, then switches back.
     * Returns a [TitleAndContent] data class.
     */
    fun readTitleAndContent(
        rule: AndroidComposeTestRule<ActivityScenarioRule<MainActivity>, MainActivity>
    ): TitleAndContent {
        switchToCodeEditor(rule)
        // Wait for the code editor content textarea to appear in the DOM.
        waitForWebViewElement(CODE_EDITOR_CONTENT_SELECTOR, ELEMENT_TIMEOUT_MS)
        val title = readTitle()
        val content = readContent()
        switchToVisualEditor(rule)
        return TitleAndContent(title = title, content = content)
    }

    /**
     * Convenience assertion: switches to Code Editor, reads title and content,
     * switches back, and asserts expected values.
     */
    fun assertContent(
        expectedTitle: String? = null,
        expectedContentSubstring: String? = null,
        rule: AndroidComposeTestRule<ActivityScenarioRule<MainActivity>, MainActivity>
    ): TitleAndContent {
        val result = readTitleAndContent(rule)
        if (expectedTitle != null) {
            assertEquals("Title mismatch", expectedTitle, result.title)
        }
        if (expectedContentSubstring != null) {
            assertTrue(
                "Expected content to contain \"$expectedContentSubstring\" but got \"${result.content}\"",
                result.content.contains(expectedContentSubstring)
            )
        }
        return result
    }

    // -- Waiting Helpers --

    /**
     * Waits until a Compose node with the given content description becomes enabled.
     */
    fun waitForEnabled(
        rule: AndroidComposeTestRule<ActivityScenarioRule<MainActivity>, MainActivity>,
        contentDescription: String,
        timeoutMs: Long = ELEMENT_TIMEOUT_MS
    ) {
        rule.waitUntilAsserts(timeoutMs) {
            onNodeWithContentDescription(contentDescription).assertIsEnabled()
        }
    }

    /**
     * Asserts a Compose node with the given content description is not enabled.
     */
    fun assertDisabled(
        rule: AndroidComposeTestRule<ActivityScenarioRule<MainActivity>, MainActivity>,
        contentDescription: String
    ) {
        rule.onNodeWithContentDescription(contentDescription).assertIsNotEnabled()
    }

    // -- Internal Helpers --

    /**
     * Executes a JavaScript snippet in the WebView and returns the result as a string.
     * Centralizes the Espresso Web boilerplate shared by all JS helpers.
     */
    private fun runJs(js: String): String {
        val result = onWebView()
            .forceJavascriptEnabled()
            .perform(script(js))
            .get()
        return result.value?.toString() ?: ""
    }

    /**
     * Returns an XPath that matches a block option by [name] inside
     * the inserter dialog (role="dialog", aria-modal="true").
     */
    private fun inserterOptionXpath(name: String) =
        "//*[@role='dialog'][@aria-modal='true']//*[@role='option'][normalize-space()='$name']"

    /**
     * Clicks an element by CSS selector via JavaScript.
     *
     * Espresso Web's `webClick()` requires the element to pass a visibility
     * check, which can fail for elements in the Gutenberg toolbar. Using
     * `element.click()` in JS bypasses that restriction.
     */
    private fun clickViaJs(cssSelector: String) {
        val escapedSelector = cssSelector.replace("'", "\\'")
        val js = "var el = document.querySelector('" + escapedSelector + "');" +
            "if (!el) { return 'element not found: " + escapedSelector + "'; }" +
            "el.scrollIntoView();" +
            "el.click();" +
            "return 'clicked';"
        val value = runJs(js)
        if (value.contains("not found")) {
            throw AssertionError("clickViaJs failed: $value")
        }
    }

    /**
     * Types text into the currently focused element via
     * `document.execCommand('insertText')`, which is what mobile browsers
     * use for software keyboard input. Gutenberg's rich text listens for
     * the resulting `input` event at the contenteditable level.
     *
     * This bypasses Espresso Web's `webKeys()`, which fails on Gutenberg's
     * contenteditable rich text blocks with "Cannot set the selection end".
     */
    private fun typeViaExecCommand(text: String) {
        val escapedText = text.replace("\\", "\\\\").replace("'", "\\'")
        val js = "document.execCommand('insertText', false, '" + escapedText + "');" +
            "return 'ok';"
        runJs(js)
    }

    /**
     * Reads the text content of an element by CSS selector via JS.
     * Uses `textContent` for contenteditable elements and `value` for
     * textarea/input elements, matching how Code Editor fields render.
     */
    private fun readTextViaJs(cssSelector: String): String {
        val escapedSelector = cssSelector.replace("'", "\\'")
        val js = "var el = document.querySelector('" + escapedSelector + "');" +
            "if (!el) return '';" +
            "if (el.tagName === 'TEXTAREA' || el.tagName === 'INPUT') return el.value || '';" +
            "return el.innerText || el.textContent || '';"
        return runJs(js)
    }

    /**
     * Polls until a WebView element matching the CSS selector exists.
     * Uses `document.querySelector` in JS rather than Espresso Web's
     * `findElement`, which can fail on elements that don't pass its
     * built-in visibility check.
     */
    private fun waitForWebViewElement(cssSelector: String, timeoutMs: Long) {
        val escapedSelector = cssSelector.replace("'", "\\'")
        val js = "var el = document.querySelector('" + escapedSelector + "');" +
            "return el ? 'found' : 'not found';"
        waitForConditionViaJs(js, "found", timeoutMs)
    }

    /**
     * Polls a JS script until its return value matches [expectedResult].
     */
    private fun waitForConditionViaJs(js: String, expectedResult: String, timeoutMs: Long) {
        val deadline = System.currentTimeMillis() + timeoutMs
        var lastResult = ""

        while (System.currentTimeMillis() < deadline) {
            try {
                lastResult = runJs(js)
                if (lastResult.contains(expectedResult)) return
            } catch (_: Exception) {
                // Ignore and retry
            }
            Thread.sleep(POLL_INTERVAL_MS)
        }
        throw AssertionError(
            "Timed out waiting for JS condition. Last result: $lastResult"
        )
    }

    data class TitleAndContent(val title: String, val content: String)
}

/**
 * Polls until [block] completes without throwing, or times out.
 * Useful for waiting on Compose assertions that throw when unsatisfied.
 */
private fun AndroidComposeTestRule<*, *>.waitUntilAsserts(
    timeoutMs: Long = 10_000L,
    block: AndroidComposeTestRule<*, *>.() -> Unit
) {
    waitUntil(timeoutMs) {
        runCatching { block(); true }.getOrDefault(false)
    }
}

/**
 * Waits until a Compose node with the given [text] exists.
 */
private fun AndroidComposeTestRule<*, *>.waitForNodeWithText(
    text: String,
    timeoutMs: Long = 10_000L
) {
    waitUntilAsserts(timeoutMs) {
        onNodeWithText(text).assertExists()
    }
}
