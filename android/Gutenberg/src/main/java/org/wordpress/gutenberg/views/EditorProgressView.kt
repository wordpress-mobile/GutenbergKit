package org.wordpress.gutenberg.views

import android.content.Context
import android.util.AttributeSet
import android.view.Gravity
import android.widget.LinearLayout
import android.widget.ProgressBar
import android.widget.TextView
import androidx.core.widget.TextViewCompat
import org.wordpress.gutenberg.model.EditorProgress

/**
 * A view displaying a progress bar with a customizable label underneath.
 *
 * This view is used to show loading progress while the editor dependencies
 * are being fetched from the network.
 *
 * ## Usage
 *
 * ```kotlin
 * val progressView = EditorProgressView(context)
 * progressView.loadingText = "Loading Editor..."
 * progressView.setProgress(EditorProgress(completed = 50, total = 100))
 * ```
 */
class EditorProgressView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
    defStyleAttr: Int = 0
) : LinearLayout(context, attrs, defStyleAttr) {

    private val progressBar: ProgressBar
    private val label: TextView

    /**
     * The text displayed below the progress bar.
     */
    var loadingText: String
        get() = label.text.toString()
        set(value) {
            label.text = value
        }

    init {
        orientation = VERTICAL
        gravity = Gravity.CENTER

        // Create progress bar
        progressBar = ProgressBar(context, null, android.R.attr.progressBarStyleHorizontal).apply {
            layoutParams = LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT).apply {
                marginStart = dpToPx(16)
                marginEnd = dpToPx(16)
            }
            max = 100
            progress = 0
        }

        // Create label
        label = TextView(context).apply {
            layoutParams = LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT).apply {
                topMargin = dpToPx(8)
                marginStart = dpToPx(16)
                marginEnd = dpToPx(16)
            }
            gravity = Gravity.CENTER
            TextViewCompat.setTextAppearance(this, android.R.style.TextAppearance_Material_Body1)
        }

        addView(progressBar)
        addView(label)
    }

    /**
     * Updates the progress bar with the given progress.
     *
     * @param progress The current loading progress with completed/total counts.
     * @param animated Whether to animate the progress change.
     */
    fun setProgress(progress: EditorProgress, animated: Boolean = true) {
        val progressPercent = (progress.fractionCompleted * 100).toInt()
        if (animated && android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.N) {
            progressBar.setProgress(progressPercent, true)
        } else {
            progressBar.progress = progressPercent
        }
    }

    private fun dpToPx(dp: Int): Int {
        return (dp * context.resources.displayMetrics.density).toInt()
    }
}
