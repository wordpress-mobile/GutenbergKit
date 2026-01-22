package org.wordpress.gutenberg

import org.wordpress.gutenberg.model.EditorProgress

/**
 * Callback interface for monitoring editor loading state.
 *
 * Implement this interface to receive updates about the editor's loading progress,
 * allowing you to display appropriate UI (progress bar, spinner, etc.) while the
 * editor initializes.
 *
 * ## Loading Flow
 *
 * When dependencies are **not provided** to `GutenbergView.start()`:
 * 1. `onDependencyLoadingStarted()` - Begin showing progress bar
 * 2. `onDependencyLoadingProgress()` - Update progress bar (called multiple times)
 * 3. `onDependencyLoadingFinished()` - Hide progress bar, show spinner
 * 4. `onEditorReady()` - Hide spinner, editor is usable
 *
 * When dependencies **are provided** to `GutenbergView.start()`:
 * 1. `onDependencyLoadingFinished()` - Show spinner (no progress phase)
 * 2. `onEditorReady()` - Hide spinner, editor is usable
 */
interface EditorLoadingListener {
    /**
     * Called when dependency loading begins.
     *
     * This is the appropriate time to show a progress bar to the user.
     * Only called when dependencies were not provided to `start()`.
     */
    fun onDependencyLoadingStarted()

    /**
     * Called periodically with progress updates during dependency loading.
     *
     * @param progress The current loading progress with completed/total counts.
     */
    fun onDependencyLoadingProgress(progress: EditorProgress)

    /**
     * Called when dependency loading completes.
     *
     * This is the appropriate time to hide the progress bar and show a spinner
     * while the WebView loads and parses the editor JavaScript.
     */
    fun onDependencyLoadingFinished()

    /**
     * Called when the editor has fully loaded and is ready for use.
     *
     * This is the appropriate time to hide all loading indicators and reveal
     * the editor. The editor APIs are safe to call after this callback.
     */
    fun onEditorReady()

    /**
     * Called if dependency loading fails.
     *
     * @param error The exception that caused the failure.
     */
    fun onDependencyLoadingFailed(error: Throwable)
}
