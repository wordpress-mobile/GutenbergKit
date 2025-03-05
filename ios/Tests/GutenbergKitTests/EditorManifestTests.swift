import Foundation
import Testing
@testable import GutenbergKit

@Suite("Manifest Tests")
struct EditorManifestTests {

    @Test("Default Manifest Test Case")
    func runTestCase1() async throws {
        let json = try json(named: "manifest-test-case-1")
        let manifest = try EditorManifest(data: json)

        #expect(manifest.scripts.count == 79)
        #expect(manifest.styles.count == 22)
        #expect(manifest.hash == "4a041c7d3cdcb9457bdf7d63c0f4d289fe087701ec2f91908c8c8fb92002fb2c")
    }

    @Test("Try downloading manifest")
    func runTestCase2() async throws {
        let json = try json(named: "manifest-test-case-1")
        let manifest = try EditorManifest(data: json)

        try await EditorLibrary().buildManifest(for: manifest)

        try await #expect(EditorLibrary().listManifests().count == 1)
    }

    private func json(named name: String) throws -> Data {
        let json = Bundle.module.url(forResource: name, withExtension: "json")!
        return try Data(contentsOf: json)
    }
}
