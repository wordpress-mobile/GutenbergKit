package org.wordpress.gutenberg

import android.os.Looper
import kotlinx.coroutines.test.TestScope
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.wordpress.gutenberg.model.EditorConfiguration
import org.wordpress.gutenberg.model.EditorDependencies

@RunWith(RobolectricTestRunner::class)
class GutenbergViewBridgeTest {
    private lateinit var view: GutenbergView
    private val received = mutableListOf<String>()

    @Before
    fun setUp() {
        view = GutenbergView(
            EditorConfiguration.bundled(),
            EditorDependencies.empty,
            TestScope(),
            RuntimeEnvironment.getApplication()
        )
        view.setContentChangeListener(object : GutenbergView.ContentChangeListener {
            override fun onContentChanged() {
                received += "contentChanged"
            }
        })
        view.setHistoryChangeListener(object : GutenbergView.HistoryChangeListener {
            override fun onHistoryChanged(hasUndo: Boolean, hasRedo: Boolean) {
                received += "history $hasUndo $hasRedo"
            }
        })
        view.setSaveAvailabilityListener { availability ->
            received += "saveAvailability ${availability.isSaveable} ${availability.isSavingLocked}"
        }
        view.setFeaturedImageChangeListener(object : GutenbergView.FeaturedImageChangeListener {
            override fun onFeaturedImageChanged(mediaID: Long) {
                received += "featuredImage $mediaID"
            }
        })
        view.setOpenMediaLibraryListener(object : GutenbergView.OpenMediaLibraryListener {
            override fun onOpenMediaLibrary(config: GutenbergView.OpenMediaLibraryConfig) {
                received += "mediaLibrary ${config.contextId} ${config.multiple}"
            }
        })
        view.setLogJsExceptionListener(object : GutenbergView.LogJsExceptionListener {
            override fun onLogJsException(exception: GutenbergJsException) {
                received += "exception ${exception.message}"
            }
        })
        view.setAutocompleterTriggeredListener(object : GutenbergView.AutocompleterTriggeredListener {
            override fun onAutocompleterTriggered(type: String) {
                received += "autocompleter $type"
            }
        })
        view.setModalDialogStateListener(object : GutenbergView.ModalDialogStateListener {
            override fun onModalDialogOpened(dialogType: String) {
                received += "dialogOpened $dialogType"
            }

            override fun onModalDialogClosed(dialogType: String) {
                received += "dialogClosed $dialogType"
            }
        })
        view.setNetworkRequestListener(object : GutenbergView.NetworkRequestListener {
            override fun onNetworkRequest(request: RecordedNetworkRequest) {
                received += "networkRequest ${request.method} ${request.status}"
            }
        })
        view.setEditorDidBecomeAvailable { received += "available" }
        view.setEditorDidBecomeUnavailable { received += "unavailable" }
    }

    private fun receive(json: String) {
        view.postBridgeMessageJson(json)
        idle()
    }

    private fun idle() = shadowOf(Looper.getMainLooper()).idle()

    @Test
    fun `routes each message to its handler by name`() {
        receive("""{"message":"onEditorLoaded","body":{}}""")
        receive("""{"message":"onEditorContentChanged","body":{}}""")
        receive("""{"message":"onEditorHistoryChanged","body":{"hasUndo":true,"hasRedo":false}}""")
        receive("""{"message":"onEditorSaveAvailabilityChanged","body":{"isSaveable":true,"isSavingLocked":true}}""")
        receive("""{"message":"onEditorFeaturedImageChanged","body":{"mediaID":42}}""")
        receive("""{"message":"openMediaLibrary","body":{"multiple":false,"contextId":"ctx"}}""")
        receive("""{"message":"onEditorExceptionLogged","body":{"type":"Error","message":"boom"}}""")
        receive("""{"message":"onAutocompleterTriggered","body":{"type":"at-symbol"}}""")
        receive("""{"message":"onModalDialogOpened","body":{"dialogType":"inserter"}}""")
        receive("""{"message":"onModalDialogClosed","body":{"dialogType":"inserter"}}""")
        receive(
            """{"message":"onNetworkRequest","body":{"url":"https://example.com","method":"GET",""" +
                """"requestHeaders":{},"status":200,"responseHeaders":{},"duration":5}}"""
        )
        receive("""{"message":"onEditorUnavailable","body":{}}""")

        assertEquals(
            listOf(
                "available",
                "contentChanged",
                "history true false",
                "saveAvailability true true",
                "featuredImage 42",
                "mediaLibrary ctx false",
                "exception boom",
                "autocompleter at-symbol",
                "dialogOpened inserter",
                "dialogClosed inserter",
                "networkRequest GET 200",
                "unavailable",
            ),
            received
        )
    }

    @Test
    fun `drops a message that can't be read`() {
        receive("not json")
        receive("""["onEditorLoaded"]""")
        receive("""{"body":{}}""")
        receive("""{"message":"onEditorLoaded","body":"{}"}""")

        assertTrue(received.isEmpty())
    }

    @Test
    fun `drops a message with an unknown name`() {
        receive("""{"message":"requestSomethingElse","body":{}}""")

        assertTrue(received.isEmpty())
    }

    @Test
    fun `drops a message missing a field its handler needs`() {
        receive("""{"message":"onEditorHistoryChanged","body":{"hasUndo":true}}""")
        receive("""{"message":"onEditorFeaturedImageChanged","body":{}}""")
        receive("""{"message":"onModalDialogOpened","body":{}}""")

        assertTrue(received.isEmpty())
    }

    @Test
    fun `drops a message whose field has the wrong type`() {
        receive("""{"message":"onEditorHistoryChanged","body":{"hasUndo":"maybe","hasRedo":false}}""")
        receive("""{"message":"onEditorFeaturedImageChanged","body":{"mediaID":"forty-two"}}""")

        assertTrue(received.isEmpty())
    }

    @Test
    fun `drops a logged exception of the wrong shape`() {
        receive("""{"message":"onEditorExceptionLogged","body":{"stacktrace":"not a list"}}""")
        receive("""{"message":"onEditorExceptionLogged","body":{"context":{"nested":{"a":1}}}}""")

        assertTrue(received.isEmpty())
    }

    @Test
    fun `drops a media library request of the wrong shape`() {
        receive("""{"message":"openMediaLibrary","body":{"multiple":"yes"}}""")

        assertTrue(received.isEmpty())
    }

    @Test
    fun `drops a network request of the wrong shape`() {
        receive("""{"message":"onNetworkRequest","body":{"url":"https://example.com"}}""")

        assertTrue(received.isEmpty())
    }

    // Hosts build their own requests from these, as WordPress-Android does with
    // OkHttp, which rejects a POST without a body.
    @Test
    fun `survives a host failing to handle a network request`() {
        view.setNetworkRequestListener(object : GutenbergView.NetworkRequestListener {
            override fun onNetworkRequest(request: RecordedNetworkRequest) {
                throw IllegalArgumentException("method POST must have a request body.")
            }
        })

        receive(
            """{"message":"onNetworkRequest","body":{"url":"https://example.com","method":"POST",""" +
                """"requestHeaders":{},"status":200,"responseHeaders":{},"duration":5}}"""
        )
        receive("""{"message":"onEditorContentChanged","body":{}}""")

        assertEquals("later messages still arrive", listOf("contentChanged"), received)
    }
}
