import Foundation
import RegexBuilder

let editorCacheRoot: URL = FileManager.default
    .urls(for: .applicationSupportDirectory, in:.userDomainMask)
    .last!
    .appendingPathComponent("editor-caches")


struct EditorManifest: Codable {
    let styles_html: String
    let scripts_html: String

    let styles: [URL]
    let scripts: [URL]
    let hash: String

    init(data: Data) throws {
        self = try JSONDecoder().decode(EditorManifest.self, from: data)
    }

    var rootDirectory: URL {
        editorCacheRoot.appendingPathComponent("\(hash).editorbundle")
    }

    var editorURL: URL {
        rootDirectory.appendingPathComponent("index.html")
    }
}

public struct LocalEditorManifest: Hashable {
    public let rootDirectory: URL

    init(_ url: URL) {
        let hash = url.deletingPathExtension().lastPathComponent
        self.init(hash: hash)
    }

    init(rootDirectory: URL) {
        self.rootDirectory = rootDirectory
    }

    init(hash: String) {
        self.rootDirectory = editorCacheRoot.appendingPathComponent("\(hash).editorbundle")
    }

    public var editorURL: URL {
        rootDirectory.appendingPathComponent("index.html")
    }
}

/// A mechanism to store editor assets on-disk to avoid downloading them every time
///
public actor EditorLibrary {

    enum CachedAssetType {
        case script
        case style
    }

    struct CachedAsset {
        let type: CachedAssetType
        let source: String
        let destination: String
    }

    public nonisolated var bundledManifest: LocalEditorManifest {
        LocalEditorManifest(rootDirectory: Bundle.module.url(forResource: "Gutenberg", withExtension: nil)!)
    }

    public nonisolated var rootDirectory: URL {
        editorCacheRoot
    }

    public typealias ProgressCallback = (Progress) -> Void

    private let urlsession: URLSession

    public init(urlSession: URLSession = .shared) {
        self.urlsession = urlSession
    }

    /// Downloads the editor asset manifest from the given URL
    ///
    /// Optionally takes a progress callback for updating UI
    /// ```swift
    /// // While the user is waiting:
    /// try await EditorAssetCache().buildManifest(for: manifest) { progress in
    ///     print(progress.fractionCompleted)
    /// }
    ///
    /// // In the background, prewarming the cache:
    /// try await EditorAssetCache().buildManifest(for: manifest)
    /// ```
    ///
    ///
    @discardableResult
    public func downloadManifest(from url: URL, progress callback: ProgressCallback?) async throws -> LocalEditorManifest {
        try await downloadManifest(from: .init(url: url), progress: callback)
    }

    @discardableResult
    public func downloadManifest(from request: URLRequest, progress callback: ProgressCallback?) async throws -> LocalEditorManifest {
        let (data, _) = try await urlsession.data(for: request)
        let manifest = try EditorManifest(data: data)

        try await buildManifest(for: manifest, progress: callback)

        return LocalEditorManifest(hash: manifest.hash)
    }

    func buildManifest(for manifest: EditorManifest, progress callback: ProgressCallback? = nil) async throws {
        try FileManager.default.createDirectory(at: manifest.rootDirectory, withIntermediateDirectories: true)

        let assets = try await withThrowingTaskGroup(of: CachedAsset.self) { group in
            let progress = Progress(totalUnitCount: Int64(manifest.scripts.count + manifest.styles.count))
            callback?(progress)

            var assets: [CachedAsset] = []

            for script in manifest.scripts {
                group.addTask {
                    let destination = manifest.rootDirectory.appendingPathComponent(script.path)
                    try await self.download(source: script, to: destination)
                    return CachedAsset(type: .script, source: script.absoluteString, destination: script.path)
                }
            }

            for style in manifest.styles {
                group.addTask {
                    let destination = manifest.rootDirectory.appendingPathComponent(style.path)
                    try await self.download(source: style, to: destination)
                    return CachedAsset(type: .style, source: style.absoluteString, destination: style.path)
                }
            }

            for try await asset in group {
                progress.completedUnitCount += 1
                assets.append(asset)
            }

            return assets
        }

        try buildEditorPage(assets: assets, manifest: manifest)
    }

    func buildEditorPage(assets: [CachedAsset], manifest: EditorManifest) throws {
        var html =
"""
<!doctype html>
<html lang="en">
    <head>
        <meta charset="UTF-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no" />
        <title>Gutenberg</title>
        [!--- Scripts ---]
        [!--- Styles  ---]
    </head>
    <body class="gutenberg-kit">
        <div id="root" class="gutenberg-kit-root"></div>
    </body>
</html>
"""

        var mutableScriptHTML = manifest.scripts_html

        for asset in assets where asset.type == .script {
            mutableScriptHTML = mutableScriptHTML.replacingOccurrences(
                of: asset.source,
                with: "." + asset.destination
            )
        }

        var mutableStyleHtml = manifest.styles_html

        for asset in assets where asset.type == .style {
            mutableStyleHtml = mutableStyleHtml.replacingOccurrences(
                of: asset.source,
                with: "." + asset.destination
            )
        }

        html = html
            .replacingOccurrences(of: "[!--- Scripts ---]", with: mutableScriptHTML)
            .replacingOccurrences(of: "[!--- Styles  ---]", with: mutableStyleHtml)

        let indexPath = manifest.rootDirectory.appendingPathComponent("index.html").path
        FileManager.default.createFile(atPath: indexPath, contents: html.data(using: .utf8))
    }

    public func listManifests() throws -> [LocalEditorManifest] {
        try createRootIfNotExists()

        return try FileManager.default
            .contentsOfDirectory(atPath: rootDirectory.path)
            .compactMap { URL(string: $0) }
            .filter { $0.pathExtension == "editorbundle" }
            .map { LocalEditorManifest($0) }
    }

    public nonisolated func urlIsInsideEditorLibrary(url: URL) -> Bool {
        url.pathComponents.starts(with: editorCacheRoot.pathComponents)
    }

    public func remove(manifest: LocalEditorManifest) async throws {
        try FileManager.default.removeItem(at: manifest.rootDirectory)
    }

    private func createRootIfNotExists() throws {
        try FileManager.default.createDirectory(at: editorCacheRoot, withIntermediateDirectories: true)
    }

    private func download(source url: URL, to destination: URL) async throws {
        let (tempUrl, _) = try await urlsession.download(from: url)

        let parentDirectory = destination.deletingLastPathComponent()

        try FileManager.default.createDirectory(at: parentDirectory, withIntermediateDirectories: true)

        guard !FileManager.default.fileExists(atPath: destination.path) else {
            return
        }

        try FileManager.default.moveItem(at: tempUrl, to: destination)
    }
}
