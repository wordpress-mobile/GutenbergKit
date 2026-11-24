package org.wordpress.gutenberg.views

import android.view.ContextThemeWrapper
import android.widget.ProgressBar
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotSame
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment

@RunWith(RobolectricTestRunner::class)
class EditorSpinnerViewTest {

    @Test
    fun `night mode change replaces the spinner`() {
        val context = lightContext()
        val view = EditorSpinnerView(context)
        val daySpinner = spinner(view)

        view.dispatchConfigurationChanged(nightModeToggled(context))

        assertNotSame(daySpinner, spinner(view))
        assertEquals(1, view.childCount)
        assertTrue(spinner(view).isIndeterminate)
    }

    @Test
    fun `configuration change without a night mode change keeps the spinner`() {
        val context = lightContext()
        val view = EditorSpinnerView(context)
        val spinner = spinner(view)

        view.dispatchConfigurationChanged(context.resources.configuration)

        assertSame(spinner, spinner(view))
    }

    private fun lightContext() = ContextThemeWrapper(
        RuntimeEnvironment.getApplication(),
        com.google.android.material.R.style.Theme_MaterialComponents_Light
    )

    private fun spinner(view: EditorSpinnerView): ProgressBar = view.getChildAt(0) as ProgressBar
}
