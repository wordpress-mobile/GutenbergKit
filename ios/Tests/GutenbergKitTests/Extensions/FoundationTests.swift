import Foundation
import Testing

@testable import GutenbergKit

@Suite
struct FileManagerExtensionsTests {

  // MARK: - fileExists(at:)
  @Test("fileExists(at:) returns true for existing file")
  func fileExistsReturnsTrueForExistingFile() throws {
    let tempFile = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try Data("test".utf8).write(to: tempFile)
    defer { try? FileManager.default.removeItem(at: tempFile) }

    #expect(FileManager.default.fileExists(at: tempFile) == true)
  }

  @Test("fileExists(at:) returns false for non-existing file")
  func fileExistsReturnsFalseForNonExistingFile() {
    let nonExistentFile = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    #expect(FileManager.default.fileExists(at: nonExistentFile) == false)
  }

  @Test("fileExists(at:) returns true for existing directory")
  func fileExistsReturnsTrueForDirectory() throws {
    let tempDir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    #expect(FileManager.default.fileExists(at: tempDir) == true)
  }

  // MARK: - directoryExists(at:)
  @Test("directoryExists(at:) returns true for existing directory")
  func directoryExistsReturnsTrueForDirectory() throws {
    let tempDir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    #expect(FileManager.default.directoryExists(at: tempDir) == true)
  }

  @Test("directoryExists(at:) returns false for non-existing path")
  func directoryExistsReturnsFalseForNonExisting() {
    let nonExistentDir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    #expect(FileManager.default.directoryExists(at: nonExistentDir) == false)
  }

  @Test("directoryExists(at:) returns false for file")
  func directoryExistsReturnsFalseForFile() throws {
    let tempFile = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try Data("test".utf8).write(to: tempFile)
    defer { try? FileManager.default.removeItem(at: tempFile) }

    #expect(FileManager.default.directoryExists(at: tempFile) == false)
  }

  @Test("directoryExists(at:) distinguishes files from directories")
  func directoryExistsDistinguishesFilesFromDirectories() throws {
    let tempDir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

    let tempFile = tempDir.appending(path: "file.txt")
    try Data("test".utf8).write(to: tempFile)

    defer { try? FileManager.default.removeItem(at: tempDir) }

    #expect(FileManager.default.directoryExists(at: tempDir) == true)
    #expect(FileManager.default.directoryExists(at: tempFile) == false)
    #expect(FileManager.default.fileExists(at: tempFile) == true)
  }

  // MARK: - Percent Encoding Tests

  @Test("fileExists(at:) handles paths with spaces")
  func fileExistsHandlesPathsWithSpaces() throws {
    let tempDir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let fileWithSpaces = tempDir.appending(path: "file with spaces.txt")
    try Data("test".utf8).write(to: fileWithSpaces)

    #expect(FileManager.default.fileExists(at: fileWithSpaces) == true)
  }

  @Test("fileExists(at:) handles paths with percent-encoded characters")
  func fileExistsHandlesPercentEncodedPaths() throws {
    let tempDir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    // Create a file with special characters that would be percent-encoded in URLs
    let specialFileName = "file%20with%20encoded.txt"
    let fileWithSpecialChars = tempDir.appending(path: specialFileName)
    try Data("test".utf8).write(to: fileWithSpecialChars)

    #expect(FileManager.default.fileExists(at: fileWithSpecialChars) == true)
  }

  @Test("fileExists(at:) handles paths with unicode characters")
  func fileExistsHandlesUnicodePaths() throws {
    let tempDir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let unicodeFileName = "文件名.txt"
    let fileWithUnicode = tempDir.appending(path: unicodeFileName)
    try Data("test".utf8).write(to: fileWithUnicode)

    #expect(FileManager.default.fileExists(at: fileWithUnicode) == true)
  }

  @Test("fileExists(at:) handles paths with special URL characters")
  func fileExistsHandlesSpecialURLCharacters() throws {
    let tempDir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    // Characters that have special meaning in URLs: # ? & =
    let specialFileName = "file#with?special&chars=test.txt"
    let fileWithSpecialChars = tempDir.appending(path: specialFileName)
    try Data("test".utf8).write(to: fileWithSpecialChars)

    #expect(FileManager.default.fileExists(at: fileWithSpecialChars) == true)
  }

