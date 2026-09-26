package org.wordpress.gutenberg.views

import android.view.ContextThemeWrapper
import android.widget.Button
import android.widget.TextView
import androidx.annotation.StyleRes
import androidx.core.view.ViewCompat
import com.google.android.material.button.MaterialButton
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.wordpress.gutenberg.R

@RunWith(RobolectricTestRunner::class)
class EditorErrorViewTest {

    @Test
    fun `action button is a Material button in a Material theme`() {
        val view = EditorErrorView(themedContext(com.google.android.material.R.style.Theme_MaterialComponents_Light))

        assertTrue(actionButton(view) is MaterialButton)
    }

    @Test
    fun `action button is a platform button outside a Material theme`() {
        // Constructing a MaterialButton here would throw.
        val view = EditorErrorView(themedContext(androidx.appcompat.R.style.Theme_AppCompat_Light))

        assertFalse(actionButton(view) is MaterialButton)
    }

    @Test
    fun `title is announced by moving focus, not by a pane title`() {
        val view = EditorErrorView(themedContext(com.google.android.material.R.style.Theme_MaterialComponents_Light))

        view.setActionableState(
            titleResId = R.string.gbk_editor_crashed_title,
            descriptionResId = R.string.gbk_editor_crashed_description,
            actionResId = R.string.gbk_editor_crashed_reload,
            onAction = {}
        )

        assertEquals(
            view.context.getString(R.string.gbk_editor_crashed_title),
            title(view).text.toString()
        )
        // A pane title announces when the view appears, and focusTitleForAccessibility
        // reads the title it lands on, so setting both reads the title twice.
        assertNull(ViewCompat.getAccessibilityPaneTitle(view))
    }

    private fun themedContext(@StyleRes theme: Int) =
        ContextThemeWrapper(RuntimeEnvironment.getApplication(), theme)

    private fun actionButton(view: EditorErrorView): Button =
        (0 until view.childCount).map(view::getChildAt).filterIsInstance<Button>().single()

    // The action button is a TextView too, so the title is the first that is not one.
    private fun title(view: EditorErrorView): TextView =
        (0 until view.childCount).map(view::getChildAt).filterIsInstance<TextView>().first { it !is Button }
}
