package org.wordpress.gutenberg

import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse

interface GutenbergRequestInterceptor {
    fun canIntercept(request: WebResourceRequest): Boolean
    fun handleRequest(request: WebResourceRequest): WebResourceResponse?
}

class DefaultGutenbergRequestInterceptor: GutenbergRequestInterceptor {
    override fun canIntercept(request: WebResourceRequest): Boolean {
        return false
    }

    override fun handleRequest(request: WebResourceRequest): WebResourceResponse? {
        return null
    }
}
