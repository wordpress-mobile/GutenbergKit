import Foundation
import Testing
@testable import GutenbergKit

@Suite("Editor Service Tests")
struct EditorServiceTests {

    @Test("Successfully loads editor dependencies")
    func successfullyLoadsDependencies() async throws {
        let session = MockNetworkSession()

        session.mockResponse(
            for: "https://example.com/wp-block-editor/v1/settings",
            data: """
            {"alignWide": true}
            """.data(using: .utf8)!,
            statusCode: 200
        )

        let manifestURL = Bundle.module.url(forResource: "manifest-test-case-2", withExtension: "json")!
        let manifestData = try Data(contentsOf: manifestURL)
        session.mockResponse(
            for: "https://example.com/wpcom/v2/editor-assets?exclude=core,gutenberg",
            data: manifestData,
            statusCode: 200
        )

        session.mockResponse(
            for: "https://example.com/wp-content/plugins/jetpack/jetpack_vendor/automattic/jetpack-forms/dist/blocks/editor.css",
            data: "/* jetpack forms */".data(using: .utf8)!,
            statusCode: 200
        )

        session.mockResponse(
            for: "https://example.com/wp-content/plugins/jetpack/_inc/blocks/editor.css",
            data: "/* jetpack blocks */".data(using: .utf8)!,
            statusCode: 200
        )

        session.mockResponse(
            for: "https://example.com/wp-content/plugins/jetpack/modules/videopress/js/videopress-token-bridge.js",
            data: "//videopress".data(using: .utf8)!,
            statusCode: 200
        )

        session.mockResponse(
            for: "https://example.com/wp-content/plugins/jetpack/_inc/blocks/contact-form/editor.js",
            data: "//contact-form".data(using: .utf8)!,
            statusCode: 200
        )

        session.mockResponse(
            for: "https://example.com/wp-content/plugins/jetpack/_inc/blocks/slideshow/editor.js",
            data: "//slideshow".data(using: .utf8)!,
            statusCode: 200
        )

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
}
