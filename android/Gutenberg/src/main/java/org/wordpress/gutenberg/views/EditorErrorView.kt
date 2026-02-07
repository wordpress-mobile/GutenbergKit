package org.wordpress.gutenberg.views

import android.content.Context
import android.util.AttributeSet
import android.view.Gravity
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import androidx.core.widget.TextViewCompat

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

        addView(icon)
        addView(titleText)
        addView(descriptionText)
    }

    /**
     * Updates the error view with the given error.
     *
     * @param error The exception that caused the failure.
     */
    fun setError(error: Throwable) {
        descriptionText.text = error.message ?: "Unknown error"
    }

    private fun dpToPx(dp: Int): Int {
        return (dp * context.resources.displayMetrics.density).toInt()
    }
}
