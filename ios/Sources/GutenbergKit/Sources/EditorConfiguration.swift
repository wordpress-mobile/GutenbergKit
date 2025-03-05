import Foundation

public struct EditorConfiguration {
    /// The initial title to initialize the editor with.
    public var title = ""
    /// The initial content to initialize the editor with.
    public var content = ""

    public var postID: Int?
    public var postType: String?
    public var themeStyles = false
    public var plugins = false
    public var hideTitle = false
    public var siteURL = ""
    public var siteApiRoot = ""
    public var siteApiNamespace = ""
    public var authHeader = ""

    public init(title: String = "", content: String = "") {
        self.title = title
        self.content = content
    }

    var manifestURL: URL {
        URL(string: siteApiRoot)!
            .appendingPathComponent("__experimental")
            .appendingPathComponent("wp-block-editor")
            .appendingPathComponent("v1")
            .appendingPathComponent( "editor-assets" )
    }
}
