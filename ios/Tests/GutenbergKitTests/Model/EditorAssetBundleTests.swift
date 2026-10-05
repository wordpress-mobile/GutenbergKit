import Foundation
import Testing

@testable import GutenbergKit

@Suite
struct EditorAssetBundleTests {

    // MARK: - Initialization Tests
    @Test("Default initialization creates bundle with empty manifest")
    func defaultInitializationCreatesEmptyManifest() {
        let bundle = makeBundle()

        #expect(bundle.manifest.scripts.isEmpty)
        #expect(bundle.manifest.styles.isEmpty)
        #expect(bundle.manifest.allowedBlockTypes.isEmpty)
    }

    @Test("Default initialization sets downloadDate to current time")
    func defaultInitializationSetsDownloadDate() {
        let beforeCreation = Date()
        let bundle = makeBundle()
        let afterCreation = Date()

        #expect(bundle.downloadDate >= beforeCreation)
        #expect(bundle.downloadDate <= afterCreation)
    }

    @Test("Initialization with manifest preserves manifest data")
    func initializationWithManifestPreservesData() throws {
        let manifest = try createManifest(
            scripts: "<script src=\"https://example.com/app.js\"></script>",
            styles: "<link rel=\"stylesheet\" href=\"https://example.com/style.css\">",
            blockTypes: ["core/paragraph", "core/heading"]
        )

        let bundle = makeBundle(manifest: manifest)

        #expect(bundle.manifest.scripts.count == 1)
        #expect(bundle.manifest.styles.count == 1)
        #expect(bundle.manifest.allowedBlockTypes == ["core/paragraph", "core/heading"])
    }

    @Test("Initialization with custom downloadDate preserves date")
    func initializationWithCustomDatePreservesDate() {
        let customDate = Date(timeIntervalSince1970: 1_000_000)
        let bundle = makeBundle(downloadDate: customDate)

        #expect(bundle.downloadDate == customDate)
    }

    // MARK: - ID Tests

    @Test("Bundle ID equals manifest checksum")
    func bundleIdEqualsManifestChecksum() throws {
        let manifest = try createManifest(blockTypes: ["core/paragraph"])
        let bundle = makeBundle(manifest: manifest)

        #expect(bundle.id == manifest.checksum)
    }

    @Test("Empty bundle has empty ID")
    func emptyBundleHasIdEmpty() {
        /// The bundle needs a non-nil ID so that it can be read back off the disk
        let bundle = makeBundle()
        #expect(bundle.id == "empty")
    }

    @Test("Different manifests produce different bundle IDs")
    func differentManifestsProduceDifferentIds() throws {
        let manifest1 = try createManifest(blockTypes: ["core/paragraph"])
        let manifest2 = try createManifest(blockTypes: ["core/heading"])

        let bundle1 = makeBundle(manifest: manifest1)
        let bundle2 = makeBundle(manifest: manifest2)

        #expect(bundle1.id != bundle2.id)
    }

    @Test("Same manifest data produces same bundle ID")
    func sameManifestDataProducesSameId() throws {
        let json = """
      {
          "scripts": "",
          "styles": "",
          "allowed_block_types": ["core/paragraph"]
      }
      """

        let manifest1 = try LocalEditorAssetManifest.from(data: Data(json.utf8))
        let manifest2 = try LocalEditorAssetManifest.from(data: Data(json.utf8))

        let bundle1 = makeBundle(manifest: manifest1)
        let bundle2 = makeBundle(manifest: manifest2)

        #expect(bundle1.id == bundle2.id)
    }

    // MARK: - assetCount Tests

    @Test("assetCount returns zero for empty bundle")
    func assetCountReturnsZeroForEmptyBundle() {
        let bundle = makeBundle()
        #expect(bundle.assetCount == 0)
    }

    @Test("assetCount reflects manifest asset URLs")
    func assetCountReflectsManifestAssetUrls() throws {
        let manifest = try createManifest(
            scripts: "<script src=\"https://example.com/script1.js\"></script><script src=\"https://example.com/script2.js\"></script>",
            styles: "<link rel=\"stylesheet\" href=\"https://example.com/style.css\">"
        )
        let bundle = makeBundle(manifest: manifest)

        #expect(bundle.assetCount == 3)
    }

    // MARK: - Codable Tests

    @Test("Bundle can be encoded and decoded")
    func bundleCanBeEncodedAndDecoded() throws {
        let manifest = try createManifest(
            scripts: "<script src=\"https://example.com/app.js\"></script>",
            blockTypes: ["core/paragraph", "core/image"]
        )
        let originalBundle = makeBundle(manifest: manifest)

        let rawBundle = EditorAssetBundle.RawAssetBundle(
            manifest: originalBundle.manifest,
            downloadDate: originalBundle.downloadDate
        )

        let encoded = try JSONEncoder().encode(rawBundle)
        let decoded = try JSONDecoder().decode(EditorAssetBundle.RawAssetBundle.self, from: encoded)

        #expect(decoded.manifest.checksum == originalBundle.manifest.checksum)
        #expect(decoded.downloadDate == originalBundle.downloadDate)
        #expect(decoded.manifest.allowedBlockTypes == originalBundle.manifest.allowedBlockTypes)
    }

