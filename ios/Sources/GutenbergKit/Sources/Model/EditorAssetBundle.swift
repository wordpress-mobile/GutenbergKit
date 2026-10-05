import CryptoKit
import Foundation
import SwiftSoup

/// A cached collection of editor assets downloaded from a remote manifest.
///
/// An `EditorAssetBundle` represents an on-disk cache of JavaScript and CSS assets
/// required by WordPress plugins and themes. The bundle is created by downloading
/// all assets specified in a server-provided manifest and storing them locally.
///
/// Bundles are identified by their manifest checksum, ensuring that different
/// versions of plugin/theme assets are stored separately. The `downloadDate`
/// property allows the system to prefer newer bundles over older ones.
///
/// Assets are accessed via URL lookup - the bundle maintains a mapping from
/// original remote URLs to local file paths.
public struct EditorAssetBundle: Sendable {

    /// The EditorRepresentation has the exact same format as `RemoteEditorAssetManifest.RawManifest` – what we're passing to Gutenberg
    /// looks exactly like what it'd get if it called `/wpcom/v2/editor-assets` directly.
    ///
    /// The difference is that we've rewritten all of the URLs to reference local files with our custom URL scheme so they can be provided from the on-disk cache.
    typealias EditorRepresentation = RemoteEditorAssetManifest.RawManifest

    /// Errors that can occur when working with asset bundles.
    enum Errors: Error, Equatable {
        /// The requested asset URL is not part of this bundle's manifest.
        case invalidRequest

        /// An asset with the same key already exists in the lookup table.
        case assetAlreadyExists(String)
    }

    /// The data structure stored on-disk
    struct RawAssetBundle: Codable {
        let manifest: LocalEditorAssetManifest
        let downloadDate: Date
        /// Absent from a bundle stored before this was recorded.
        var lastCheckedDate: Date?
        /// Absent from a bundle stored before these were recorded.
        var assetHeaders: [String: AssetHeaders]?
    }

    /// What a server sent with an asset that's worth keeping with it: what kind of file it is, and what tells
    /// one version of it from another.
    struct AssetHeaders: Codable, Hashable, Sendable {
        /// The response's `Content-Type`, as the server sent it. The editor is served the asset with it.
        let contentType: String?

        /// The response's `ETag`, as the server sent it.
        let etag: String?

        /// The response's `Last-Modified`, as the server sent it.
        let lastModified: String?

        init(contentType: String? = nil, etag: String? = nil, lastModified: String? = nil) {
            self.contentType = contentType
            self.etag = etag
            self.lastModified = lastModified
        }

        /// The headers of `response` that are worth keeping, or `nil` if it carries none of them.
        init?(response: HTTPURLResponse) {
            self.init(
                contentType: response.value(forHTTPHeaderField: "Content-Type"),
                etag: response.value(forHTTPHeaderField: "ETag"),
                lastModified: response.value(forHTTPHeaderField: "Last-Modified")
            )

            guard self.contentType != nil || self.canRevalidate else {
                return nil
            }
        }

        /// Whether these say how to tell one version of the asset from another, so that a later request
        /// can ask the server only for a newer copy.
        var canRevalidate: Bool {
            self.etag != nil || self.lastModified != nil
        }

        /// Makes `request` ask only for a copy newer than the one these came with, which a server
        /// that has none answers with a 304.
        func makeConditional(_ request: inout URLRequest) {
            if let etag {
                request.setValue(etag, forHTTPHeaderField: "If-None-Match")
            }

            if let lastModified {
                request.setValue(lastModified, forHTTPHeaderField: "If-Modified-Since")
            }
        }
    }

    /// The bundle's unique identifier, derived from its manifest checksum.
    ///
    /// Two bundles with the same ID have identical manifests and _should_ contain identical assets. This may not be
    /// true if a site is under development, so asset bundles should have some mechanism for being re-downloaded entirely.
    public var id: String {
        manifest.checksum
    }

    /// The manifest that defines which assets belong to this bundle.
    let manifest: LocalEditorAssetManifest

    /// The date this bundle was created by downloading the manifest contents.
    ///
    /// Used to determine which bundle is most recent when multiple bundles exist, until the bundle
    /// has a ``lastCheckedDate``.
    let downloadDate: Date

    /// The date the site's manifest was last found to match this bundle, if that's been recorded.
    ///
    /// It says how recently the bundle was confirmed, not what the bundle is, so two copies of a
    /// bundle that differ only in this are equal.
    let lastCheckedDate: Date?

    /// When the site's manifest is last known to have matched this bundle: when it was last
    /// checked, or else when it was downloaded.
    ///
    /// Used to determine which bundle is the site's latest, and how old it is for the cache policy.
    var lastMatchedDate: Date {
        lastCheckedDate ?? downloadDate
    }

