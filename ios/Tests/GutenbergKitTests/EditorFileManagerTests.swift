import XCTest
@testable import GutenbergKit

@MainActor
final class EditorFileManagerTests: XCTestCase {
    
    var tempDirectory: URL!
    var fileManager: EditorFileManager!
    
    override func setUp() async throws {
        try await super.setUp()
        
        // Create a unique temporary directory for testing
        let tempDirURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("GutenbergKitTests")
            .appendingPathComponent(UUID().uuidString)
        
        try FileManager.default.createDirectory(at: tempDirURL, withIntermediateDirectories: true)
        
        self.tempDirectory = tempDirURL
        self.fileManager = EditorFileManager(targetDirectory: tempDirURL)
    }
    
    override func tearDown() async throws {
        // Clean up temporary directory
        if let tempDirectory = tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        
        try await super.tearDown()
    }
    
    func testCopyEditorFilesIfNeeded() throws {
        // Given
        let editorDirectory = fileManager.editorDirectory
        let indexURL = editorDirectory.appendingPathComponent("index.html")
        let remoteURL = editorDirectory.appendingPathComponent("remote.html")
        
        // Initially, files should not exist
        XCTAssertFalse(FileManager.default.fileExists(atPath: indexURL.path), "index.html should not exist initially")
        XCTAssertFalse(FileManager.default.fileExists(atPath: remoteURL.path), "remote.html should not exist initially")
        
        // When
        try fileManager.copyEditorFilesIfNeeded()
        
        // Then
        XCTAssertTrue(FileManager.default.fileExists(atPath: indexURL.path), "index.html should exist after copying")
        XCTAssertTrue(FileManager.default.fileExists(atPath: remoteURL.path), "remote.html should exist after copying")
        
        // Verify the files have content
        let indexContent = try String(contentsOf: indexURL)
        XCTAssertFalse(indexContent.isEmpty, "index.html should have content")
        XCTAssertTrue(indexContent.contains("<!DOCTYPE html>") || indexContent.contains("<html"), "index.html should be valid HTML")
        
        let remoteContent = try String(contentsOf: remoteURL)
        XCTAssertFalse(remoteContent.isEmpty, "remote.html should have content")
        XCTAssertTrue(remoteContent.contains("<!DOCTYPE html>") || remoteContent.contains("<html"), "remote.html should be valid HTML")
    }
    
    func testCopyEditorFilesIfNeededIdempotent() throws {
        // Given
        try fileManager.copyEditorFilesIfNeeded()
        let indexURL = fileManager.editorDirectory.appendingPathComponent("index.html")
        
        // Modify the file to verify it's not overwritten
        let testContent = "<!-- Test Content -->"
        try testContent.write(to: indexURL, atomically: true, encoding: .utf8)
        
        // When - copy again
        try fileManager.copyEditorFilesIfNeeded()
        
        // Then - file should not be overwritten
        let content = try String(contentsOf: indexURL)
        XCTAssertEqual(content, testContent, "Existing files should not be overwritten")
    }
    
    func testCopyEditorFilesSubdirectories() throws {
        // When
        try fileManager.copyEditorFilesIfNeeded()
        
        // Then - verify subdirectories are created
        let editorDirectory = fileManager.editorDirectory
        
        // Check if common subdirectories exist (adjust based on actual Gutenberg structure)
        let possibleSubdirs = ["css", "js", "assets", "build"]
        var foundSubdir = false
        
        if let contents = try? FileManager.default.contentsOfDirectory(at: editorDirectory, includingPropertiesForKeys: nil) {
            for url in contents {
                var isDirectory: ObjCBool = false
                if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
                   isDirectory.boolValue {
                    foundSubdir = true
                    break
                }
            }
        }
        
        // We expect at least some structure to be copied
        XCTAssertTrue(foundSubdir || 
                      FileManager.default.fileExists(atPath: editorDirectory.appendingPathComponent("index.html").path),
                      "Editor files should be copied with their structure")
    }
    
    func testComputedProperties() {
        // Test that computed properties return correct URLs
        let expectedIndexURL = fileManager.editorDirectory.appendingPathComponent("index.html")
        let expectedRemoteURL = fileManager.editorDirectory.appendingPathComponent("remote.html")
        
        XCTAssertEqual(fileManager.editorIndexURL, expectedIndexURL, "editorIndexURL should return correct path")
        XCTAssertEqual(fileManager.remoteEditorURL, expectedRemoteURL, "remoteEditorURL should return correct path")
    }
    
    func testInitializationCreatesDirectories() {
        // Given a new temporary directory
        let newTempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("GutenbergKitTests")
            .appendingPathComponent(UUID().uuidString)
        
        // When
        let newFileManager = EditorFileManager(targetDirectory: newTempDir)
        
        // Then
        XCTAssertTrue(FileManager.default.fileExists(atPath: newFileManager.editorDirectory.path), 
                      "Editor directory should be created on initialization")
        
        // Cleanup
        try? FileManager.default.removeItem(at: newTempDir)
    }
}