    @Test("Bundle preserves rawScripts through encoding")
    func bundlePreservesRawScriptsThroughEncoding() throws {
        let rawScripts =
            "<script src=\"https://example.com/app.js\"></script><script>console.log('inline');</script>"
        let manifest = try createManifest(scripts: rawScripts)
        let originalBundle = makeBundle(manifest: manifest)

        let rawBundle = EditorAssetBundle.RawAssetBundle(
            manifest: originalBundle.manifest,
            downloadDate: originalBundle.downloadDate
        )

        let encoded = try JSONEncoder().encode(rawBundle)
        let decoded = try JSONDecoder().decode(EditorAssetBundle.RawAssetBundle.self, from: encoded)

        #expect(decoded.manifest.rawScripts == originalBundle.manifest.rawScripts)
    }

    @Test("Bundle preserves rawStyles through encoding")
    func bundlePreservesRawStylesThroughEncoding() throws {
        let rawStyles =
            "<link rel=\"stylesheet\" href=\"https://example.com/style.css\"><style>body {}</style>"
        let manifest = try createManifest(styles: rawStyles)
        let originalBundle = makeBundle(manifest: manifest)

        let rawBundle = EditorAssetBundle.RawAssetBundle(
            manifest: originalBundle.manifest,
            downloadDate: originalBundle.downloadDate
        )

        let encoded = try JSONEncoder().encode(rawBundle)
        let decoded = try JSONDecoder().decode(EditorAssetBundle.RawAssetBundle.self, from: encoded)

        #expect(decoded.manifest.rawStyles == originalBundle.manifest.rawStyles)
    }

    @Test("Bundle keeps its assets' headers through writing and reading")
    func bundleKeepsAssetHeadersThroughWritingAndReading() throws {
        let asset = URL(string: "https://example.com/app.js")!
        let manifest = try createManifest(scripts: "<script src=\"https://example.com/app.js\"></script>")
        let headers = EditorAssetBundle.AssetHeaders(
            contentType: "application/javascript; charset=utf-8",
            etag: "\"first\"",
            lastModified: "Wed, 30 Sep 2026 21:43:35 GMT"
        )
        let bundle = try EditorAssetBundle(
            manifest: manifest,
            assetHeaders: [EditorAssetBundle.assetKey(for: asset): headers],
            bundleRoot: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        )
        try bundle.writeManifest(editorRepresentation: .empty)

        let loaded = try EditorAssetBundle(url: bundle.bundleRoot.appending(path: "manifest.json"))

        #expect(loaded.headers(for: asset) == headers)
    }

    /// The editor asks for an asset under a scheme of its own, and is served it as the site's server would.
    @Test(
        "contentType(forAssetAt:) gives the type the server sent, for the asset's URL or the editor's request for it",
        arguments: [
            "https://example.com/wp-content/app.js?ver=1",
            "gbk-cache-https://example.com/wp-content/app.js?ver=1",
        ]
    )
    func contentTypeIsGivenForAssetOrRequest(url: String) throws {
        let manifest = try createManifest(
            scripts: "<script src=\"https://example.com/wp-content/app.js?ver=1\"></script>"
        )
        let bundle = try EditorAssetBundle(
            manifest: manifest,
            assetHeaders: [
                "example.com/wp-content/app.js?ver=1": .init(contentType: "application/javascript; charset=utf-8"),
                "example.com/wp-content/other.js?ver=1": .init(contentType: "text/plain"),
            ],
            bundleRoot: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        )

        #expect(bundle.contentType(forAssetAt: try #require(URL(string: url))) == "application/javascript; charset=utf-8")
    }

    @Test("contentType(forAssetAt:) gives none for an asset whose server sent none, or one the bundle doesn't have")
    func contentTypeIsNilWhenNotRecorded() throws {
        let manifest = try createManifest(scripts: "<script src=\"https://example.com/app.js\"></script>")
        let bundle = try EditorAssetBundle(
            manifest: manifest,
            assetHeaders: ["example.com/app.js": .init(etag: "\"first\"")],
            bundleRoot: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        )

        #expect(bundle.contentType(forAssetAt: try #require(URL(string: "gbk-cache-https://example.com/app.js"))) == nil)
        #expect(bundle.contentType(forAssetAt: try #require(URL(string: "gbk-cache-https://example.com/other.js"))) == nil)
        // The same path on another host is another asset
        #expect(bundle.contentType(forAssetAt: try #require(URL(string: "gbk-cache-https://cdn.example.com/app.js"))) == nil)
    }

