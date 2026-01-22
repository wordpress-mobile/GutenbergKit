package org.wordpress.gutenberg.model

import org.junit.Assert.assertEquals
import org.junit.Test

class EditorProgressTest {

    @Test
    fun `reports zero when there are no completed items`() {
        assertEquals(0.0, EditorProgress(completed = 0, total = 5).fractionCompleted, 0.0)
    }

    @Test
    fun `reports zero when there are no total items`() {
        assertEquals(0.0, EditorProgress(completed = 5, total = 0).fractionCompleted, 0.0)
    }

    @Test
    fun `reports the correct percentage when there are both completed and total items`() {
        assertEquals(1.0, EditorProgress(completed = 5, total = 5).fractionCompleted, 0.0)
    }

    @Test
    fun `reports a maximum of 1_0 when there are more completed items than total items`() {
        assertEquals(1.0, EditorProgress(completed = 10, total = 5).fractionCompleted, 0.0)
    }
}
