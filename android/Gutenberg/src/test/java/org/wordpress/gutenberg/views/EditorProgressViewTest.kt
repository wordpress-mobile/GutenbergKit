package org.wordpress.gutenberg.views

import android.view.ContextThemeWrapper
import android.widget.ProgressBar
import android.widget.TextView
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNotSame
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.wordpress.gutenberg.model.EditorProgress

@RunWith(RobolectricTestRunner::class)
class EditorProgressViewTest {

    @Test
    fun `night mode change re-resolves the label color and keeps the progress`() {
        val context = lightContext()
        val view = EditorProgressView(context)
        view.loadingText = "Loading Editor..."
        view.setProgress(EditorProgress(completed = 40, total = 100), animated = false)
        val dayLabelColor = label(view).currentTextColor
        val dayBar = progressBar(view)

        // Stands in for the platform rebasing a DayNight theme onto its night
        // variant, which Robolectric's `Theme.rebase()` does not do.
        context.theme.applyStyle(com.google.android.material.R.style.Theme_MaterialComponents, true)
        view.dispatchConfigurationChanged(nightModeToggled(context))

        assertNotEquals(dayLabelColor, label(view).currentTextColor)
        assertNotSame(dayBar, progressBar(view))
        assertEquals(40, progressBar(view).progress)
        assertEquals("Loading Editor...", view.loadingText)
    }

    @Test
    fun `progress after a night mode change reaches the replaced bar`() {
        val context = lightContext()
        val view = EditorProgressView(context)
        view.dispatchConfigurationChanged(nightModeToggled(context))

        view.setProgress(EditorProgress(completed = 75, total = 100), animated = false)

        assertEquals(75, progressBar(view).progress)
    }

    private fun lightContext() = ContextThemeWrapper(
        RuntimeEnvironment.getApplication(),
        com.google.android.material.R.style.Theme_MaterialComponents_Light
    )

    private fun progressBar(view: EditorProgressView): ProgressBar =
        (0 until view.childCount).map(view::getChildAt).filterIsInstance<ProgressBar>().single()

    private fun label(view: EditorProgressView): TextView =
        (0 until view.childCount).map(view::getChildAt).filterIsInstance<TextView>().single()
}