    @Test("Bundle stored before its assets' headers were recorded has none")
    func bundleStoredWithoutAssetHeadersHasNone() throws {
        let manifest = try createManifest(scripts: "<script src=\"https://example.com/app.js\"></script>")
        let stored = try JSONEncoder().encode(["manifest": manifest])
        var object = try #require(try JSONSerialization.jsonObject(with: stored) as? [String: Any])
        object["downloadDate"] = 0

        let bundle = try EditorAssetBundle(
            data: try JSONSerialization.data(withJSONObject: object),
            bundleRoot: FileManager.default.temporaryDirectory
        )

        #expect(bundle.headers(for: URL(string: "https://example.com/app.js")!) == nil)
        #expect(bundle.assetsNotRefreshed.isEmpty)
    }

    @Test("Bundle keeps which of its assets weren't refreshed through writing and reading")
    func bundleKeepsAssetsNotRefreshedThroughWritingAndReading() throws {
        let asset = URL(string: "https://example.com/app.js")!
        let manifest = try createManifest(scripts: "<script src=\"https://example.com/app.js\"></script>")
        let bundle = try EditorAssetBundle(
            manifest: manifest,
            assetsNotRefreshed: [EditorAssetBundle.assetKey(for: asset)],
            bundleRoot: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        )
        try bundle.writeManifest(editorRepresentation: .empty)

        let loaded = try EditorAssetBundle(url: bundle.bundleRoot.appending(path: "manifest.json"))

        #expect(loaded.assetsNotRefreshed == [EditorAssetBundle.assetKey(for: asset)])
        // It says how the bundle came to be, not what it holds
        #expect(
            loaded
                == (try EditorAssetBundle(
                    manifest: manifest,
                    downloadDate: loaded.downloadDate,
                    bundleRoot: loaded.bundleRoot
                ))
        )
    }

    // MARK: - URL Initialization Tests

    @Test("Bundle can be initialized from URL")
    func bundleCanBeInitializedFromUrl() throws {
        let manifest = try createManifest(blockTypes: ["core/paragraph"])
        let originalBundle = makeBundle(manifest: manifest)

        // Create temp directory structure
        let tempDir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        // Write manifest.json
        let manifestURL = tempDir.appending(path: "manifest.json")
        let rawBundle = EditorAssetBundle.RawAssetBundle(
            manifest: originalBundle.manifest,
            downloadDate: originalBundle.downloadDate
        )
        let bundleToWrite = EditorAssetBundle(raw: rawBundle, bundleRoot: tempDir)
        try bundleToWrite.writeManifest(editorRepresentation: .empty)

        // Initialize from URL
        let loadedBundle = try EditorAssetBundle(url: manifestURL)

        #expect(loadedBundle.id == originalBundle.id)
        #expect(loadedBundle.manifest.allowedBlockTypes == originalBundle.manifest.allowedBlockTypes)

        // Clean up
        try? FileManager.default.removeItem(at: tempDir)
    }

    @Test("Bundle initialization from invalid URL throws error")
    func bundleInitializationFromInvalidUrlThrows() {
        let invalidURL = URL(fileURLWithPath: "/nonexistent/path/bundle.json")

        #expect(throws: Error.self) {
            _ = try EditorAssetBundle(url: invalidURL)
        }
    }

    @Test("Bundle initialization from invalid JSON throws error")
    func bundleInitializationFromInvalidJsonThrows() throws {
        let tempURL = FileManager.default.temporaryDirectory.appending(
            path: "\(UUID().uuidString).json")
        try Data("invalid json".utf8).write(to: tempURL)

        #expect(throws: Error.self) {
            _ = try EditorAssetBundle(url: tempURL)
        }

        // Clean up
        try? FileManager.default.removeItem(at: tempURL)
    }

    // MARK: - hasAssetData Tests

    @Test("hasAssetData returns false for non-existent file")
    func hasAssetDataReturnsFalseForNonExistentFile() {
        let bundle = makeBundle()
        let url = URL(string: "https://example.com/nonexistent.js")!

        #expect(!bundle.hasAssetData(for: url))
    }

    @Test("hasAssetData returns true when the asset's file exists")
    func hasAssetDataReturnsTrueWhenFileExists() throws {
        let tempDir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let bundle = makeBundle(bundleRoot: tempDir)
        let url = URL(string: "https://example.com/wp-content/plugins/script.js")!
        try write("test", to: bundle.assetDataPath(for: url))

        #expect(bundle.hasAssetData(for: url))
    }

    // MARK: - Asset location Tests

    /// The bundle's own directory is there, and it isn't an asset.
    @Test("hasAssetData returns false for a link to a site's root")
    func hasAssetDataReturnsFalseForRootPathLink() throws {
        let tempDir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let bundle = makeBundle(bundleRoot: tempDir)

        #expect(!bundle.hasAssetData(for: try #require(URL(string: "https://s0.wp.com/?custom-css=1&csblog=1"))))
    }

    @Test(
        "hasAssetData returns false for a link to a directory an asset is under",
        arguments: ["https://example.com/wp-content/plugins/", "https://example.com/wp-content"]
    )
    func hasAssetDataReturnsFalseForDirectoryOfAnAsset(url: String) throws {
        let tempDir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let bundle = makeBundle(bundleRoot: tempDir)
        let asset = try #require(URL(string: "https://example.com/wp-content/plugins/script.js"))
        try write("test", to: bundle.assetDataPath(for: asset))

        #expect(bundle.hasAssetData(for: asset))
        #expect(!bundle.hasAssetData(for: try #require(URL(string: url))))
    }

    @Test(
        "assets that differ in their host or their query are stored apart",
        arguments: [
            "https://cdn.example.com/wp-content/app.js?ver=1",
            "https://example.com/wp-content/app.js?ver=2",
            "https://example.com/wp-content/app.js",
        ]
    )
    func assetsThatDifferInHostOrQueryAreStoredApart(other: String) throws {
        let bundle = makeBundle()
        let asset = try #require(URL(string: "https://example.com/wp-content/app.js?ver=1"))

        #expect(bundle.assetDataPath(for: try #require(URL(string: other))) != bundle.assetDataPath(for: asset))
    }

    /// A name that's percent-encoded but isn't UTF-8 — a directory named in Latin-1, say — decodes to
    /// nothing at all. Its URL is told apart as it's written instead.
    @Test(
        "assets whose URLs are encoded as something other than text are stored apart",
        arguments: [
            ("https://example.com/caf%E9/a.js", "https://example.com/caf%E9/b.css"),
            ("https://example.com/caf%E9/a.js", "https://example.com/th%E9/a.js"),
            ("https://example.com/a.js?x=caf%E9", "https://example.com/a.js?x=th%E9"),
            ("https://example.com/a.js?x=caf%E9", "https://example.com/a.js"),
        ]
    )
    func assetsWithEncodingThatIsNotTextAreStoredApart(first: String, second: String) throws {
        let bundle = makeBundle()

        #expect(
            bundle.assetDataPath(for: try #require(URL(string: first)))
                != bundle.assetDataPath(for: try #require(URL(string: second)))
        )
    }

    /// A character that divides a URL up means something else when it's encoded: `a%2Fb.js` is one file's
    /// name, and `a/b.js` is a file in a directory.
    @Test(
        "assets whose URLs differ in whether a dividing character is encoded are stored apart",
        arguments: [
            ("https://example.com/a%2Fb/app.js", "https://example.com/a/b/app.js"),
            ("https://example.com/a%3Fb.js", "https://example.com/a?b.js"),
            ("https://example.com/app.js?x=a%26y%3D1", "https://example.com/app.js?x=a&y=1"),
            ("https://example.com/app.js?x=a%2Bb", "https://example.com/app.js?x=a+b"),
            ("https://example.com/100%25.js", "https://example.com/100%2525.js"),
        ]
    )
    func assetsThatDifferInEncodedDelimitersAreStoredApart(first: String, second: String) throws {
        let bundle = makeBundle()

        #expect(
            bundle.assetDataPath(for: try #require(URL(string: first)))
                != bundle.assetDataPath(for: try #require(URL(string: second)))
        )
    }

    /// However else a URL is written, it's the same asset: a web view may write it another way.
    @Test(
        "assets whose URLs differ only in how they're written are stored together",
        arguments: [
            ("https://example.com/my%20plugin/app.js", "https://example.com/my plugin/app.js"),
            ("https://example.com/caf%C3%A9/app.js", "https://example.com/café/app.js"),
            ("https://example.com/a%2fb/app.js", "https://example.com/a%2Fb/app.js"),
            ("https://example.com/app.js?x=%7B1%7D", "https://example.com/app.js?x={1}"),
            ("https://example.com/%61pp.js", "https://example.com/app.js"),
            ("https://example.com/a/%2E%2E/app.js", "https://example.com/app.js"),
            ("https://example.com/a/%2e/app.js", "https://example.com/a/app.js"),
            // What can't be decoded is still the same bytes, whichever case they're written in
            ("https://example.com/caf%e9/app.js", "https://example.com/caf%E9/app.js"),
            // The whole of a file's name comes of what the URL leads to, its extension included
            ("https://example.com/caf%E9/../app.js", "https://example.com/app.js"),
            // Nothing is above a site's root, so going back from there goes nowhere
            ("https://example.com/a/../../app.js", "https://example.com/app.js"),
            ("https://example.com/%2E%2E/%2E%2E/app.js", "https://example.com/app.js"),
        ]
    )
    func assetsThatDifferOnlyInHowTheyAreWrittenAreStoredTogether(first: String, second: String) throws {
        let bundle = makeBundle()

        #expect(
            bundle.assetDataPath(for: try #require(URL(string: first)))
                == bundle.assetDataPath(for: try #require(URL(string: second)))
        )
    }

    // MARK: - Earlier Layout Tests

    @Test("legacyAssetLocation gives the file at an asset's URL path, where a bundle used to keep it")
    func legacyAssetLocationFindsFileAtURLPath() throws {
        let bundle = makeBundle(bundleRoot: URL.randomTemporaryDirectory.appending(path: "bundle"))
        let asset = try #require(URL(string: "https://example.com/wp-content/plugins/a%20plugin/app.js?ver=1"))
        let file = bundle.bundleRoot.appending(path: "wp-content/plugins/a plugin/app.js")
        try write("content", to: file)

        let location = try #require(bundle.legacyAssetLocation(for: asset))

        #expect(try Data(contentsOf: location) == Data("content".utf8))
    }

    /// Only a file inside the bundle that isn't one of the bundle's own can be an asset it kept.
    @Test(
        "legacyAssetLocation gives nothing where a bundle never kept an asset",
        arguments: [
            "https://example.com/wp-content/missing.js",
            "https://example.com/",
            "https://example.com/wp-content/",
            "https://example.com/wp-content/../../outside.js",
            "https://example.com/%2E%2E/outside.js",
            "https://example.com/manifest.json",
            "https://example.com/editor-representation.json",
            // The same files, on a volume that doesn't tell capitals apart
            "https://example.com/Manifest.json",
            "https://example.com/EDITOR-REPRESENTATION.JSON",
        ]
    )
    func legacyAssetLocationIsNilWhereNoAssetWasKept(link: String) throws {
        let directory = URL.randomTemporaryDirectory
        let bundle = makeBundle(bundleRoot: directory.appending(path: "bundle"))
        try write("content", to: bundle.bundleRoot.appending(path: "wp-content/app.js"))
        try write("{}", to: bundle.bundleRoot.appending(path: "manifest.json"))
        try write("{}", to: bundle.bundleRoot.appending(path: "editor-representation.json"))
        try write("outside", to: directory.appending(path: "outside.js"))

        #expect(bundle.legacyAssetLocation(for: try #require(URL(string: link))) == nil)
    }

    /// A bundle on disk can be read by someone looking for an asset.
    @Test("an asset's file is named for its URL")
    func assetFileIsNamedForItsURL() throws {
        let bundle = makeBundle()
        let asset = try #require(URL(string: "https://example.com/wp-content/plugins/script.js?ver=1.2"))

        let name = bundle.assetDataPath(for: asset).lastPathComponent

        #expect(name.hasPrefix("example.com_wp-content_plugins_script.js_ver=1.2."))
        #expect(name.hasSuffix(".js"))
    }

    /// Only a path leads to a file with an extension. A query can have a `/` and a `.` in it too.
    @Test("an asset's file takes no extension from its URL's query")
    func assetFileTakesNoExtensionFromQuery() throws {
        let asset = try #require(URL(string: "https://example.com?load=a/b.js"))

        #expect(!EditorAssetBundle.assetFileName(for: asset).hasSuffix(".js"))
    }

    @Test("an asset's file name fits the file system however long its URL is, and still tells assets apart")
    func assetFileNameFitsFileSystem() throws {
        let bundle = makeBundle()
        let concatenated = String(repeating: "/wp-content/plugins/a-plugin/build/block.js,", count: 40)
        let first = try #require(URL(string: "https://s0.wp.com/_static/??\(concatenated)/first.js"))
        let second = try #require(URL(string: "https://s0.wp.com/_static/??\(concatenated)/second.js"))

        let firstName = bundle.assetDataPath(for: first).lastPathComponent
        let secondName = bundle.assetDataPath(for: second).lastPathComponent

        #expect(firstName.utf8.count <= 255)
        #expect(secondName.utf8.count <= 255)
        #expect(firstName != secondName)
    }

    /// A manifest is whatever the site sends. No name in it is used as a path, so none can put an asset
    /// anywhere else, and nothing among the assets is a directory.
    @Test(
        "every asset is a file directly inside the bundle's assets directory",
        arguments: [
            "https://example.com/wp-content/plugins/script.js",
            "https://example.com/../../../etc/passwd",
            "https://example.com/%2e%2e/%2e%2e/etc/passwd",
            "https://example.com/wp-content/../../escaped.js",
            "https://../escaped.js",
            "https://example.com/",
            "https://example.com",
            "https://example.com/?custom-css=1",
            "https://example.com/a%2Fb/..%2F..%2Fescaped.js",
            "https://example.com/wp-content/plugins/",
        ]
    )
    func everyAssetIsAFileDirectlyInsideAssets(url: String) throws {
        let tempDir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let bundle = makeBundle(bundleRoot: tempDir)

        let location = bundle.assetDataPath(for: try #require(URL(string: url)))

        #expect(location.deletingLastPathComponent().standardizedFileURL.path == tempDir.appending(path: "assets").standardizedFileURL.path)
        #expect(location.standardizedFileURL.lastPathComponent == location.lastPathComponent)
        #expect(![".", ".."].contains(location.lastPathComponent))
        #expect(!location.lastPathComponent.contains("/"))
    }

    /// The editor asks for an asset under a scheme of its own, with the URL written the way a web view writes it.
    @Test(
        "the editor's request for an asset finds the asset",
        arguments: [
            ("https://example.com/wp-content/app.js?ver=1", "gbk-cache-https://example.com/wp-content/app.js?ver=1"),
            ("https://Example.com/wp-content/app.js", "gbk-cache-https://example.com/wp-content/app.js"),
            ("https://example.com/wp-content/plugins/../app.js", "gbk-cache-https://example.com/wp-content/app.js"),
            ("https://example.com/my%20plugin/app.js", "gbk-cache-https://example.com/my%20plugin/app.js"),
            ("https://example.com/?custom-css=1", "gbk-cache-https://example.com/?custom-css=1"),
        ]
    )
    func requestForAssetFindsAsset(asset: String, request: String) throws {
        let bundle = makeBundle()

        #expect(
            bundle.assetDataPath(for: try #require(URL(string: request)))
                == bundle.assetDataPath(for: try #require(URL(string: asset)))
        )
    }

    // MARK: - assetData Tests

    @Test("assetData returns data for existing file")
    func assetDataReturnsDataForExistingFile() throws {
        let tempDir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let testContent = "console.log('test');"
        let bundle = makeBundle(bundleRoot: tempDir)

        let requestUrl = URL(string: "https://example.com/script.js")!
        try write(testContent, to: bundle.assetDataPath(for: requestUrl))
        let data = try bundle.assetData(for: requestUrl)

        #expect(String(data: data, encoding: .utf8) == testContent)

        // Clean up
        try? FileManager.default.removeItem(at: tempDir)
    }

    @Test("assetData throws when file doesn't exist")
    func assetDataThrowsWhenFileDoesntExist() {
        let bundle = makeBundle()
        let url = URL(string: "https://example.com/nonexistent.js")!

        #expect(throws: Error.self) {
            _ = try bundle.assetData(for: url)
        }
    }

    // MARK: - Equatable Tests

    @Test("Equal bundles are equal")
    func equalBundlesAreEqual() throws {
        let manifest = try createManifest(blockTypes: ["core/paragraph"])
        let date = Date(timeIntervalSince1970: 1_700_000_000)

        let bundle1 = makeBundle(manifest: manifest, downloadDate: date)
        let bundle2 = makeBundle(manifest: manifest, downloadDate: date)

        #expect(bundle1 == bundle2)
    }

    @Test("Bundles with different manifests are not equal")
    func bundlesWithDifferentManifestsNotEqual() throws {
        let manifest1 = try createManifest(blockTypes: ["core/paragraph"])
        let manifest2 = try createManifest(blockTypes: ["core/heading"])

        let bundle1 = makeBundle(manifest: manifest1)
        let bundle2 = makeBundle(manifest: manifest2)

        #expect(bundle1 != bundle2)
    }

    /// An editor is served each asset with the headers its bundle holds for it.
    @Test("Bundles that hold different headers for their assets are not equal")
    func bundlesWithDifferentAssetHeadersNotEqual() throws {
        let manifest = try createManifest(scripts: "<script src=\"https://example.com/app.js\"></script>")
        let key = EditorAssetBundle.assetKey(for: URL(string: "https://example.com/app.js")!)
        let date = Date()
        let root = URL.randomTemporaryDirectory

        let plain = try EditorAssetBundle(
            manifest: manifest,
            downloadDate: date,
            assetHeaders: [key: .init(contentType: "text/plain")],
            bundleRoot: root
        )
        let script = try EditorAssetBundle(
            manifest: manifest,
            downloadDate: date,
            assetHeaders: [key: .init(contentType: "application/javascript")],
            bundleRoot: root
        )

        #expect(plain != script)
        #expect(plain.hashValue != script.hashValue)
    }

    /// A server can write the same type differently from one answer to the next.
    @Test("Bundles that differ only in how their assets' types are written are equal")
    func bundlesWithDifferentlyWrittenContentTypesAreEqual() throws {
        let manifest = try createManifest(scripts: "<script src=\"https://example.com/app.js\"></script>")
        let key = EditorAssetBundle.assetKey(for: URL(string: "https://example.com/app.js")!)
        let date = Date()
        let root = URL.randomTemporaryDirectory

        let first = try EditorAssetBundle(
            manifest: manifest,
            downloadDate: date,
            assetHeaders: [key: .init(contentType: "text/css; charset=UTF-8")],
            bundleRoot: root
        )
        let second = try EditorAssetBundle(
            manifest: manifest,
            downloadDate: date,
            assetHeaders: [key: .init(contentType: "text/css;charset=utf-8")],
            bundleRoot: root
        )

        #expect(first == second)
        #expect(first.hashValue == second.hashValue)
    }

    /// What tells one version of an asset from another is for asking its server, not for an editor. A
    /// server can send a new one with the same file.
    @Test("Bundles that differ only in how their assets' servers tell versions apart are equal")
    func bundlesWithDifferentValidatorsAreEqual() throws {
        let manifest = try createManifest(scripts: "<script src=\"https://example.com/app.js\"></script>")
        let key = EditorAssetBundle.assetKey(for: URL(string: "https://example.com/app.js")!)
        let date = Date()
        let root = URL.randomTemporaryDirectory

        let first = try EditorAssetBundle(
            manifest: manifest,
            downloadDate: date,
            assetHeaders: [key: .init(contentType: "application/javascript", etag: "\"first\"")],
            bundleRoot: root
        )
        let second = try EditorAssetBundle(
            manifest: manifest,
            downloadDate: date,
            assetHeaders: [
                key: .init(
                    contentType: "application/javascript",
                    etag: "\"second\"",
                    lastModified: "Wed, 30 Sep 2026 21:43:35 GMT"
                )
            ],
            bundleRoot: root
        )

        #expect(first == second)
        #expect(first.hashValue == second.hashValue)
    }

    @Test("Bundles with different downloadDates are not equal")
    func bundlesWithDifferentDatesNotEqual() throws {
        let manifest = try createManifest(blockTypes: ["core/paragraph"])

        let bundle1 = makeBundle(manifest: manifest, downloadDate: Date(timeIntervalSince1970: 1000))
        let bundle2 = makeBundle(manifest: manifest, downloadDate: Date(timeIntervalSince1970: 2000))

        #expect(bundle1 != bundle2)
    }

    // MARK: - Integration Tests

    @Test("Bundle round-trip through file system preserves all data")
    func bundleRoundTripPreservesAllData() throws {
        let manifest = try createManifest(
            scripts: "<script src=\"https://example.com/app.js\"></script>",
            styles: "<link rel=\"stylesheet\" href=\"https://example.com/style.css\">",
            blockTypes: ["core/paragraph", "core/heading", "jetpack/ai-assistant"]
        )
        let customDate = Date(timeIntervalSince1970: 1_700_000_000)
        let originalBundle = makeBundle(manifest: manifest, downloadDate: customDate)

        // Create temp directory
        let tempDir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        // Write to file
        let tempURL = tempDir.appending(path: "manifest.json")
        let rawBundle = EditorAssetBundle.RawAssetBundle(
            manifest: originalBundle.manifest,
            downloadDate: originalBundle.downloadDate
        )
        let bundleToWrite = EditorAssetBundle(raw: rawBundle, bundleRoot: tempDir)
        try bundleToWrite.writeManifest(to: tempURL, editorRepresentation: .empty)

        // Read back
        let loadedBundle = try EditorAssetBundle(url: tempURL)

        // Verify all data preserved
        #expect(loadedBundle.id == originalBundle.id)
        #expect(loadedBundle.downloadDate == originalBundle.downloadDate)
        #expect(loadedBundle.manifest.scripts == originalBundle.manifest.scripts)
        #expect(loadedBundle.manifest.styles == originalBundle.manifest.styles)
        #expect(loadedBundle.manifest.allowedBlockTypes == originalBundle.manifest.allowedBlockTypes)
        #expect(loadedBundle.manifest.rawScripts == originalBundle.manifest.rawScripts)
        #expect(loadedBundle.manifest.rawStyles == originalBundle.manifest.rawStyles)
        #expect(loadedBundle.manifest.checksum == originalBundle.manifest.checksum)

        // Clean up
        try? FileManager.default.removeItem(at: tempDir)
    }

    @Test("Multiple bundles with different dates have same ID if same manifest")
    func multipleBundlesWithDifferentDatesHaveSameId() throws {
        let manifest = try createManifest(blockTypes: ["core/paragraph"])

        let bundle1 = makeBundle(
            manifest: manifest,
            downloadDate: Date(timeIntervalSince1970: 1000)
        )

        let bundle2 = makeBundle(
            manifest: manifest,
            downloadDate: Date(timeIntervalSince1970: 2000)
        )

        #expect(bundle1.id == bundle2.id)
        #expect(bundle1.downloadDate != bundle2.downloadDate)
    }

    // MARK: - EditorRepresentation Tests

    @Test("setEditorRepresentation writes file to bundle root")
    func setEditorRepresentationWritesFile() throws {
        let tempDir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let bundle = makeBundle(bundleRoot: tempDir)
        let representation = RemoteEditorAssetManifest.RawManifest(
            scripts: "<script src=\"test.js\"></script>",
            styles: "<link href=\"test.css\">",
            allowedBlockTypes: ["core/paragraph"]
        )

        try bundle.setEditorRepresentation(representation)

        let filePath = tempDir.appending(path: "editor-representation.json")
        #expect(FileManager.default.fileExists(atPath: filePath.path))

        try? FileManager.default.removeItem(at: tempDir)
    }

    @Test("getEditorRepresentation returns typed EditorRepresentation")
    func getEditorRepresentationReturnsTypedValue() throws {
        let tempDir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let bundle = makeBundle(bundleRoot: tempDir)
        let original = RemoteEditorAssetManifest.RawManifest(
            scripts: "<script src=\"plugin.js\"></script>",
            styles: "<link href=\"theme.css\">",
            allowedBlockTypes: ["core/paragraph", "core/heading"]
        )

        try bundle.setEditorRepresentation(original)

        let retrieved: EditorAssetBundle.EditorRepresentation = try bundle.getEditorRepresentation()

        #expect(retrieved.scripts == original.scripts)
        #expect(retrieved.styles == original.styles)
        #expect(retrieved.allowedBlockTypes == original.allowedBlockTypes)

        try? FileManager.default.removeItem(at: tempDir)
    }

    @Test("getEditorRepresentation returns Any for JSON serialization")
    func getEditorRepresentationReturnsAny() throws {
        let tempDir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let bundle = makeBundle(bundleRoot: tempDir)
        let original = RemoteEditorAssetManifest.RawManifest(
            scripts: "<script src=\"app.js\"></script>",
            styles: "<link href=\"style.css\">",
            allowedBlockTypes: ["core/image"]
        )

        try bundle.setEditorRepresentation(original)

        let retrieved: Any = try bundle.getEditorRepresentation()

        #expect(retrieved is [String: Any])
        let dict = retrieved as! [String: Any]
        #expect(dict["scripts"] as? String == original.scripts)
        #expect(dict["styles"] as? String == original.styles)
        #expect(dict["allowed_block_types"] as? [String] == original.allowedBlockTypes)

        try? FileManager.default.removeItem(at: tempDir)
    }

    @Test("getEditorRepresentation throws when file does not exist")
    func getEditorRepresentationThrowsWhenFileDoesNotExist() {
        let tempDir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let bundle = makeBundle(bundleRoot: tempDir)

        #expect(throws: Error.self) {
            let _: EditorAssetBundle.EditorRepresentation = try bundle.getEditorRepresentation()
        }
    }

    @Test("setEditorRepresentation overwrites existing file")
    func setEditorRepresentationOverwritesExistingFile() throws {
        let tempDir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let bundle = makeBundle(bundleRoot: tempDir)

        let first = RemoteEditorAssetManifest.RawManifest(
            scripts: "first",
            styles: "first",
            allowedBlockTypes: ["first"]
        )
        try bundle.setEditorRepresentation(first)

        let second = RemoteEditorAssetManifest.RawManifest(
            scripts: "second",
            styles: "second",
            allowedBlockTypes: ["second"]
        )
        try bundle.setEditorRepresentation(second)

        let retrieved: EditorAssetBundle.EditorRepresentation = try bundle.getEditorRepresentation()

        #expect(retrieved.scripts == "second")
        #expect(retrieved.styles == "second")
        #expect(retrieved.allowedBlockTypes == ["second"])

        try? FileManager.default.removeItem(at: tempDir)
    }

    @Test("EditorRepresentation round-trip preserves all fields")
    func editorRepresentationRoundTripPreservesAllFields() throws {
        let tempDir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let bundle = makeBundle(bundleRoot: tempDir)
        let original = RemoteEditorAssetManifest.RawManifest(
            scripts: "<script src=\"https://example.com/gutenberg.js?ver=1.0\"></script><script>console.log('inline');</script>",
            styles: "<link rel=\"stylesheet\" href=\"https://example.com/editor.css\"><style>.block { color: red; }</style>",
            allowedBlockTypes: ["core/paragraph", "core/heading", "core/image", "jetpack/ai-assistant"]
        )

        try bundle.setEditorRepresentation(original)
        let retrieved: EditorAssetBundle.EditorRepresentation = try bundle.getEditorRepresentation()

        #expect(retrieved == original)

        try? FileManager.default.removeItem(at: tempDir)
    }
}

// MARK: - Test Helpers

extension EditorAssetBundleTests {

    fileprivate func write(_ content: String, to file: URL) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(content.utf8).write(to: file)
    }

    fileprivate func makeBundle(
        manifest: LocalEditorAssetManifest = .empty,
        downloadDate: Date? = nil,
        bundleRoot: URL = .temporaryDirectory
    ) -> EditorAssetBundle {
        if let downloadDate {
            return try! EditorAssetBundle(manifest: manifest, downloadDate: downloadDate, bundleRoot: bundleRoot)
        }
        return try! EditorAssetBundle(manifest: manifest, bundleRoot: bundleRoot)
    }

    fileprivate func createManifest(
        scripts: String = "",
        styles: String = "",
        blockTypes: [String] = []
    ) throws -> LocalEditorAssetManifest {
        let blockTypesJson = blockTypes.map { "\"\($0)\"" }.joined(separator: ", ")
        let json = """
      {
          "scripts": \(escapeJsonString(scripts)),
          "styles": \(escapeJsonString(styles)),
          "allowed_block_types": [\(blockTypesJson)]
      }
      """
        return try LocalEditorAssetManifest.from(data: Data(json.utf8))
    }

    fileprivate func escapeJsonString(_ string: String) -> String {
        let escaped =
            string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
        return "\"\(escaped)\""
    }
}

extension LocalEditorAssetManifest {
    fileprivate static func from(data: Data) throws -> LocalEditorAssetManifest {
        let remote = try RemoteEditorAssetManifest(data: data)
        return try LocalEditorAssetManifest(remoteManifest: remote)
    }
}
