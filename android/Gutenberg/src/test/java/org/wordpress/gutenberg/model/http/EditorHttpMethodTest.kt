package org.wordpress.gutenberg.model.http

import org.junit.Assert.assertEquals
import org.junit.Test

class EditorHttpMethodTest {

    @Test
    fun `Raw values are correct`() {
        assertEquals("GET", EditorHttpMethod.GET.name)
        assertEquals("POST", EditorHttpMethod.POST.name)
        assertEquals("PUT", EditorHttpMethod.PUT.name)
        assertEquals("DELETE", EditorHttpMethod.DELETE.name)
        assertEquals("OPTIONS", EditorHttpMethod.OPTIONS.name)
    }

    @Test
    fun `All HTTP methods are defined`() {
        val allMethods = EditorHttpMethod.entries
        assertEquals(
            listOf(
                EditorHttpMethod.GET,
                EditorHttpMethod.POST,
                EditorHttpMethod.PUT,
                EditorHttpMethod.DELETE,
                EditorHttpMethod.OPTIONS
            ),
            allMethods
        )
    }
}
