import Foundation

public struct EditorAssetsBundle {

    private let rootDirectory: URL

    public init(rootDirectory: URL) {
        self.rootDirectory = rootDirectory
    }

    public var editorUrl: URL {
        rootDirectory.appendingPathComponent("index.html")
    }

    public var editorWithThirdPartyBlockSupportUrl: URL {
        rootDirectory.appendingPathComponent("remote.html")
    }

    static var editorUrlFromEnvironment: URL? {
        ProcessInfo.processInfo.environment["GUTENBERG_EDITOR_URL"].flatMap(URL.init)
    }
}
