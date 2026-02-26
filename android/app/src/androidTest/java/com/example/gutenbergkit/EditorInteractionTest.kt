package com.example.gutenbergkit

import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.performClick
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * E2E tests for editor interactions via the native Android UI layer.
 *
 * These tests verify that user actions in the native shell (toolbar
 * taps, navigation) correctly propagate through the WebView bridge
 * to the Gutenberg editor and back.
 *
 * Unlike Playwright (which injects `window.GBKit` directly via
 * `addInitScript`), these tests exercise the real native configuration
 * pipeline: `EditorConfiguration` → `GutenbergView` →
 * JS bridge injection → Gutenberg JS initialization.
 *
 * Mirrors `EditorInteractionUITest` on iOS.
 */
@RunWith(AndroidJUnit4::class)
class EditorInteractionTest {

    @get:Rule
    val composeTestRule = createAndroidComposeRule<MainActivity>()

    // -- Editor Loading --

    /**
     * A WebView becomes visible after the editor finishes loading.
     */
    @Test
    fun testEditorWebViewBecomesVisible() {
        EditorTestHelpers.navigateToEditor(composeTestRule)
    }

    // -- Editor History --

    /**
     * Typing in the title and content enables undo; tapping undo enables redo.
     *
     * Exercises the full bridge round-trip:
     * 1. Verify undo/redo are disabled on a fresh editor
     * 2. Type text in title → bridge sends `onEditorHistoryChanged` with `hasUndo: true`
     * 3. Insert Paragraph block, type in content → undo remains enabled
     * 4. Tap Undo → native calls `undo()` on GutenbergView → redo enables
     * 5. Tap Redo → redo disables, undo re-enables
     */
    @Test
    fun testUndoRedoAfterTyping() {
        EditorTestHelpers.navigateToEditor(composeTestRule)

        // On a fresh editor, both buttons should be disabled.
        EditorTestHelpers.assertDisabled(composeTestRule, "Undo")
        EditorTestHelpers.assertDisabled(composeTestRule, "Redo")

        // Type in the title field.
        EditorTestHelpers.typeInTitle("Hello")

        // After typing in the title, undo should become enabled.
        EditorTestHelpers.waitForEnabled(composeTestRule, "Undo")

        // Insert a Paragraph block and type in the content area.
        EditorTestHelpers.typeInContent("World")

        // Undo should still be enabled after typing content.
        EditorTestHelpers.waitForEnabled(composeTestRule, "Undo")

        // Tap undo — redo should become enabled.
        composeTestRule.onNodeWithContentDescription("Undo").performClick()
        EditorTestHelpers.waitForEnabled(composeTestRule, "Redo")

        // Tap redo — undo should remain enabled.
        composeTestRule.onNodeWithContentDescription("Redo").performClick()
        EditorTestHelpers.waitForEnabled(composeTestRule, "Undo")
    }
}