    /// The headers kept from each asset's download, by the asset's ``assetKey(for:)``. An asset whose server
    /// sent none worth keeping has no entry.
    let assetHeaders: [String: AssetHeaders]

    /// The number of assets stored in this bundle.
    public var assetCount: Int {
        manifest.assetUrls.count
    }

    let bundleRoot: URL

    init(raw: RawAssetBundle, bundleRoot: URL) {
        self.manifest = raw.manifest
        self.downloadDate = raw.downloadDate
        self.lastCheckedDate = raw.lastCheckedDate
        self.assetHeaders = raw.assetHeaders ?? [:]
        self.bundleRoot = bundleRoot
    }

    init(
        manifest: LocalEditorAssetManifest,
        downloadDate: Date = Date(),
        lastCheckedDate: Date? = nil,
        assetHeaders: [String: AssetHeaders] = [:],
        bundleRoot: URL
    ) throws {
        self.manifest = manifest
        self.downloadDate = downloadDate
        self.lastCheckedDate = lastCheckedDate
        self.assetHeaders = assetHeaders
        self.bundleRoot = bundleRoot
    }

    /// Loads a bundle from a JSON file on disk.
    ///
    /// - Parameter url: The file URL of the bundle's `manifest.json`.
    /// - Throws: An error if the file cannot be read or decoded, or if required files are missing.
    init(url: URL) throws {
        let bundleRoot = url.deletingLastPathComponent()

        // Validate that editor-representation.json exists (required for the bundle to be usable)
        let editorRepPath = bundleRoot.appending(path: "editor-representation.json")
        guard FileManager.default.fileExists(atPath: editorRepPath.path) else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: editorRepPath.path])
        }

        self = try EditorAssetBundle(data: Data(contentsOf: url), bundleRoot: bundleRoot)
    }

    init(data: Data, bundleRoot: URL) throws {
        let rawBundle = try JSONDecoder().decode(RawAssetBundle.self, from: data)
        self = EditorAssetBundle(
            raw: rawBundle,
            bundleRoot: bundleRoot
        )
    }

    /// Where the asset at `url` is stored in the bundle.
    ///
    /// This is the one place that's decided. What writes an asset and what reads it both ask here, so they
    /// can't disagree.
    ///
    /// Every asset is a file of its own, directly inside the bundle's `assets` directory. Nothing in that
    /// directory is a directory, so nothing there can be taken for an asset that isn't one, and no name a site
    /// sends is used as a path, so none can name a place outside the bundle.
    func assetLocation(for url: URL) -> URL {
        self.bundleRoot
            .appending(path: "assets", directoryHint: .isDirectory)
            .appending(path: Self.assetFileName(for: url), directoryHint: .notDirectory)
    }

    /// The name of the file an asset is stored in: its URL, spelled so that it can be a file's name, then a
    /// digest of the URL, then the extension the URL has.
    ///
    /// The spelling is for whoever reads a bundle on disk. It can't tell every asset from every other — two
    /// URLs can be spelled the same, and a long one is cut short — so the digest does.
    static func assetFileName(for url: URL) -> String {
        let key = self.assetKey(for: url)

        let spelling = String(
            String.UnicodeScalarView(key.unicodeScalars.map { Self.fileNameCharacters.contains($0) ? $0 : "_" })
                .prefix(Self.fileNameSpellingLength)
        )
        let digest = SHA256.hash(data: Data(key.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()

        let pathExtension = url.pathExtension
        let isPlainExtension =
            (1...8).contains(pathExtension.count)
            && pathExtension.unicodeScalars.allSatisfy { Self.fileNameCharacters.contains($0) }

        return isPlainExtension ? "\(spelling).\(digest).\(pathExtension)" : "\(spelling).\(digest)"
    }

    /// The characters of an asset's URL that are kept in its file's name. All of them are one byte long.
    private static let fileNameCharacters = CharacterSet(
        charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-=,@+"
    )

    /// How much of an asset's URL its file's name spells out. With the digest and the extension, it leaves the
    /// name well under the 255 bytes a file's name can be.
    private static let fileNameSpellingLength = 180

    /// What tells one asset from another: its URL from the host on.
    ///
    /// The editor asks for an asset under a scheme of its own, so the scheme is no part of it. Neither is how
    /// the URL happens to be written — its host in capitals, `..` in its path, a character percent-encoded or
    /// not — since a web view may write it another way when it asks.
    static func assetKey(for url: URL) -> String {
        let url = url.standardized
        let host = url.host(percentEncoded: false)?.lowercased() ?? ""
        let port = url.port.map { ":\($0)" } ?? ""
        let query = url.query(percentEncoded: false).map { "?\($0)" } ?? ""

        return host + port + url.path(percentEncoded: false) + query
    }

    /// Checks whether this bundle contains cached data for the given asset URL.
    ///
    /// - Parameter url: The original remote URL of the asset, or the editor's request for it.
    /// - Returns: `true` if the asset is cached in this bundle, `false` otherwise.
    public func hasAssetData(for url: URL) -> Bool {
        FileManager.default.fileExists(at: self.assetLocation(for: url))
    }

    /// Returns the local file path for a cached asset.
    ///
    /// - Parameter url: The original remote URL of the asset, or the editor's request for it.
    /// - Returns: The local file URL where the asset is stored.
    public func assetDataPath(for url: URL) -> URL {
        self.assetLocation(for: url)
    }

    /// The headers kept from when the asset at `url` was downloaded, if its server sent any worth keeping.
    func headers(for url: URL) -> AssetHeaders? {
        assetHeaders[Self.assetKey(for: url)]
    }

    /// The `Content-Type` the server sent with an asset, for serving it to the editor the way the server did.
    ///
    /// `url` can be the asset's own, or the editor's request for it. `nil` if the server sent none, or the
    /// bundle was stored before this was recorded.
    public func contentType(forAssetAt url: URL) -> String? {
        self.headers(for: url)?.contentType
    }

    /// Reads and returns the cached data for an asset.
    ///
    /// - Parameter url: The original remote URL of the asset.
    /// - Returns: The asset's file contents.
    /// - Throws: `Errors.invalidRequest` if the asset is not in this bundle,
    ///   or a file system error if the file cannot be read.
    public func assetData(for url: URL) throws -> Data {
        let fileURL = assetDataPath(for: url)
        return try Data(contentsOf: fileURL)
    }

    /// Reads the editor representation as a strongly-typed struct.
    ///
    /// The editor representation contains the rewritten script and style tags
    /// with URLs pointing to the local cache via the custom URL scheme.
    ///
    /// - Throws: An error if the file doesn't exist or cannot be decoded.
    func getEditorRepresentation() throws -> EditorRepresentation {
        let path = self.bundleRoot.appending(path: "editor-representation.json")
        let data = try Data(contentsOf: path)
        return try JSONDecoder().decode(EditorRepresentation.self, from: data)
    }

    /// Reads the editor representation as a JSON-serializable dictionary.
    ///
    /// Use this overload when you need to pass the representation to JavaScript.
    ///
    /// - Throws: An error if the file doesn't exist or cannot be parsed.
    func getEditorRepresentation() throws -> Any {
        let path = self.bundleRoot.appending(path: "editor-representation.json")
        let data = try Data(contentsOf: path)
        return try JSONSerialization.jsonObject(with: data)
    }

    /// Saves the editor representation to disk.
    ///
    /// - Parameter representation: The processed script/style tags with rewritten URLs.
    /// - Throws: An error if encoding or writing fails.
    func setEditorRepresentation(_ representation: EditorRepresentation) throws {
        let path = self.bundleRoot.appending(path: "editor-representation.json")
        try JSONEncoder().encode(representation).write(to: path, options: .atomic)
    }

    /// Returns the bundle's manifest as JSON data for storage.
    func dataRepresentation() throws -> Data {
        try JSONEncoder().encode(RawAssetBundle(
            manifest: self.manifest,
            downloadDate: self.downloadDate,
            lastCheckedDate: self.lastCheckedDate,
            assetHeaders: self.assetHeaders.isEmpty ? nil : self.assetHeaders
        ))
    }

    /// Writes the bundle's JSON representation to disk.
    ///
    /// - Parameter path: The file URL where the bundle should be saved.
    /// - Throws: An error if encoding fails or the file cannot be written.
    func writeManifest(to path: URL? = nil, editorRepresentation: EditorRepresentation? = nil) throws {
        try FileManager.default.createDirectory(at: self.bundleRoot, withIntermediateDirectories: true)
        let destination = path ?? self.bundleRoot.appendingPathComponent("manifest.json")
        try self.dataRepresentation().write(to: destination, options: .atomic)

        if let editorRepresentation {
            try setEditorRepresentation(editorRepresentation)
        }
    }

    static let empty = EditorAssetBundle(
        raw: RawAssetBundle(
            manifest: .empty,
            downloadDate: Date()
        ),
        bundleRoot: URL.temporaryDirectory
    )
}

extension EditorAssetBundle: Equatable, Hashable {
    public static func == (lhs: EditorAssetBundle, rhs: EditorAssetBundle) -> Bool {
        lhs.manifest == rhs.manifest && lhs.downloadDate == rhs.downloadDate && lhs.bundleRoot == rhs.bundleRoot
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(manifest)
        hasher.combine(downloadDate)
        hasher.combine(bundleRoot)
    }
}
