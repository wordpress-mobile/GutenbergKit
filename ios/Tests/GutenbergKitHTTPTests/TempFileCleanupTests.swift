#if canImport(Network)

import Foundation
import Testing
@testable import GutenbergKitHTTP

@Suite("Temp File Cleanup")
struct TempFileCleanupTests {

    @Test("orphan cleanup skips registered (in-flight) files and removes orphans")
    func cleanupSkipsActiveFiles() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("GutenbergKitHTTP-cleanup-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let active = dir.appendingPathComponent("GutenbergKitHTTP-\(UUID().uuidString)")
        let orphan = dir.appendingPathComponent("GutenbergKitHTTP-\(UUID().uuidString)")
        #expect(FileManager.default.createFile(atPath: active.path, contents: Data("a".utf8)))
        #expect(FileManager.default.createFile(atPath: orphan.path, contents: Data("b".utf8)))

        // Mark `active` as backing an in-flight request, as a concurrently-running
        // server instance sharing this directory would.
        ActiveTempFiles.register(active.lastPathComponent)
        defer { ActiveTempFiles.unregister(active.lastPathComponent) }

        HTTPServer.cleanOrphanedTempFiles(in: dir)

        #expect(FileManager.default.fileExists(atPath: active.path), "registered (live) file must be preserved")
        #expect(!FileManager.default.fileExists(atPath: orphan.path), "unregistered orphan must be removed")
    }

    @Test("cleanup removes everything when nothing is registered (crash recovery)")
    func cleanupRemovesAllOrphansOnFreshProcess() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("GutenbergKitHTTP-cleanup-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let orphans = (0..<3).map { _ in dir.appendingPathComponent("GutenbergKitHTTP-\(UUID().uuidString)") }
        for url in orphans {
            #expect(FileManager.default.createFile(atPath: url.path, contents: Data("x".utf8)))
        }

        HTTPServer.cleanOrphanedTempFiles(in: dir)

        for url in orphans {
            #expect(!FileManager.default.fileExists(atPath: url.path))
        }
    }
}

#endif
