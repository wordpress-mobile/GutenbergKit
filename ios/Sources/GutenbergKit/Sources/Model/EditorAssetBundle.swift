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
        /// `nil` in a bundle stored before this field existed.
        var lastCheckedDate: Date?
        /// `nil` in a bundle stored before this field existed.
        var assetHeaders: [String: AssetHeaders]?
    }

    /// The response headers stored with an asset. For now, only its `Content-Type`.
    struct AssetHeaders: Codable, Hashable, Sendable {
        /// The `Content-Type` the server sent. `EditorAssetBundleProvider` serves the asset with it.
        let contentType: String?

        init(contentType: String? = nil) {
            self.contentType = contentType
        }

        /// The headers to store from `response`, or `nil` if it has none of them.
        init?(response: HTTPURLResponse) {
            guard let contentType = response.value(forHTTPHeaderField: "Content-Type") else {
                return nil
            }

            self.init(contentType: contentType)
        }
    }

    /// The checksum of the bundle's manifest. It identifies the manifest, not the bundle.
    ///
    /// Several bundles on disk can share an ID: an `.ignore` refresh whose assets come back different, or a
    /// retry of assets that failed to download, builds a new bundle beside the one it replaces. Bundles with
    /// the same ID have identical manifests, but their assets can differ. Use `==` to tell them apart.
    public var id: String {
        manifest.checksum
    }

    /// The manifest that defines which assets belong to this bundle.
    let manifest: LocalEditorAssetManifest

    /// The date this bundle was created by downloading the manifest contents.
    ///
    /// Used as the bundle's ``lastMatchedDate`` until it has a ``lastCheckedDate``.
    let downloadDate: Date

    /// When the site's manifest was last checked and found to match this bundle. `nil` if that wasn't recorded.
    ///
    /// It isn't part of `==`: it says when the bundle was last confirmed, not what the bundle holds.
    let lastCheckedDate: Date?

    /// The last time the site's manifest is known to have matched this bundle: ``lastCheckedDate``, or
    /// ``downloadDate`` if that's `nil`.
    ///
    /// Decides which of a site's bundles is the latest, and how old a bundle is for the cache policy.
    var lastMatchedDate: Date {
        lastCheckedDate ?? downloadDate
    }

    /// The headers stored from each asset's download, keyed by ``assetKey(for:)``. An asset whose response had
    /// none of them has no entry.
    let assetHeaders: [String: AssetHeaders]

    /// Each asset's `Content-Type`, keyed by ``assetKey(for:)``, for `==` and `hash(into:)`.
    ///
    /// The editor is served each asset with its type, so bundles whose types differ aren't equal. Types are
    /// lowercased and have their spaces removed first, so `text/css; charset=UTF-8` and
    /// `text/css;charset=utf-8` compare equal.
    private var assetContentTypes: [String: String] {
        assetHeaders.compactMapValues { $0.contentType?.lowercased().filter { !$0.isWhitespace } }
    }

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

    /// A copy of this bundle with its `lastCheckedDate` and `assetHeaders` replaced.
    func recording(lastCheckedDate: Date?, assetHeaders: [String: AssetHeaders]) -> EditorAssetBundle {
        EditorAssetBundle(
            raw: RawAssetBundle(
                manifest: self.manifest,
                downloadDate: self.downloadDate,
                lastCheckedDate: lastCheckedDate,
                assetHeaders: assetHeaders
            ),
            bundleRoot: self.bundleRoot
        )
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
    /// Both writing and reading an asset go through this, so they can't disagree about where it is.
    ///
    /// Every asset is a single file directly inside the bundle's `assets` directory, named by
    /// ``assetFileName(for:)``. No part of a URL is used as a path, so no manifest can put a file outside the
    /// bundle, and no URL — not even a site's root — leads to a directory that ``hasAssetData(for:)`` would
    /// take for an asset.
    func assetLocation(for url: URL) -> URL {
        self.bundleRoot
            .appending(path: "assets", directoryHint: .isDirectory)
            .appending(path: Self.assetFileName(for: url), directoryHint: .notDirectory)
    }

    /// The file name an asset is stored under: a readable form of its ``assetKey(for:)``, then a digest of the
    /// key, then the key's file extension, if it has a short, plain one. For example,
    /// `example.com_wp-content_plugins_jetpack_blocks_editor.js_ver=15.2.<digest>.js`.
    ///
    /// The readable part is for people browsing a bundle on disk. It isn't unique — different URLs can map to
    /// the same characters, and a long one is truncated — so the digest keeps names apart.
    static func assetFileName(for url: URL) -> String {
        let key = self.assetKey(for: url)

        let spelling = String(
            String.UnicodeScalarView(key.unicodeScalars.map { Self.fileNameCharacters.contains($0) ? $0 : "_" })
                .prefix(Self.fileNameSpellingLength)
        )
        let digest = SHA256.hash(data: Data(key.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()

        // Taken from the key rather than the URL, so every way of writing the URL gets the same name
        let pathExtension = Self.pathExtension(ofAssetKey: key)
        let isPlainExtension =
            (1...8).contains(pathExtension.count)
            && pathExtension.unicodeScalars.allSatisfy { Self.fileNameCharacters.contains($0) }

        return isPlainExtension ? "\(spelling).\(digest).\(pathExtension)" : "\(spelling).\(digest)"
    }

    /// The file extension in an ``assetKey(for:)``: what follows the last `.` in the last path component,
    /// ignoring the query. Empty if there's none.
    private static func pathExtension(ofAssetKey key: String) -> String {
        let path = key.prefix { $0 != "?" }.drop { $0 != "/" }

        guard
            let name = path.split(separator: "/").last,
            let dot = name.lastIndex(of: "."),
            dot != name.startIndex
        else {
            return ""
        }

        return String(name[name.index(after: dot)...])
    }

    /// The characters kept as they are in an asset's file name; every other character becomes `_`. All are
    /// ASCII, so each is one byte.
    private static let fileNameCharacters = CharacterSet(
        charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-=,@+"
    )

    /// The maximum length of the readable part of an asset's file name. With the digest and extension added,
    /// names stay well under the 255-byte limit.
    private static let fileNameSpellingLength = 180

    /// The key that identifies an asset: its URL without the scheme, normalized.
    ///
    /// The scheme is left out because the editor requests assets through its own `gbk-cache-https` scheme.
    /// The rest is normalized — host lowercased, `.` and `..` resolved, percent-encoding removed — because a
    /// web view may write the same URL differently from the manifest.
    ///
    /// Encoded delimiters stay encoded, as a web view leaves them: `a%2Fb.js` is a single path segment, while
    /// `a/b.js` is `b.js` inside `a`. Decoding the first would turn it into the second, a different asset.
    static func assetKey(for url: URL) -> String {
        let url = Self.resolvingDotSegments(of: url)
        let host = url.host(percentEncoded: false)?.lowercased() ?? ""
        let port = url.port.map { ":\($0)" } ?? ""
        var path = Self.decoded(url.path(percentEncoded: true))
        let query = url.query(percentEncoded: true).map { "?" + Self.decoded($0) } ?? ""

        // A web view drops a `..` at the root, since there's nothing above it, but `URL.standardized` keeps it
        while path.hasPrefix("/../") {
            path.removeFirst(3)
        }

        if path == "/.." {
            path = "/"
        }

        return host + port + path + query
    }

    /// `url` with its `.` and `..` path segments resolved, including ones written as `%2E`. A web view treats
    /// `%2E` as a dot and resolves those segments before it makes the request.
    private static func resolvingDotSegments(of url: URL) -> URL {
        let written = url.absoluteString

        guard written.range(of: "%2E", options: .caseInsensitive) != nil else {
            return url.standardized
        }

        let decodingDots = written.replacingOccurrences(of: "%2E", with: ".", options: .caseInsensitive)
        return (URL(string: decodingDots) ?? url).standardized
    }

    /// `component` with its percent-encoding removed, except for `%` and the delimiters in ``encodedDelimiters``.
    /// Those stay encoded, because decoding them would change where the URL divides.
    ///
    /// If the decoded bytes aren't valid UTF-8 — a name encoded in Latin-1, say — decoding fails. The
    /// component then stays encoded, with its hex digits uppercased so that `%e9` and `%E9` give the same key.
    private static func decoded(_ component: String) -> String {
        guard component.contains("%") else {
            return component
        }

        // Escape each delimiter's `%` as `%25`, so that decoding leaves the delimiter encoded
        let escapingDelimiters = Self.encodedDelimiters.reduce(component) { component, delimiter in
            component.replacingOccurrences(of: delimiter, with: "%25" + delimiter.dropFirst(), options: .caseInsensitive)
        }

        return escapingDelimiters.removingPercentEncoding ?? Self.withEncodingInCapitals(component)
    }

    /// `component` with the two hex digits after each `%` uppercased: `%e9` and `%E9` are the same byte.
    private static func withEncodingInCapitals(_ component: String) -> String {
        var result = ""
        var encodedCharactersLeft = 0

        for character in component {
            if character == "%" {
                encodedCharactersLeft = 2
                result.append(character)
            } else if encodedCharactersLeft > 0 {
                encodedCharactersLeft -= 1
                result += character.uppercased()
            } else {
                result.append(character)
            }
        }

        return result
    }

    /// The encoded forms of `%` and of the characters that delimit a URL's path and query. `%25` comes first,
    /// so that ``decoded(_:)`` doesn't re-escape the `%25` it writes for the others.
    private static let encodedDelimiters = ["%25", "%2F", "%3F", "%23", "%26", "%3D", "%2B"]

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

    @available(*, deprecated, message: "An asset's path can no longer escape its bundle, so this always returns `true`. Remove the check.")
    public func isValidAssetPath(for url: URL) -> Bool {
        true
    }

    /// The headers stored for the asset at `url`, if any.
    func headers(for url: URL) -> AssetHeaders? {
        assetHeaders[Self.assetKey(for: url)]
    }

    /// The `Content-Type` the server sent with the asset at `url`, so the editor can be served the same type.
    ///
    /// `url` can be the asset's URL or the editor's request for it. `nil` if the server sent none, the bundle
    /// doesn't have the asset, or the bundle was stored before headers were recorded.
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
        lhs.manifest == rhs.manifest
            && lhs.downloadDate == rhs.downloadDate
            && (lhs.assetHeaders == rhs.assetHeaders || lhs.assetContentTypes == rhs.assetContentTypes)
            && lhs.bundleRoot == rhs.bundleRoot
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(manifest)
        hasher.combine(downloadDate)
        hasher.combine(assetContentTypes)
        hasher.combine(bundleRoot)
    }
}
