package org.wordpress.gutenberg.model

import android.annotation.SuppressLint
import kotlinx.serialization.Serializable
import kotlin.math.min

/**
 * Represents the progress of an editor loading operation.
 *
 * Used to report progress during asset downloads and other long-running operations.
 * The progress is expressed as a count of completed items out of a total.
 */
@SuppressLint("UnsafeOptInUsageError")
@Serializable
data class EditorProgress(
    /** The number of items that have been completed. */
    val completed: Int,
    /** The total number of items for the operation. */
    val total: Int
) {
    /**
     * The progress as a fraction between 0.0 and 1.0.
     *
     * Returns 0 if either `completed` or `total` is zero.
     * The value is clamped to a maximum of 1.0.
     */
    val fractionCompleted: Double
        get() {
            if (completed == 0 || total == 0) return 0.0
            return min(completed.toDouble() / total.toDouble(), 1.0)
        }

    companion object {
        /** A progress value representing no progress (0 of 0). */
        val zero = EditorProgress(completed = 0, total = 0)
    }
}

/**
 * A callback that receives progress updates during long-running operations.
 */
typealias EditorProgressCallback = suspend (EditorProgress) -> Unit
