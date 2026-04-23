package org.wordpress.gutenberg.preview

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.view.View
import android.webkit.WebView
import android.webkit.WebViewClient
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout
import kotlin.coroutines.resume
import kotlin.math.max
import kotlin.math.min

/**
 * Renders an HTML string to a [Bitmap] by loading it into an off-screen [WebView]
 * and drawing the laid-out content onto a [Canvas].
 *
 * Mirrors the iOS `HTMLWebViewRenderer` MVP: no caching, no pooling — each call
 * creates and destroys its own WebView. Follow-ups will add a disk/memory cache
 * and reuse WebView instances across calls.
 *
 * All WebView interaction happens on the main thread. The suspending API can be
 * called from any dispatcher; work is marshalled onto [Dispatchers.Main] internally.
 */
internal class HtmlToBitmapRenderer(
    private val context: Context,
    private val timeoutMs: Long = DEFAULT_TIMEOUT_MS,
) {

    /**
     * Load [html] off-screen and return a [Bitmap] of the rendered content.
     *
     * @param viewportWidthCssPx CSS viewport width the HTML should lay out against.
     *   Block patterns typically declare 1200.
     * @param maxOutputDimensionPx Upper bound for either dimension of the returned
     *   bitmap, in device pixels. The bitmap is never upscaled — if the rendered
     *   content is already smaller it is returned at its native size.
     */
    suspend fun render(
        html: String,
        viewportWidthCssPx: Int,
        maxOutputDimensionPx: Int,
    ): Bitmap = withContext(Dispatchers.Main) {
        withTimeout(timeoutMs) {
            renderOnMainThread(html, viewportWidthCssPx, maxOutputDimensionPx)
        }
    }

    @SuppressLint("SetJavaScriptEnabled")
    private suspend fun renderOnMainThread(
        html: String,
        viewportWidthCssPx: Int,
        maxOutputDimensionPx: Int,
    ): Bitmap {
        val density = context.resources.displayMetrics.density
        val webViewWidthPx = max(1, (viewportWidthCssPx * density).toInt())

        val webView = WebView(context).apply {
            settings.javaScriptEnabled = true
            settings.useWideViewPort = false
            settings.loadWithOverviewMode = false
            isHorizontalScrollBarEnabled = false
            isVerticalScrollBarEnabled = false
        }

        return try {
            // Start with a tiny height so document.documentElement.scrollHeight
            // reflects actual content height rather than the viewport height.
            measureAndLayout(webView, webViewWidthPx, max(1, (INITIAL_HEIGHT_DP * density).toInt()))
            loadHtmlAwaitFinish(webView, html)

            val contentHeightCssPx = fetchContentHeightCssPx(webView)
            val webViewHeightPx = max(1, (contentHeightCssPx * density).toInt())
            measureAndLayout(webView, webViewWidthPx, webViewHeightPx)

            drawToBitmap(webView, webViewWidthPx, webViewHeightPx, maxOutputDimensionPx)
        } finally {
            webView.stopLoading()
            webView.destroy()
        }
    }

    private fun measureAndLayout(view: View, widthPx: Int, heightPx: Int) {
        val widthSpec = View.MeasureSpec.makeMeasureSpec(widthPx, View.MeasureSpec.EXACTLY)
        val heightSpec = View.MeasureSpec.makeMeasureSpec(heightPx, View.MeasureSpec.EXACTLY)
        view.measure(widthSpec, heightSpec)
        view.layout(0, 0, widthPx, heightPx)
    }

    private suspend fun loadHtmlAwaitFinish(webView: WebView, html: String) {
        suspendCancellableCoroutine<Unit> { cont ->
            webView.webViewClient = object : WebViewClient() {
                override fun onPageFinished(view: WebView?, url: String?) {
                    if (cont.isActive) cont.resume(Unit)
                }
            }
            webView.loadDataWithBaseURL(null, html, MIME_HTML, ENCODING_UTF8, null)
        }
    }

    private suspend fun fetchContentHeightCssPx(webView: WebView): Float =
        suspendCancellableCoroutine { cont ->
            webView.evaluateJavascript("document.documentElement.scrollHeight") { value ->
                val height = value?.trim()?.trim('"')?.toFloatOrNull() ?: 0f
                if (cont.isActive) cont.resume(height)
            }
        }

    private fun drawToBitmap(
        webView: WebView,
        widthPx: Int,
        heightPx: Int,
        maxOutputDimensionPx: Int,
    ): Bitmap {
        val widthScale = maxOutputDimensionPx.toFloat() / widthPx
        val heightScale = maxOutputDimensionPx.toFloat() / heightPx
        val scale = min(min(widthScale, heightScale), 1f)

        val outputWidth = max(1, (widthPx * scale).toInt())
        val outputHeight = max(1, (heightPx * scale).toInt())

        val bitmap = Bitmap.createBitmap(outputWidth, outputHeight, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        canvas.drawColor(Color.WHITE)
        if (scale < 1f) canvas.scale(scale, scale)
        webView.draw(canvas)
        return bitmap
    }

    companion object {
        const val DEFAULT_VIEWPORT_WIDTH_CSS_PX = 1200
        const val DEFAULT_MAX_OUTPUT_DIMENSION_PX = 1280
        const val DEFAULT_TIMEOUT_MS = 16_000L
        private const val INITIAL_HEIGHT_DP = 80
        private const val MIME_HTML = "text/html"
        private const val ENCODING_UTF8 = "UTF-8"
    }
}
