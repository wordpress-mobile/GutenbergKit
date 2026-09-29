import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

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

  @Test("maps a file back to the gbk-media-file URL that names it")
  func mediaURLRoundTrips() throws {
    let file = root.appending(component: "Uploads/abc/IMG 0001.HEIC")
    let url = try #require(MediaFileManager.mediaURL(forFile: file, root: root))

    #expect(url.absoluteString == "gbk-media-file:///Uploads/abc/IMG%200001.HEIC")
    #expect(MediaFileManager.fileURL(for: url, root: root) == file.standardizedFileURL)
    #expect(MediaFileManager.mediaURL(forFile: URL(fileURLWithPath: "/etc/hosts"), root: root) == nil)
  }

  @Test("writes a JPEG preview of an image next to it")
  func imagePreview() async throws {
    let image = try makeTemporaryFile(try pngData(width: 3000, height: 2000), named: "big.png")

    let preview = try #require(await MediaPreview.write(for: image, mimeType: "image/png"))

    #expect(preview.deletingLastPathComponent() == image.deletingLastPathComponent())
    let source = try #require(CGImageSourceCreateWithURL(preview as CFURL, nil))
    #expect(CGImageSourceGetType(source) as String? == UTType.jpeg.identifier)
    let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
    #expect(properties[kCGImagePropertyPixelWidth] as? Int == MediaPreview.maxPixelSize)
  }

  @Test("has no preview for a file that isn't an image or video")
  func noPreviewForDocuments() async throws {
    let document = try makeTemporaryFile(Data("%PDF-1.7".utf8), named: "a.pdf")

    #expect(await MediaPreview.write(for: document, mimeType: "application/pdf") == nil)
  }

  private func pngData(width: Int, height: Int) throws -> Data {
    let context = try #require(CGContext(
      data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ))
    context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let image = try #require(context.makeImage())
    let data = NSMutableData()
    let destination = try #require(CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
    CGImageDestinationAddImage(destination, image, nil)
    #expect(CGImageDestinationFinalize(destination))
    return data as Data
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
