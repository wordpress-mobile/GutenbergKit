import Foundation
import Testing
@testable import GutenbergKit

@Suite("Editor Service Tests")
struct EditorServiceTests {

    let manifestData: Data = {
        let manifestURL = Bundle.module.url(forResource: "manifest-test-case-2", withExtension: "json")!
        return try! Data(contentsOf: manifestURL)
    }()

    let assetURLs: [String] = [
        "https://example.com/wp-content/plugins/jetpack/modules/videopress/js/videopress-token-bridge.js?ver=13.9",
        "https://example.com/wp-content/plugins/jetpack/_inc/blocks/contact-form/editor.js?ver=13.9",
        "https://example.com/wp-content/plugins/jetpack/_inc/blocks/slideshow/editor.js?ver=13.9",
        "https://example.com/wp-content/plugins/jetpack/jetpack_vendor/automattic/jetpack-forms/dist/blocks/editor.css?ver=13.9",
        "https://example.com/wp-content/plugins/jetpack/_inc/blocks/editor.css?ver=13.9"
    ]

    @Test("Successfully loads editor dependencies")
    func successfullyLoadsDependencies() async throws {
        let session = MockURLSession()

        session.mockResponse(
            for: "https://example.com/wp-block-editor/v1/settings",
            data: """
            {"alignWide": true}
            """.data(using: .utf8)!,
            statusCode: 200
        )

        session.mockResponse(
            for: "https://example.com/wpcom/v2/editor-assets?exclude=core,gutenberg",
            data: manifestData,
            statusCode: 200
        )

        for assetURL in assetURLs {
            session.mockSuccessfulResponse(forAssetURL: assetURL)
        }

        let testDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: testDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: testDir) }

        let service = EditorService(siteURL: "https://example.com", storeURL: testDir, networkSession: session)
        let configuration = EditorConfigurationBuilder()
            .setSiteUrl("https://example.com")
            .setSiteApiRoot("https://example.com")
            .setAuthHeader("Bearer test-token")
            .build()

        // WHEN
        let dependencies = await service.dependencies(for: configuration)

        // THEN dependencies are loaded and editor settings are returned as is
        #expect(dependencies.editorSettings == #"{"alignWide": true}"#)

        // THEN processed manifest contains links pointing to files on disk (`gbk-cache-https://`)
        let manifest = try #require(dependencies.manifest)
        #expect(manifest.contains(#"link rel=\"stylesheet\" id=\"jp-forms-blocks-css\" href=\"gbk-cache-https:\/\/example.com\/wp-content\/plugins\/jetpack\/jetpack_vendor\/automattic\/jetpack-forms\/dist\/blocks\/editor.css?ver=13.9\"#))
    }

    @Test("Loads settings but not manifest when asset download fails")
    func loadsSettingsWhenAssetFails() async throws {

        // GIVEN one of the asset fails to load
        let session = MockURLSession()

        session.mockResponse(
            for: "https://example.com/wp-block-editor/v1/settings",
            data: """
            {"alignWide": true}
            """.data(using: .utf8)!,
            statusCode: 200
        )

        session.mockResponse(
            for: "https://example.com/wpcom/v2/editor-assets?exclude=core,gutenberg",
            data: manifestData,
            statusCode: 200
        )

        for assetURL in assetURLs[0...1] {
            session.mockSuccessfulResponse(forAssetURL: assetURL)
        }
        for assetURL in assetURLs[2...4] {
            session.mockResponse(for: assetURL, data: Data(), statusCode: 404)
        }

        let testDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: testDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: testDir) }

        let service = EditorService(siteURL: "https://example.com", storeURL: testDir, networkSession: session)
        let configuration = EditorConfigurationBuilder()
            .setSiteUrl("https://example.com")
            .setSiteApiRoot("https://example.com")
            .setAuthHeader("Bearer test-token")
            .build()

        let dependencies = await service.dependencies(for: configuration)

        // THEN settings are loaded but manifest is ignored – we cam't guarantee
        // it will work with missing resources
        #expect(dependencies.editorSettings == #"{"alignWide": true}"#)
        #expect(dependencies.manifest == nil)
    }
}

private extension MockURLSession {
    func mockSuccessfulResponse(forAssetURL assetURL: String) {
        mockResponse(
            for: assetURL,
            data: assetURL.data(using: .utf8)!,
            statusCode: 200
        )
    }
}
