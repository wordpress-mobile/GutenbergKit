package org.wordpress.gutenberg

import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebView

public interface GutenbergRequestInterceptor {
    fun modifyRequest(view: WebView, request: WebResourceRequest): WebResourceResponse?
}

class DefaultGutenbergRequestInterceptor: GutenbergRequestInterceptor {
    override fun modifyRequest(view: WebView, request: WebResourceRequest): WebResourceResponse? {
        return null
    }
}