package org.wordpress.gutenberg.inserter

import org.junit.Assert.assertEquals
import org.junit.Test

class PhotoAccessStateTest {

    // resolvePromptState

    @Test
    fun `unasked when never prompted, regardless of canReprompt`() {
        assertEquals(
            PromptState.Unasked,
            resolvePromptState(promptedBefore = false, canReprompt = true),
        )
        assertEquals(
            PromptState.Unasked,
            resolvePromptState(promptedBefore = false, canReprompt = false),
        )
    }

    @Test
    fun `denied when prompted before and system can re-prompt`() {
        assertEquals(
            PromptState.Denied,
            resolvePromptState(promptedBefore = true, canReprompt = true),
        )
    }

    @Test
    fun `permanently denied when prompted before and system cannot re-prompt`() {
        assertEquals(
            PromptState.PermanentlyDenied,
            resolvePromptState(promptedBefore = true, canReprompt = false),
        )
    }

    // resolveMediaStripView

    @Test
    fun `granted access always shows full strip even after rejection`() {
        val granted = PhotoAccess.Granted(uris = emptyList())
        assertEquals(MediaStripView.FullStrip, resolveMediaStripView(granted, rejected = false))
        assertEquals(MediaStripView.FullStrip, resolveMediaStripView(granted, rejected = true))
    }

    @Test
    fun `partial access still shows full strip`() {
        val partial = PhotoAccess.Granted(
            uris = emptyList(),
            partialAccess = PhotoAccess.PartialAccess(onManageSelection = {}),
        )
        assertEquals(MediaStripView.FullStrip, resolveMediaStripView(partial, rejected = false))
        assertEquals(MediaStripView.FullStrip, resolveMediaStripView(partial, rejected = true))
    }

    @Test
    fun `needs-permission shows rationale when not rejected`() {
        val needs = needsPermission(PromptState.Denied)
        assertEquals(MediaStripView.Rationale, resolveMediaStripView(needs, rejected = false))
    }

    @Test
    fun `needs-permission shows compact tiles when rejected`() {
        val needs = needsPermission(PromptState.PermanentlyDenied)
        assertEquals(MediaStripView.CompactTiles, resolveMediaStripView(needs, rejected = true))
    }

    @Test
    fun `rationale shows for every prompt state when not rejected`() {
        for (state in PromptState.entries) {
            assertEquals(
                "state=$state",
                MediaStripView.Rationale,
                resolveMediaStripView(needsPermission(state), rejected = false),
            )
        }
    }

    private fun needsPermission(state: PromptState) =
        PhotoAccess.NeedsPermission(state = state, request = {})
}
