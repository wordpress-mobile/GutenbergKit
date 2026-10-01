import Foundation
import Testing

@testable import GutenbergKit

@Suite("Native media import")
struct MediaImportTests {
  private let root = FileManager.default.temporaryDirectory.appending(component: "import-root-\(UUID().uuidString)")

  @Test("imports a file under its own name, in its own directory, as a clone")
  func importsAsAClone() async throws {
    let source = try makeTemporaryFile(Data(repeating: 7, count: 256 * 1024), named: "IMG 0001.MOV")
    let manager = MediaFileManager(rootURL: root)

    let info = try await manager.importFile(at: source)

    let url = try #require(info.url.flatMap(URL.init(string:)))
    #expect(url.scheme == MediaFileSchemeHandler.scheme)
    #expect(info.type == "video/quicktime")
    let fileURL = try #require(MediaFileManager.fileURL(for: url, root: root))
    #expect(fileURL.lastPathComponent == "IMG 0001.MOV")
    #expect(fileURL.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent == "Uploads")
    #expect(try Data(contentsOf: fileURL) == Data(contentsOf: source))
    #expect(try sharesStorage(fileURL, with: source), "the import copied the bytes instead of cloning them")
  }

  @Test("removes WebKit's old upload copies, and nothing else")
  func removesStaleWebKitUploadCopies() throws {
    let tmp = URL.randomTemporaryDirectory
    let old = tmp.appending(component: "WKFileUploadPanel-old")
    let recent = tmp.appending(component: "WKFileUploadPanel-recent")
    let unrelated = tmp.appending(component: "GutenbergKit-uploads")
    for directory in [old, recent, unrelated] {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      try Data("video".utf8).write(to: directory.appending(component: "clip.mp4"))
    }
    let threeDaysAgo = Date.now.addingTimeInterval(-3 * 24 * 60 * 60)
    try FileManager.default.setAttributes([.creationDate: threeDaysAgo], ofItemAtPath: old.path)
    try FileManager.default.setAttributes([.creationDate: threeDaysAgo], ofItemAtPath: unrelated.path)

    MediaFileManager.removeStaleWebKitUploadCopies(in: tmp)

    #expect(!FileManager.default.fileExists(atPath: old.path))
    #expect(FileManager.default.fileExists(atPath: recent.path))
    #expect(FileManager.default.fileExists(atPath: unrelated.path))
  }

  @Test("maps a file back to the gbk-media-file URL that names it")
  func mediaURLRoundTrips() throws {
    let file = root.appending(component: "Uploads/abc/IMG 0001.HEIC")
    let url = try #require(MediaFileManager.mediaURL(forFile: file, root: root))

    #expect(url.absoluteString == "gbk-media-file:///Uploads/abc/IMG%200001.HEIC")
    #expect(MediaFileManager.fileURL(for: url, root: root) == file.standardizedFileURL)
    #expect(MediaFileManager.mediaURL(forFile: URL(fileURLWithPath: "/etc/hosts"), root: root) == nil)
  }
}

/// Whether two files share their storage — an APFS clone — read with `getattrlist`.
func sharesStorage(_ a: URL, with b: URL) throws -> Bool {
  func cloneAttributes(_ url: URL) throws -> (cloneID: UInt64, privateSize: Int64) {
    var list = attrlist()
    list.bitmapcount = u_short(ATTR_BIT_MAP_COUNT)
    list.forkattr = attrgroup_t(ATTR_CMNEXT_PRIVATESIZE) | attrgroup_t(ATTR_CMNEXT_CLONEID)
    var buffer = [UInt8](repeating: 0, count: 64)
    let result = url.withUnsafeFileSystemRepresentation { getattrlist($0!, &list, &buffer, buffer.count, UInt32(FSOPT_ATTR_CMN_EXTENDED)) }
    guard result == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    return buffer.withUnsafeBytes {
      (cloneID: $0.loadUnaligned(fromByteOffset: 12, as: UInt64.self), privateSize: $0.loadUnaligned(fromByteOffset: 4, as: Int64.self))
    }
  }
  let first = try cloneAttributes(a)
  let second = try cloneAttributes(b)
  return first.cloneID == second.cloneID && first.privateSize == 0 && second.privateSize == 0
}
