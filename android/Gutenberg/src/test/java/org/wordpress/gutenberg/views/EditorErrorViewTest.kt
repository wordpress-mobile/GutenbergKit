package org.wordpress.gutenberg.views

import android.app.Activity
import android.os.Looper
import android.view.ContextThemeWrapper
import android.view.View
import android.view.accessibility.AccessibilityManager
import android.view.accessibility.AccessibilityNodeInfo
import android.widget.Button
import android.widget.TextView
import androidx.annotation.StyleRes
import androidx.core.view.ViewCompat
import com.google.android.material.button.MaterialButton
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNotSame
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
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

    @Test
    fun `night mode change keeps the action button's label, visibility, and action`() {
        val view = EditorErrorView(themedContext(com.google.android.material.R.style.Theme_MaterialComponents_Light))
        var actionCount = 0
        view.setActionableState(
            titleResId = R.string.gbk_editor_crashed_title,
            descriptionResId = R.string.gbk_editor_crashed_description,
            actionResId = R.string.gbk_editor_crashed_reload,
            onAction = { actionCount++ }
        )
        val originalButton = actionButton(view)

        view.dispatchConfigurationChanged(nightModeToggled(view.context))

        val button = actionButton(view)
        assertNotSame(originalButton, button)
        assertEquals(view.context.getString(R.string.gbk_editor_crashed_reload), button.text.toString())
        assertEquals(View.VISIBLE, button.visibility)
        button.performClick()
        assertEquals(1, actionCount)
    }

    @Test
    fun `night mode change re-resolves the text and button colors`() {
        val context = themedContext(com.google.android.material.R.style.Theme_MaterialComponents_Light)
        val view = EditorErrorView(context)
        view.setActionableState(
            titleResId = R.string.gbk_editor_crashed_title,
            descriptionResId = R.string.gbk_editor_crashed_description,
            actionResId = R.string.gbk_editor_crashed_reload,
            onAction = {}
        )
        val dayTitleColor = title(view).currentTextColor
        val dayDescriptionColor = description(view).currentTextColor
        val dayButtonColor = actionButton(view).currentTextColor

        // Stands in for the platform rebasing a DayNight theme onto its night
        // variant, which Robolectric's `Theme.rebase()` does not do.
        context.theme.applyStyle(com.google.android.material.R.style.Theme_MaterialComponents, true)
        view.dispatchConfigurationChanged(nightModeToggled(view.context))

        assertNotEquals(dayTitleColor, title(view).currentTextColor)
        assertNotEquals(dayDescriptionColor, description(view).currentTextColor)
        assertNotEquals(dayButtonColor, actionButton(view).currentTextColor)
    }

    @Test
    fun `setError after a night mode change hides the replaced button and drops its action`() {
        val view = EditorErrorView(themedContext(com.google.android.material.R.style.Theme_MaterialComponents_Light))
        var actionCount = 0
        view.setActionableState(
            titleResId = R.string.gbk_editor_crashed_title,
            descriptionResId = R.string.gbk_editor_crashed_description,
            actionResId = R.string.gbk_editor_crashed_reload,
            onAction = { actionCount++ }
        )
        view.dispatchConfigurationChanged(nightModeToggled(view.context))

        view.setError(IllegalStateException("Load failed"))

        val button = actionButton(view)
        assertEquals(View.GONE, button.visibility)
        button.performClick()
        assertEquals(0, actionCount)
    }

    @Test
    fun `a new action after a night mode change replaces the old one`() {
        val view = EditorErrorView(themedContext(com.google.android.material.R.style.Theme_MaterialComponents_Light))
        var firstCount = 0
        var secondCount = 0
        view.setActionableState(
            titleResId = R.string.gbk_editor_crashed_title,
            descriptionResId = R.string.gbk_editor_crashed_description,
            actionResId = R.string.gbk_editor_crashed_reload,
            onAction = { firstCount++ }
        )
        view.dispatchConfigurationChanged(nightModeToggled(view.context))

        view.setActionableState(
            titleResId = R.string.gbk_editor_crashed_title,
            descriptionResId = R.string.gbk_editor_crashed_description,
            actionResId = R.string.gbk_editor_crashed_reload,
            onAction = { secondCount++ }
        )
        actionButton(view).performClick()

        assertEquals(0, firstCount)
        assertEquals(1, secondCount)
    }

    @Test
    fun `night mode change keeps keyboard focus on the action button`() {
        val view = attachedCrashView()
        actionButton(view).isFocusableInTouchMode = true
        actionButton(view).requestFocus()

        view.dispatchConfigurationChanged(nightModeToggled(view.context))

        assertTrue(actionButton(view).isFocused)
    }

    @Test
    fun `night mode change keeps TalkBack focus on the action button`() {
        val accessibilityManager = shadowOf(
            RuntimeEnvironment.getApplication().getSystemService(AccessibilityManager::class.java)
        )
        accessibilityManager.setEnabled(true)
        accessibilityManager.setTouchExplorationEnabled(true)
        val view = attachedCrashView()
        actionButton(view).performAccessibilityAction(AccessibilityNodeInfo.ACTION_ACCESSIBILITY_FOCUS, null)
        assertTrue(actionButton(view).createAccessibilityNodeInfo().isAccessibilityFocused)

        view.dispatchConfigurationChanged(nightModeToggled(view.context))

        assertTrue(actionButton(view).createAccessibilityNodeInfo().isAccessibilityFocused)
    }

    // Focus needs a window, so these views are shown in an activity.
    private fun attachedCrashView(): EditorErrorView {
        val activity = Robolectric.buildActivity(Activity::class.java).setup().get()
        activity.setTheme(com.google.android.material.R.style.Theme_MaterialComponents_Light)
        val view = EditorErrorView(activity)
        view.setActionableState(
            titleResId = R.string.gbk_editor_crashed_title,
            descriptionResId = R.string.gbk_editor_crashed_description,
            actionResId = R.string.gbk_editor_crashed_reload,
            onAction = {}
        )
        activity.setContentView(view)
        shadowOf(Looper.getMainLooper()).idle()
        return view
    }

    private fun themedContext(@StyleRes theme: Int) =
        ContextThemeWrapper(RuntimeEnvironment.getApplication(), theme)

    private fun actionButton(view: EditorErrorView): Button =
        (0 until view.childCount).map(view::getChildAt).filterIsInstance<Button>().single()

    // The action button is a TextView too, so the title and description are the
    // first two that are not.
    private fun title(view: EditorErrorView): TextView = labels(view)[0]

    private fun description(view: EditorErrorView): TextView = labels(view)[1]

    private fun labels(view: EditorErrorView): List<TextView> =
        (0 until view.childCount).map(view::getChildAt).filterIsInstance<TextView>().filter { it !is Button }
}
