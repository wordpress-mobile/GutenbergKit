package org.wordpress.gutenberg.views

import android.view.ContextThemeWrapper
import android.widget.Button
import androidx.annotation.StyleRes
import androidx.core.view.ViewCompat
import com.google.android.material.button.MaterialButton
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config
import org.wordpress.gutenberg.R

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28])
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
    fun `title is the pane title TalkBack announces`() {
        val view = EditorErrorView(themedContext(com.google.android.material.R.style.Theme_MaterialComponents_Light))

        view.setActionableState(
            titleResId = R.string.gbk_editor_crashed_title,
            descriptionResId = R.string.gbk_editor_crashed_description,
            actionResId = R.string.gbk_editor_crashed_reload,
            onAction = {}
        )

        assertEquals(
            view.context.getString(R.string.gbk_editor_crashed_title),
            ViewCompat.getAccessibilityPaneTitle(view)?.toString()
        )
    }

    private fun themedContext(@StyleRes theme: Int) =
        ContextThemeWrapper(RuntimeEnvironment.getApplication(), theme)

    private fun actionButton(view: EditorErrorView): Button =
        (0 until view.childCount).map(view::getChildAt).filterIsInstance<Button>().single()
}
