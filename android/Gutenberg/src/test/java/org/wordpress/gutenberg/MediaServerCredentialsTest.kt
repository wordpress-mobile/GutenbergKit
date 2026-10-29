package org.wordpress.gutenberg

import org.junit.Assert.assertFalse
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * The counterpart of iOS's `MediaServerCredentialsTests`. The two suites assert the
 * same cases on purpose — this policy already diverged silently between the platforms
 * once, and matching cases are what makes a future divergence show up as a failing
 * test rather than as a crash on one platform and a broken server on the other.
 *
 * Robolectric is required only because [MediaServerCredentials] parses with
 * `android.net.Uri`, which is a framework class.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28], manifest = Config.NONE)
class MediaServerCredentialsTest {

    private val siteRoot = "https://example.com/wp-json/"

    @Test
    fun `accepts an absolute site root with an auth header`() {
        assertTrue(MediaServerCredentials.areUsable(siteRoot, "Bearer t"))
    }

    @Test
    fun `rejects an empty auth header`() {
        assertFalse(MediaServerCredentials.areUsable(siteRoot, ""))
    }

    // The two arms below are the ones an `isEmpty()` check used to let through.

    @Test
    fun `rejects a site root with no scheme`() {
        // What a user types when asked for their site address. OkHttp rejects the
        // resulting URL with IllegalArgumentException, which is not an IOException.
        assertFalse(MediaServerCredentials.areUsable("example.com/wp-json/", "Bearer t"))
    }

    @Test
    fun `rejects a site root with no host`() {
        assertFalse(MediaServerCredentials.areUsable("file:///tmp/wp-json", "Bearer t"))
    }

    @Test
    fun `rejects an empty site root, the default when a host configures none`() {
        assertFalse(MediaServerCredentials.areUsable("", "Bearer t"))
    }

    // MARK: - requireCredentialsForUploader

    @Test
    fun `accepts usable credentials, uploader or not`() {
        for (hasUploader in listOf(true, false)) {
            MediaServerCredentials.requireCredentialsForUploader(siteRoot, "Bearer t", hasUploader)
        }
    }

    @Test
    fun `ignores missing credentials when there is no uploader`() {
        // Nothing to deliver through, so nothing to process. This is not an error — the
        // server just stays down (areUsable decides that) and uploads fall to the
        // default WebView path, so a processor-only host must not fail here.
        MediaServerCredentials.requireCredentialsForUploader(siteRoot, "", hasUploader = false)
    }

    @Test
    fun `throws for an uploader with no auth header`() {
        assertThrows(IllegalStateException::class.java) {
            MediaServerCredentials.requireCredentialsForUploader(siteRoot, "", hasUploader = true)
        }
    }

    @Test
    fun `throws for an uploader with no site root`() {
        assertThrows(IllegalStateException::class.java) {
            MediaServerCredentials.requireCredentialsForUploader("", "Bearer t", hasUploader = true)
        }
    }

    @Test
    fun `throws for an uploader with a scheme-less site root`() {
        // The case that previously trapped on iOS and started a doomed server here.
        assertThrows(IllegalStateException::class.java) {
            MediaServerCredentials.requireCredentialsForUploader(
                "example.com/wp-json/", "Bearer t", hasUploader = true
            )
        }
    }
}
