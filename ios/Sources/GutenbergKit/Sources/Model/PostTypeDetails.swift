import Foundation

/// Details about a WordPress post type needed for REST API interactions.
///
/// This struct encapsulates the information required to construct correct REST API
/// endpoints for different post types. WordPress custom post types (like WooCommerce
/// products) have their own REST endpoints that differ from the standard `/wp/v2/posts/`.
///
/// For standard post types, use the provided static instances:
/// ```swift
/// let config = EditorConfigurationBuilder(postType: .post, ...)
/// let config = EditorConfigurationBuilder(postType: .page, ...)
/// ```
///
/// For custom post types, create an instance with the appropriate REST base:
/// ```swift
/// let productType = PostTypeDetails(postType: "product", restBase: "products")
/// let config = EditorConfigurationBuilder(postType: productType, ...)
/// ```
public struct PostTypeDetails: Sendable, Hashable, Equatable {
    /// The post type slug (e.g., "post", "page", "product").
    public let postType: String

    /// The REST API base path for this post type (e.g., "posts", "pages", "products").
    public let restBase: String

    /// The REST API namespace for this post type (e.g., "wp/v2").
    public let restNamespace: String

    /// Creates a new post type details instance.
    ///
    /// - Parameters:
    ///   - postType: The post type slug (e.g., "product").
    ///   - restBase: The REST API base path (e.g., "products").
    ///   - restNamespace: The REST API namespace. Defaults to "wp/v2".
    public init(postType: String, restBase: String, restNamespace: String = "wp/v2") {
        self.postType = postType
        self.restBase = restBase
        self.restNamespace = restNamespace
    }

    /// Standard WordPress post type.
    public static let post = PostTypeDetails(postType: "post", restBase: "posts")

    /// Standard WordPress page type.
    public static let page = PostTypeDetails(postType: "page", restBase: "pages")
}
