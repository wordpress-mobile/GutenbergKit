import Foundation
import GutenbergKitResources
import Testing

struct `GutenbergKit Resources` {

    @Test func `getting resources bundle URL`() {
        let url = GutenbergKitResources.resourcesURL()
        #expect(FileManager.default.fileExists(atPath: url.path))
    }

    @Test func `getting index URL`() {
        let url = GutenbergKitResources.indexURL()
        #expect(FileManager.default.fileExists(atPath: url.path))
    }

    @Test func `loading Gutenberg CSS`() {
        #expect(GutenbergKitResources.loadGutenbergCSS() != nil)
    }
}
