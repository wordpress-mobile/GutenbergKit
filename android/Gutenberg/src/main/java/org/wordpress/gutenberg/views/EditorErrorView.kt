package org.wordpress.gutenberg.views

import android.content.Context
import android.util.AttributeSet
import android.view.Gravity
import android.widget.Button
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import androidx.annotation.StringRes
import androidx.core.view.ViewCompat
import androidx.core.widget.TextViewCompat
import org.wordpress.gutenberg.R

/**
 * A view displaying an error state with an icon, title, and description.
 *
 * This view is used inside [org.wordpress.gutenberg.GutenbergView] to show
 * an error when editor dependencies fail to load.
 *
 * ## Usage
 *
 * ```kotlin
 * val errorView = EditorErrorView(context)
 * errorView.setError(exception)
 * ```
 */
class EditorErrorView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
    defStyleAttr: Int = 0
) : LinearLayout(context, attrs, defStyleAttr) {

    private val icon: ImageView
    private val titleText: TextView
    private val descriptionText: TextView
    private val actionButton: Button

    /// Restored by [setError] after [setActionableState] has replaced the title.
    private val loadFailedTitle: CharSequence

    init {
        orientation = VERTICAL
        gravity = Gravity.CENTER

        // Create error icon
        icon = ImageView(context).apply {
            layoutParams = LayoutParams(dpToPx(48), dpToPx(48))
            setImageResource(android.R.drawable.ic_dialog_alert)
        }

        // Create title
        titleText = TextView(context).apply {
            layoutParams = LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT).apply {
                topMargin = dpToPx(16)
                marginStart = dpToPx(16)
                marginEnd = dpToPx(16)
            }
            gravity = Gravity.CENTER
            TextViewCompat.setTextAppearance(this, android.R.style.TextAppearance_Material_Subhead)
            text = "Failed to load editor"
            ViewCompat.setAccessibilityHeading(this, true)
        }

        // Create description
        descriptionText = TextView(context).apply {
            layoutParams = LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT).apply {
                topMargin = dpToPx(8)
                marginStart = dpToPx(16)
                marginEnd = dpToPx(16)
            }
            gravity = Gravity.CENTER
            TextViewCompat.setTextAppearance(this, android.R.style.TextAppearance_Material_Body1)
        }

        // Hidden unless the state gives the user something to do about it.
        actionButton = Button(context).apply {
            layoutParams = LayoutParams(LayoutParams.WRAP_CONTENT, LayoutParams.WRAP_CONTENT).apply {
                topMargin = dpToPx(16)
            }
            visibility = GONE
        }

        addView(icon)
        addView(titleText)
        addView(descriptionText)
        addView(actionButton)

        loadFailedTitle = titleText.text
    }

    /**
     * Updates the error view with the given error.
     *
     * @param error The exception that caused the failure.
     */
    fun setError(error: Throwable) {
        titleText.text = loadFailedTitle
        descriptionText.text = error.message ?: "Unknown error"
        clearAction()
    }

    /**
     * Shows a state the user can act on, rather than a load failure.
     *
     * @param titleResId Title describing the state.
     * @param descriptionResId What the user can do about it.
     * @param actionResId Label for the action button.
     * @param onAction Invoked when the action button is tapped.
     */
    fun setActionableState(
        @StringRes titleResId: Int,
        @StringRes descriptionResId: Int,
        @StringRes actionResId: Int,
        onAction: () -> Unit
    ) {
        titleText.setText(titleResId)
        descriptionText.setText(descriptionResId)
        actionButton.setText(actionResId)
        actionButton.setOnClickListener { onAction() }
        actionButton.visibility = VISIBLE
    }

    private fun clearAction() {
        actionButton.setOnClickListener(null)
        actionButton.visibility = GONE
    }

    private fun dpToPx(dp: Int): Int {
        return (dp * context.resources.displayMetrics.density).toInt()
    }
}