  @Test("directoryExists(at:) handles paths with spaces")
  func directoryExistsHandlesPathsWithSpaces() throws {
    let tempDir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let dirWithSpaces = tempDir.appending(path: "directory with spaces")
    try FileManager.default.createDirectory(at: dirWithSpaces, withIntermediateDirectories: true)

    #expect(FileManager.default.directoryExists(at: dirWithSpaces) == true)
  }

  @Test("directoryExists(at:) handles paths with unicode characters")
  func directoryExistsHandlesUnicodePaths() throws {
    let tempDir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let unicodeDirName = "目录名"
    let dirWithUnicode = tempDir.appending(path: unicodeDirName)
    try FileManager.default.createDirectory(at: dirWithUnicode, withIntermediateDirectories: true)

    #expect(FileManager.default.directoryExists(at: dirWithUnicode) == true)
  }

  @Test("directoryExists(at:) handles nested paths with special characters")
  func directoryExistsHandlesNestedSpecialPaths() throws {
    let tempDir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let nestedDir =
      tempDir
      .appending(path: "level 1 with spaces")
      .appending(path: "level2#special")
      .appending(path: "レベル3")
    try FileManager.default.createDirectory(at: nestedDir, withIntermediateDirectories: true)

    #expect(FileManager.default.directoryExists(at: nestedDir) == true)
  }

  @Test(
    "fileExists(at:) correctly reports non-existence for percent-encoded path that doesn't exist")
  func fileExistsReportsNonExistenceForEncodedPath() {
    let nonExistentPath = FileManager.default.temporaryDirectory
      .appending(path: UUID().uuidString)
      .appending(path: "file with spaces.txt")

    #expect(FileManager.default.fileExists(at: nonExistentPath) == false)
  }
}

// MARK: - URL.appending(rawPath:) Tests

@Suite
struct URLAppendingRawPathTests {

  // MARK: - Basic Path Appending

  @Test("appends path when base URL has no trailing slash and path has no leading slash")
  func appendsPathWithNoSlashes() {
    let base = URL(string: "https://example.com/api")!
    let result = base.appending(rawPath: "posts")
    #expect(result.absoluteString == "https://example.com/api/posts")
  }

  @Test("appends path when base URL has trailing slash and path has no leading slash")
  func appendsPathWhenBaseHasTrailingSlash() {
    let base = URL(string: "https://example.com/api/")!
    let result = base.appending(rawPath: "posts")
    #expect(result.absoluteString == "https://example.com/api/posts")
  }

  @Test("appends path when base URL has no trailing slash and path has leading slash")
  func appendsPathWhenPathHasLeadingSlash() {
    let base = URL(string: "https://example.com/api")!
    let result = base.appending(rawPath: "/posts")
    #expect(result.absoluteString == "https://example.com/api/posts")
  }

  @Test("appends path when both have slashes (avoids double slash)")
  func appendsPathAvoidingDoubleSlash() {
    let base = URL(string: "https://example.com/api/")!
    let result = base.appending(rawPath: "/posts")
    #expect(result.absoluteString == "https://example.com/api/posts")
  }

  // MARK: - Multi-segment Paths

  @Test("appends multi-segment path")
  func appendsMultiSegmentPath() {
    let base = URL(string: "https://example.com/wp-json")!
    let result = base.appending(rawPath: "wp/v2/posts")
    #expect(result.absoluteString == "https://example.com/wp-json/wp/v2/posts")
  }

  @Test("appends multi-segment path with leading slash")
  func appendsMultiSegmentPathWithLeadingSlash() {
    let base = URL(string: "https://example.com/wp-json")!
    let result = base.appending(rawPath: "/wp/v2/posts")
    #expect(result.absoluteString == "https://example.com/wp-json/wp/v2/posts")
  }

  // MARK: - Query Parameters

  @Test("appends path with query parameters")
  func appendsPathWithQueryParameters() {
    let base = URL(string: "https://example.com/api")!
    let result = base.appending(rawPath: "posts?context=edit")
    #expect(result.absoluteString == "https://example.com/api/posts?context=edit")
  }

  @Test("appends path with multiple query parameters")
  func appendsPathWithMultipleQueryParameters() {
    let base = URL(string: "https://example.com/api")!
    let result = base.appending(rawPath: "posts?context=edit&per_page=10")
    #expect(result.absoluteString == "https://example.com/api/posts?context=edit&per_page=10")
  }

