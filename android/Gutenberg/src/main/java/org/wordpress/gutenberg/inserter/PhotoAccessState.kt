package org.wordpress.gutenberg.inserter

import android.net.Uri

/**
 * Photo-library access state for the inserter's media strip. Distinguishes
 * "never asked" from "permanently denied" by persisting whether the system
 * prompt has been shown at least once — Android's
 * `shouldShowRequestPermissionRationale` alone can't tell those apart.
 */
internal sealed interface PhotoAccess {
    /**
     * Permission has been granted. `partialAccess` is non-null on Android 14+
     * when the user picked "Select photos and videos" rather than full access —
     * its `onManageSelection` reopens the system picker so the user can update
     * the selection without leaving the app.
     */
    data class Granted(
        val uris: List<Uri>,
        val partialAccess: PartialAccess? = null,
    ) : PhotoAccess
    data class NeedsPermission(
        val state: PromptState,
        val request: () -> Unit,
    ) : PhotoAccess

    data class PartialAccess(val onManageSelection: () -> Unit)
}

/**
 * Three mutually exclusive states the rationale card needs to distinguish:
 * never asked, denied once (system will re-prompt), or permanently denied
 * (system prompt is suppressed, user must enable via Settings).
 */
internal enum class PromptState { Unasked, Denied, PermanentlyDenied }

/**
 * Pure mapping from the two Android signals to the rationale's three-way state.
 * `canReprompt` is `Activity.shouldShowRequestPermissionRationale(...)`'s result;
 * `promptedBefore` is our SharedPreferences flag set after the first system prompt.
 */
internal fun resolvePromptState(
    promptedBefore: Boolean,
    canReprompt: Boolean,
): PromptState = when {
    !promptedBefore -> PromptState.Unasked
    canReprompt -> PromptState.Denied
    else -> PromptState.PermanentlyDenied
}

/**
 * Which of the three media-strip layouts the inserter should render. A granted
 * permission always wins over a sticky rejection so users get the thumbnail
 * strip back if they grant access via system Settings after dismissing the
 * rationale.
 */
internal sealed class MediaStripView {
    object Rationale : MediaStripView()
    object CompactTiles : MediaStripView()
    object FullStrip : MediaStripView()
}

internal fun resolveMediaStripView(
    access: PhotoAccess,
    rejected: Boolean,
): MediaStripView = when {
    access is PhotoAccess.Granted -> MediaStripView.FullStrip
    rejected -> MediaStripView.CompactTiles
    access is PhotoAccess.NeedsPermission -> MediaStripView.Rationale
    else -> MediaStripView.FullStrip
}
