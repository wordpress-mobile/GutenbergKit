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

    @Test("hasAssetData returns true when file exists at expected path")
    func hasAssetDataReturnsTrueWhenFileExists() throws {
        // Create temp directory and file
        let tempDir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let assetPath = tempDir.appending(path: "wp-content/plugins/script.js")
        try FileManager.default.createDirectory(
            at: assetPath.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("test".utf8).write(to: assetPath)

        let bundle = makeBundle(bundleRoot: tempDir)
        let url = URL(string: "https://example.com/wp-content/plugins/script.js")!

        #expect(bundle.hasAssetData(for: url))

        // Clean up
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: - isValidAssetPath Tests

    @Test("isValidAssetPath returns true for valid path within bundle")
    func isValidAssetPathReturnsTrueForValidPath() {
        let tempDir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let bundle = makeBundle(bundleRoot: tempDir)

        let url = URL(string: "https://example.com/wp-content/plugins/script.js")!
        #expect(bundle.isValidAssetPath(for: url))
    }

    @Test("isValidAssetPath returns true for nested paths")
    func isValidAssetPathReturnsTrueForNestedPaths() {
        let tempDir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let bundle = makeBundle(bundleRoot: tempDir)

        let url = URL(string: "https://example.com/wp-content/plugins/jetpack/assets/js/script.js")!
        #expect(bundle.isValidAssetPath(for: url))
    }

    @Test("isValidAssetPath returns false for path traversal attempt")
    func isValidAssetPathReturnsFalseForPathTraversal() {
        let tempDir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let bundle = makeBundle(bundleRoot: tempDir)

        let url = URL(string: "https://example.com/../../../etc/passwd")!
        #expect(!bundle.isValidAssetPath(for: url))
    }

    @Test("isValidAssetPath returns false for path escaping via encoded traversal")
    func isValidAssetPathReturnsFalseForEncodedTraversal() {
        let tempDir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let bundle = makeBundle(bundleRoot: tempDir)

        let url = URL(string: "https://example.com/%2e%2e/%2e%2e/etc/passwd")!
        #expect(!bundle.isValidAssetPath(for: url))
    }

    @Test("isValidAssetPath handles paths with dot segments that stay within bundle")
    func isValidAssetPathHandlesDotSegmentsWithinBundle() {
        let tempDir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let bundle = makeBundle(bundleRoot: tempDir)

        let url = URL(string: "https://example.com/wp-content/./plugins/script.js")!
        #expect(bundle.isValidAssetPath(for: url))
    }

    // MARK: - assetDataPath Tests

    @Test("assetDataPath returns correct path based on URL path")
    func assetDataPathReturnsCorrectPath() {
        let tempDir = FileManager.default.temporaryDirectory.appending(path: "test-bundle")
        let bundle = makeBundle(bundleRoot: tempDir)

        let url = URL(string: "https://example.com/wp-content/plugins/script.js")!
        let result = bundle.assetDataPath(for: url)

        #expect(result.path.contains("/wp-content/plugins/script.js"))
    }

    @Test("assetDataPath allows valid nested paths")
    func assetDataPathAllowsValidNestedPaths() {
        let tempDir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let bundle = makeBundle(bundleRoot: tempDir)

        let url = URL(string: "https://example.com/wp-content/plugins/my-plugin/assets/js/script.js")!
        let result = bundle.assetDataPath(for: url)

        #expect(result.standardizedFileURL.path.hasPrefix(tempDir.standardizedFileURL.path))
    }

    @Test("assetDataPath normalizes paths with dot segments")
    func assetDataPathNormalizesDotsSegments() {
        let tempDir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let bundle = makeBundle(bundleRoot: tempDir)

        // This path has ./ which should be normalized but stay within bundle
        let url = URL(string: "https://example.com/wp-content/./plugins/script.js")!
        let result = bundle.assetDataPath(for: url)

        #expect(result.standardizedFileURL.path.hasPrefix(tempDir.standardizedFileURL.path))
        #expect(result.path.contains("plugins/script.js"))
    }

    @Test("assetDataPath crashes for path traversal attempt")
    func assetDataPathCrashesForPathTraversal() async {
        await #expect(processExitsWith: .failure) {
            let tempDir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
            let bundle = EditorAssetBundle(
                raw: EditorAssetBundle.RawAssetBundle(manifest: .empty, downloadDate: Date()),
                bundleRoot: tempDir
            )
            let url = URL(string: "https://example.com/../../../etc/passwd")!
            _ = bundle.assetDataPath(for: url)
        }
    }

    // MARK: - assetData Tests

    @Test("assetData returns data for existing file")
    func assetDataReturnsDataForExistingFile() throws {
        // Create temp directory and file
        let tempDir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let assetPath = tempDir.appending(path: "script.js")
        let testContent = "console.log('test');"
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        try Data(testContent.utf8).write(to: assetPath)

        let bundle = makeBundle(bundleRoot: tempDir)

        let requestUrl = URL(string: "https://example.com/script.js")!
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
