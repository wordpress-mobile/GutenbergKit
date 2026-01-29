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
public struct EditorAssetBundle: Sendable, Equatable, Hashable {


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
    /// Used to determine which bundle is most recent when multiple bundles exist.
    let downloadDate: Date

    /// The number of assets stored in this bundle.
    public var assetCount: Int {
        manifest.assetUrls.count
    }

    let bundleRoot: URL

    init(raw: RawAssetBundle, bundleRoot: URL) {
        self.manifest = raw.manifest
        self.downloadDate = raw.downloadDate
        self.bundleRoot = bundleRoot
    }

    init(manifest: LocalEditorAssetManifest, downloadDate: Date = Date(), bundleRoot: URL) throws {
        self.manifest = manifest
        self.downloadDate = downloadDate
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

    /// Checks whether the given asset URL resolves to a valid path within the bundle root.
    ///
    /// Use this method to validate URLs before calling `assetDataPath(for:)` or `hasAssetData(for:)`
    /// to avoid precondition failures for paths that escape the bundle root (e.g., plugin assets
    /// referenced in CSS that weren't downloaded into the bundle).
    ///
    /// - Parameter url: The asset URL to validate.
    /// - Returns: `true` if the URL resolves to a path within the bundle root, `false` otherwise.
    public func isValidAssetPath(for url: URL) -> Bool {
        let path = url.path(percentEncoded: false)
        let bundlePath = self.bundleRoot.appending(rawPath: path).standardizedFileURL
        let bundleRootPath = self.bundleRoot.standardizedFileURL.path
        return bundlePath.path.hasPrefix(bundleRootPath + "/") || bundlePath.path == bundleRootPath
    }

    /// Checks whether this bundle contains cached data for the given asset URL.
    ///
    /// - Parameter url: The original remote URL of the asset.
    /// - Returns: `true` if the asset is cached in this bundle, `false` otherwise.
    /// - Precondition: The URL path must not escape the bundle root directory.
    ///   Use `isValidAssetPath(for:)` to check validity before calling this method.
    public func hasAssetData(for url: URL) -> Bool {
        FileManager.default.fileExists(at: self.assetDataPath(for: url))
    }

    /// Returns the local file path for a cached asset.
    ///
    /// - Parameter url: The original remote URL of the asset.
    /// - Returns: The local file URL where the asset is stored.
    /// - Precondition: The URL path must not escape the bundle root directory.
    public func assetDataPath(for url: URL) -> URL {
        let path = url.path(percentEncoded: false)
        let bundlePath = self.bundleRoot.appending(rawPath: path).standardizedFileURL
        let bundleRootPath = self.bundleRoot.standardizedFileURL.path

        precondition(
            bundlePath.path.hasPrefix(bundleRootPath + "/") || bundlePath.path == bundleRootPath,
            "Asset path escapes bundle root: \(path)"
        )

        return bundlePath
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
            downloadDate: self.downloadDate
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

    /// Copies the bundle to the given directoy.
    ///
    /// APFS makes this instant and zero-cost.
    func copy(to destination: URL) throws -> EditorAssetBundle {

        // Don't bother persisting an empty bundle
        guard self != .empty else {
            return .empty
        }

        if FileManager.default.directoryExists(at: destination) {
            try FileManager.default.removeItem(at: destination)
        }

        let destinationParent = destination.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: destinationParent, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: self.bundleRoot, to: destination)

        return try EditorAssetBundle(url: destination.appending(path: "manifest.json"))
    }

    static let empty: EditorAssetBundle = EditorAssetBundle(
        raw: RawAssetBundle(
            manifest: .empty,
            downloadDate: Date()
        ),
        bundleRoot: URL.temporaryDirectory
    )
}
