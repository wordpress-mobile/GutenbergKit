package org.wordpress.gutenberg.views

import android.graphics.Color
import android.view.ContextThemeWrapper
import android.widget.Button
import androidx.annotation.StyleRes
import androidx.core.content.ContextCompat
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28])
class EditorErrorViewTest {

    @Test
    fun `action button takes the host theme's primary colors`() {
        val context = themedContext(com.google.android.material.R.style.Theme_MaterialComponents_Light)

        val button = actionButton(EditorErrorView(context))

        assertEquals(
            ContextCompat.getColor(context, com.google.android.material.R.color.design_default_color_primary),
            button.backgroundTintList?.defaultColor
        )
        assertEquals(
            ContextCompat.getColor(context, com.google.android.material.R.color.design_default_color_on_primary),
            button.currentTextColor
        )
    }

    @Test
    fun `action button picks a legible text color when the theme has no on-primary color`() {
        // AppCompat's light theme has a near-white primary color and no `colorOnPrimary`.
        val context = themedContext(androidx.appcompat.R.style.Theme_AppCompat_Light)

        val button = actionButton(EditorErrorView(context))

        assertEquals(Color.BLACK, button.currentTextColor)
    }

    private fun themedContext(@StyleRes theme: Int) =
        ContextThemeWrapper(RuntimeEnvironment.getApplication(), theme)

    private fun actionButton(view: EditorErrorView): Button =
        (0 until view.childCount).map(view::getChildAt).filterIsInstance<Button>().single()
}
