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

    /// A bundle on disk can be read by someone looking for an asset.
    @Test("an asset's file is named for its URL")
    func assetFileIsNamedForItsURL() throws {
        let bundle = makeBundle()
        let asset = try #require(URL(string: "https://example.com/wp-content/plugins/script.js?ver=1.2"))

        let name = bundle.assetDataPath(for: asset).lastPathComponent

        #expect(name.hasPrefix("example.com_wp-content_plugins_script.js_ver=1.2."))
        #expect(name.hasSuffix(".js"))
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
