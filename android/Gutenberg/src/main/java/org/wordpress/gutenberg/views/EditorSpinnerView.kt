package org.wordpress.gutenberg.views

import android.content.Context
import android.content.res.Configuration
import android.view.Gravity
import android.widget.FrameLayout
import android.widget.ProgressBar

/**
 * An indeterminate spinner shown while the editor loads.
 *
 * It wraps the spinner so the spinner can be replaced to pick up a dark mode
 * change while the wrapper, which callers animate, stays in place.
 */
internal class EditorSpinnerView(context: Context) : FrameLayout(context) {

    private var spinner = createSpinner()
    private var nightMode = resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK

    init {
        addView(spinner)
    }

    /**
     * Replaces the spinner when dark mode changes without recreating the
     * activity, since its drawable resolves its theme tint only when created.
     */
    override fun onConfigurationChanged(newConfig: Configuration) {
        super.onConfigurationChanged(newConfig)
        val newNightMode = newConfig.uiMode and Configuration.UI_MODE_NIGHT_MASK
        if (newNightMode != nightMode) {
            nightMode = newNightMode
            removeView(spinner)
            spinner = createSpinner()
            addView(spinner)
        }
    }

    private fun createSpinner(): ProgressBar = ProgressBar(context).apply {
        layoutParams = LayoutParams(LayoutParams.WRAP_CONTENT, LayoutParams.WRAP_CONTENT, Gravity.CENTER)
        isIndeterminate = true
    }
}
