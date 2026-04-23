package org.wordpress.gutenberg.preview

import android.graphics.Bitmap
import android.graphics.Color
import android.util.Log
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File

/**
 * Instrumented tests that exercise [HtmlToBitmapRenderer] against a real Android
 * [android.webkit.WebView]. Runs in CI via the `:android: Test Android Library
 * Instrumented` step (`make test-android-library-e2e`); locally:
 *
 *   ./gradlew :Gutenberg:connectedAndroidTest
 *
 * Each test writes its rendered PNG under `<externalCacheDir>/gbk-test-renders/`
 * and logs the absolute path at INFO level under the `GBKRendererTest` tag so you
 * can `adb pull` it for visual inspection.
 */
@RunWith(AndroidJUnit4::class)
class HtmlToBitmapRendererInstrumentedTest {

    private val context = InstrumentationRegistry.getInstrumentation().targetContext
    private val renderer = HtmlToBitmapRenderer(context)

    @Test
    fun rendersSolidColorBoxWithExpectedPixels() = runBlocking {
        val html = """
            <!doctype html>
            <html><body style="margin:0;padding:0;background:#00ff00">
              <div style="width:300px;height:200px"></div>
            </body></html>
        """.trimIndent()

        val bitmap = renderer.render(
            html = html,
            viewportWidthCssPx = 300,
            maxOutputDimensionPx = 600,
        )

        assertTrue("bitmap width > 0", bitmap.width > 0)
        assertTrue("bitmap height > 0", bitmap.height > 0)

        val centerColor = bitmap.getPixel(bitmap.width / 2, bitmap.height / 2)
        assertEquals("center pixel should be pure green", Color.GREEN, centerColor)

        writeDebugPng(bitmap, "solid-green.png")
    }

    @Test
    fun rendersMultiBlockPatternLayout() = runBlocking {
        val html = """
            <!doctype html>
            <html>
              <head><style>
                body { margin: 0; font-family: sans-serif; background: #fff; }
                .header { background: #1e73be; color: white; padding: 24px;
                          font-size: 32px; font-weight: bold; }
                .content { padding: 24px; color: #333; font-size: 16px; line-height: 1.5; }
                .card { background: #f5f5f5; padding: 16px; margin-top: 16px;
                        border-radius: 8px; }
              </style></head>
              <body>
                <div class="header">Welcome to GutenbergKit</div>
                <div class="content">
                  <p>This is a block pattern preview rendered by HtmlToBitmapRenderer.</p>
                  <div class="card">Card one.</div>
                  <div class="card">Card two.</div>
                </div>
              </body>
            </html>
        """.trimIndent()

        val bitmap = renderer.render(
            html = html,
            viewportWidthCssPx = 1200,
            maxOutputDimensionPx = 1280,
        )

        assertTrue("bitmap width > 0", bitmap.width > 0)
        assertTrue("bitmap height > 0", bitmap.height > 0)

        writeDebugPng(bitmap, "multi-block-pattern.png")
    }

    @Test
    fun rendersEmbeddedDataUriImage() = runBlocking {
        // 1x1 red pixel PNG, base64-encoded. Stretched to 200x200 for easy visual scan.
        val redPixel = "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJ" +
            "AAAADUlEQVR4AWP4z8DwHwAFAAH/q842iQAAAABJRU5ErkJggg=="
        val html = """
            <!doctype html>
            <html><body style="margin:0;padding:0;background:#ffffff">
              <img src="$redPixel" style="width:200px;height:200px;display:block" />
            </body></html>
        """.trimIndent()

        val bitmap = renderer.render(
            html = html,
            viewportWidthCssPx = 200,
            maxOutputDimensionPx = 400,
        )

        assertTrue("bitmap width > 0", bitmap.width > 0)
        assertTrue("bitmap height > 0", bitmap.height > 0)

        writeDebugPng(bitmap, "data-uri-image.png")
    }

    private fun writeDebugPng(bitmap: Bitmap, name: String) {
        val dir = File(context.externalCacheDir ?: context.cacheDir, "gbk-test-renders")
        dir.mkdirs()
        val out = File(dir, name)
        out.outputStream().use { stream ->
            bitmap.compress(Bitmap.CompressFormat.PNG, 100, stream)
        }
        Log.i("GBKRendererTest", "Wrote debug render: ${out.absolutePath}")
    }
}
