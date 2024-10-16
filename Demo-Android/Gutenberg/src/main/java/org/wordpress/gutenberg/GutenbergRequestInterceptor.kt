package org.wordpress.gutenberg

import android.webkit.WebResourceRequest

public interface GutenbergRequestInterceptor {
    fun interceptRequest(request: WebResourceRequest): WebResourceRequest
}

class DefaultGutenbergRequestInterceptor: GutenbergRequestInterceptor {
    override fun interceptRequest(request: WebResourceRequest): WebResourceRequest {
        return request
    }
}