  // MARK: - Query-based REST Roots (plain permalinks)

  @Test("appends path to the query value of a query-based REST root")
  func appendsPathToQueryBasedRoot() {
    let base = URL(string: "https://example.com/?rest_route=/")!
    let result = base.appending(rawPath: "/wp/v2/media")
    #expect(result.absoluteString == "https://example.com/?rest_route=/wp/v2/media")
  }

  @Test("merges the path's query string into a query-based REST root")
  func mergesQueryIntoQueryBasedRoot() {
    let base = URL(string: "https://example.com/?rest_route=/")!
    let result = base.appending(rawPath: "/wp/v2/themes?context=edit&status=active")
    #expect(
      result.absoluteString
        == "https://example.com/?rest_route=/wp/v2/themes&context=edit&status=active")
  }

  @Test("normalizes a query-based REST root without a trailing slash")
  func normalizesQueryBasedRootWithoutTrailingSlash() {
    let base = URL(string: "https://example.com/?rest_route=")!
    let result = base.appending(rawPath: "/wp/v2/media")
    #expect(result.absoluteString == "https://example.com/?rest_route=/wp/v2/media")
  }

  @Test("appends path without a leading slash to a query-based REST root")
  func appendsPathWithoutLeadingSlashToQueryBasedRoot() {
    let base = URL(string: "https://example.com/?rest_route=/")!
    let result = base.appending(rawPath: "wp/v2/media")
    #expect(result.absoluteString == "https://example.com/?rest_route=/wp/v2/media")
  }

  // MARK: - Special Characters

  @Test("appends path with numeric ID")
  func appendsPathWithNumericId() {
    let base = URL(string: "https://example.com/api/posts")!
    let result = base.appending(rawPath: "123")
    #expect(result.absoluteString == "https://example.com/api/posts/123")
  }

  @Test("appends path with hyphens and underscores")
  func appendsPathWithHyphensAndUnderscores() {
    let base = URL(string: "https://example.com")!
    let result = base.appending(rawPath: "wp-block-editor/v1/settings_options")
    #expect(result.absoluteString == "https://example.com/wp-block-editor/v1/settings_options")
  }

  // MARK: - Edge Cases

  @Test("appends empty path")
  func appendsEmptyPath() {
    let base = URL(string: "https://example.com/api")!
    let result = base.appending(rawPath: "")
    #expect(result.absoluteString == "https://example.com/api/")
  }

  @Test("appends single slash")
  func appendsSingleSlash() {
    let base = URL(string: "https://example.com/api")!
    let result = base.appending(rawPath: "/")
    #expect(result.absoluteString == "https://example.com/api/")
  }

  @Test("works with root URL")
  func worksWithRootUrl() {
    let base = URL(string: "https://example.com")!
    let result = base.appending(rawPath: "api/posts")
    #expect(result.absoluteString == "https://example.com/api/posts")
  }

  @Test("works with root URL with trailing slash")
  func worksWithRootUrlWithTrailingSlash() {
    let base = URL(string: "https://example.com/")!
    let result = base.appending(rawPath: "api/posts")
    #expect(result.absoluteString == "https://example.com/api/posts")
  }

  // MARK: - Real-world WordPress API Paths

  @Test("appends WordPress post endpoint path")
  func appendsWordPressPostEndpoint() {
    let base = URL(string: "https://example.com/wp-json")!
    let result = base.appending(rawPath: "wp/v2/posts/42?context=edit")
    #expect(result.absoluteString == "https://example.com/wp-json/wp/v2/posts/42?context=edit")
  }

  @Test("appends WordPress block editor settings path")
  func appendsWordPressBlockEditorSettingsPath() {
    let base = URL(string: "https://example.com/wp-json")!
    let result = base.appending(rawPath: "wp-block-editor/v1/settings")
    #expect(result.absoluteString == "https://example.com/wp-json/wp-block-editor/v1/settings")
  }

  @Test("appends WordPress themes endpoint path")
  func appendsWordPressThemesEndpoint() {
    let base = URL(string: "https://example.com/wp-json")!
    let result = base.appending(rawPath: "wp/v2/themes?status=active")
    #expect(result.absoluteString == "https://example.com/wp-json/wp/v2/themes?status=active")
  }
}
