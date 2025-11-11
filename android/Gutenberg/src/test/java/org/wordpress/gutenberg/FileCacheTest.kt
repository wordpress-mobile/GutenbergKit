package org.wordpress.gutenberg

import android.content.Context
import android.net.Uri
import org.junit.After
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.assertFalse
import java.io.File

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28], manifest = Config.NONE)
class FileCacheTest {
    private lateinit var context: Context

    @Before
    fun setup() {
        context = RuntimeEnvironment.getApplication()

        // Clean up cache before each test
        FileCache.clearCache(context)
    }

    @After
    fun tearDown() {
        // Clean up cache after each test
        FileCache.clearCache(context)
    }

    @Test
    fun `clearCache removes all cached files`() {
        // Given - create some test files in the cache directory
        val cacheDir = File(context.cacheDir, "gutenberg_file_uploads")
        cacheDir.mkdirs()

        val testFile1 = File(cacheDir, "test1.jpg")
        val testFile2 = File(cacheDir, "test2.mp4")
        testFile1.writeText("test content 1")
        testFile2.writeText("test content 2")

        assertTrue("Test file 1 should exist", testFile1.exists())
        assertTrue("Test file 2 should exist", testFile2.exists())

        // When
        FileCache.clearCache(context)

        // Then
        assertFalse("Test file 1 should be deleted", testFile1.exists())
        assertFalse("Test file 2 should be deleted", testFile2.exists())
        assertTrue("Cache directory should still exist", cacheDir.exists())
    }

    @Test
    fun `clearCache handles non-existent cache directory`() {
        // Given - ensure cache directory doesn't exist
        val cacheDir = File(context.cacheDir, "gutenberg_file_uploads")
        if (cacheDir.exists()) {
            cacheDir.deleteRecursively()
        }

        // When - should not throw an exception
        FileCache.clearCache(context)

        // Then - no exception should be thrown
        assertTrue("Test should complete without exception", true)
    }

    // Note: Tests for copyToCache() and isMediaFile() require ContentResolver access
    // which is not easily testable in unit tests. These methods should be tested
    // in instrumented tests (androidTest) with real content providers.
    // The core cache management functionality (clearCache) is tested above.
}
