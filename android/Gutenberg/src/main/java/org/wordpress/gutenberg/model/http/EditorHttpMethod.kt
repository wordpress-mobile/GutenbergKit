package org.wordpress.gutenberg.model.http

import kotlinx.serialization.Serializable

@Serializable
enum class EditorHttpMethod {
    GET,
    POST,
    PUT,
    DELETE,
    OPTIONS,
    PATCH,
}
