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

    // Tests for isKnownSafeLocalProvider() - Allow List

    @Test
    fun `isKnownSafeLocalProvider returns true for MediaStore images`() {
        // Given
        val mediaStoreUri = Uri.parse("content://com.android.providers.media.documents/document/image:12345")

        // When
        val result = FileCache.isKnownSafeLocalProvider(mediaStoreUri)

        // Then
        assertTrue("MediaStore images should be recognized as safe local provider", result)
    }

    @Test
    fun `isKnownSafeLocalProvider returns true for MediaStore videos`() {
        // Given
        val mediaStoreUri = Uri.parse("content://com.android.providers.media/external/video/media/456")

        // When
        val result = FileCache.isKnownSafeLocalProvider(mediaStoreUri)

        // Then
        assertTrue("MediaStore videos should be recognized as safe local provider", result)
    }

    @Test
    fun `isKnownSafeLocalProvider returns true for Downloads provider`() {
        // Given
        val downloadsUri = Uri.parse("content://com.android.providers.downloads.documents/document/123")

        // When
        val result = FileCache.isKnownSafeLocalProvider(downloadsUri)

        // Then
        assertTrue("Downloads provider should be recognized as safe local provider", result)
    }

    @Test
    fun `isKnownSafeLocalProvider returns false for Google Drive`() {
        // Given
        val driveUri = Uri.parse("content://com.google.android.apps.docs.storage/document/acc=1;doc=12345")

        // When
        val result = FileCache.isKnownSafeLocalProvider(driveUri)

        // Then
        assertFalse("Google Drive should NOT be on the allow list", result)
    }

    @Test
    fun `isKnownSafeLocalProvider returns false for OneDrive`() {
        // Given
        val oneDriveUri = Uri.parse("content://com.microsoft.skydrive.documents/document/primary:path/to/file")

        // When
        val result = FileCache.isKnownSafeLocalProvider(oneDriveUri)

        // Then
        assertFalse("OneDrive should NOT be on the allow list", result)
    }

    @Test
    fun `isKnownSafeLocalProvider returns false for unknown cloud provider`() {
        // Given
        val unknownCloudUri = Uri.parse("content://com.example.cloudstorage/document/file123")

        // When
        val result = FileCache.isKnownSafeLocalProvider(unknownCloudUri)

        // Then
        assertFalse("Unknown cloud providers should NOT be on the allow list", result)
    }

    @Test
    fun `isKnownSafeLocalProvider returns false for file URIs`() {
        // Given
        val fileUri = Uri.parse("file:///storage/emulated/0/Pictures/photo.jpg")

        // When
        val result = FileCache.isKnownSafeLocalProvider(fileUri)

        // Then
        assertFalse("File URIs should return false (not a content provider)", result)
    }

    @Test
    fun `isKnownSafeLocalProvider returns false for null authority`() {
        // Given
        val malformedUri = Uri.parse("content://")

        // When
        val result = FileCache.isKnownSafeLocalProvider(malformedUri)

        // Then
        assertFalse("URIs with null authority should return false", result)
    }

    @Test
    fun `isKnownSafeLocalProvider returns false for other Android providers`() {
        // Given - Android's contacts provider is a local provider but NOT on our allow list
        val contactsUri = Uri.parse("content://com.android.contacts/data/123")

        // When
        val result = FileCache.isKnownSafeLocalProvider(contactsUri)

        // Then
        assertFalse("Other Android providers not on allow list should return false", result)
    }
}
