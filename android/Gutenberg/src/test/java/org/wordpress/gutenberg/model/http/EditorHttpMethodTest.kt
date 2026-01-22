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
                EditorHttpMethod.OPTIONS,
                EditorHttpMethod.PATCH
            ),
            allMethods
        )
    }

    @Test
    fun `toString returns all-caps HTTP method name`() {
        assertEquals("GET", EditorHttpMethod.GET.toString())
        assertEquals("POST", EditorHttpMethod.POST.toString())
        assertEquals("PUT", EditorHttpMethod.PUT.toString())
        assertEquals("DELETE", EditorHttpMethod.DELETE.toString())
        assertEquals("OPTIONS", EditorHttpMethod.OPTIONS.toString())
        assertEquals("PATCH", EditorHttpMethod.PATCH.toString())
    }
}
