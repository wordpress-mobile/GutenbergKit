package org.wordpress.gutenberg

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class EditorBridgeMessageTest {
    @Test
    fun `parse reads the name and body`() {
        val message = EditorBridgeMessage.parse("""{"message":"onModalDialogOpened","body":{"dialogType":"inserter"}}""")

        assertEquals("onModalDialogOpened", message?.name)
        assertEquals("inserter", message?.body?.getString("dialogType"))
    }

    @Test
    fun `parse treats a missing body as empty`() {
        val message = EditorBridgeMessage.parse("""{"message":"onEditorLoaded"}""")

        assertEquals("onEditorLoaded", message?.name)
        assertEquals(0, message?.body?.length())
    }

    @Test
    fun `parse rejects text that isn't JSON`() {
        assertNull(EditorBridgeMessage.parse("onEditorLoaded"))
    }

    @Test
    fun `parse rejects JSON that isn't an object`() {
        assertNull(EditorBridgeMessage.parse("""["onEditorLoaded"]"""))
    }

    @Test
    fun `parse rejects a message without a name`() {
        assertNull(EditorBridgeMessage.parse("""{"body":{}}"""))
    }

    @Test
    fun `parse rejects a name that isn't a string`() {
        assertNull(EditorBridgeMessage.parse("""{"message":1,"body":{}}"""))
    }

    @Test
    fun `parse rejects a body that isn't an object`() {
        assertNull(EditorBridgeMessage.parse("""{"message":"onEditorLoaded","body":"{}"}"""))
        assertNull(EditorBridgeMessage.parse("""{"message":"onEditorLoaded","body":null}"""))
    }
}
