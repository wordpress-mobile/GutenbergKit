public struct EditorViewModel {
    var id: Int?

    let initialTitle: String
    let initialContent: String
    let siteURL: String
    let siteApiRoot: String
    let siteApiNamespace: String
    let authHeader: String


    private var type: String

    let features: [Feature]

    public enum Feature: CaseIterable {
        case Plugins
        case ThemeStyles
    }

    public init(
        id: Int? = nil,
        initialTitle: String,
        initialContent: String,
        siteURL: String,
        siteApiRoot: String,
        siteApiNamespace: String,
        authHeader: String,
        type: String,
        features: [Feature] = []
    ) {
        self.id = id
        self.initialTitle = initialTitle
        self.initialContent = initialContent
        self.siteURL = siteURL
        self.siteApiRoot = siteApiRoot
        self.siteApiNamespace = siteApiNamespace
        self.authHeader = authHeader
        self.type = type
        self.features = features
    }
}
