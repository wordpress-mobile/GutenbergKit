package org.wordpress.gutenberg.model

import android.os.Parcelable
import kotlinx.parcelize.Parcelize
import kotlinx.serialization.Serializable

/**
 * Details about a WordPress post type needed for REST API interactions.
 *
 * This class encapsulates the information required to construct correct REST API
 * endpoints for different post types. WordPress custom post types (like WooCommerce
 * products) have their own REST endpoints that differ from the standard `/wp/v2/posts/`.
 *
 * For standard post types, use the provided constants:
 * ```kotlin
 * val config = EditorConfiguration.builder(siteURL, siteApiRoot, PostTypeDetails.post)
 * val config = EditorConfiguration.builder(siteURL, siteApiRoot, PostTypeDetails.page)
 * ```
 *
 * For custom post types, create an instance with the appropriate REST base:
 * ```kotlin
 * val productType = PostTypeDetails(postType = "product", restBase = "products")
 * val config = EditorConfiguration.builder(siteURL, siteApiRoot, productType)
 * ```
 *
 * @property postType The post type slug (e.g., "post", "page", "product").
 * @property restBase The REST API base path for this post type (e.g., "posts", "pages", "products").
 * @property restNamespace The REST API namespace for this post type (e.g., "wp/v2"). Defaults to "wp/v2".
 */
@Parcelize
@Serializable
data class PostTypeDetails(
    val postType: String,
    val restBase: String,
    val restNamespace: String = "wp/v2"
) : Parcelable {
    companion object {
        /** Standard WordPress post type. */
        val post = PostTypeDetails(postType = "post", restBase = "posts")

        /** Standard WordPress page type. */
        val page = PostTypeDetails(postType = "page", restBase = "pages")
    }
}
