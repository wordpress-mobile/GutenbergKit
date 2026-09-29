import Foundation
import Testing
import WebKit

@testable import GutenbergKit

@MainActor
@Suite("MediaFileSchemeHandler")
struct MediaFileSchemeHandlerTests {
  private let root = FileManager.default.temporaryDirectory.appending(component: "media-root-\(UUID().uuidString)")

  private func writeUpload(_ contents: Data, named name: String) throws {
    let uploads = root.appending(component: "Uploads")
    try FileManager.default.createDirectory(at: uploads, withIntermediateDirectories: true)
    try contents.write(to: uploads.appending(component: name))
  }

  private func request(_ path: String) -> FakeSchemeTask {
    FakeSchemeTask(request: URLRequest(url: URL(string: "gbk-media-file://\(path)")!))
  }

  @Test("streams a file larger than one chunk, intact, with its type and length")
  func streamsFiles() async throws {
    let contents = Data((0..<(MediaFileSchemeHandler.chunkSize * 2 + 17)).map { UInt8($0 % 251) })
    try writeUpload(contents, named: "clip.mp4")
    let handler = MediaFileSchemeHandler(rootURL: root)
    let task = request("/Uploads/clip.mp4")

    handler.start(task)
    await task.waitUntilAnswered()

    #expect(task.status == 200)
    #expect(task.header("Content-Type") == "video/mp4")
    #expect(task.header("Content-Length") == "\(contents.count)")
    #expect(task.header("Access-Control-Allow-Origin") == "*")
    #expect(task.body == contents)
    #expect(handler.activeRequestCount == 0)
  }

  @Test("serves a filename that needs percent-encoding")
  func servesEncodedNames() async throws {
    try writeUpload(Data("hi".utf8), named: "IMG 0001.HEIC")
    let handler = MediaFileSchemeHandler(rootURL: root)
    let task = request("/Uploads/IMG%200001.HEIC")

    handler.start(task)
    await task.waitUntilAnswered()

    #expect(task.body == Data("hi".utf8))
  }

  @Test("refuses a path that would escape the media directory")
  func refusesTraversal() async throws {
    let handler = MediaFileSchemeHandler(rootURL: root)
    let task = request("/Uploads/../../../../etc/hosts")

    handler.start(task)
    await task.waitUntilAnswered()

    #expect(task.response == nil)
    #expect((task.failure as? URLError)?.code == .badURL)
  }

  @Test("fails a request for a file that doesn't exist")
  func missingFiles() async throws {
    let handler = MediaFileSchemeHandler(rootURL: root)
    let task = request("/Uploads/missing.jpg")

    handler.start(task)
    await task.waitUntilAnswered()

    #expect(task.failure != nil)
    #expect(handler.activeRequestCount == 0)
  }

  @Test("stops delivering to a request WebKit stopped")
  func stopsDelivering() async throws {
    let contents = Data(count: MediaFileSchemeHandler.chunkSize * 8)
    try writeUpload(contents, named: "big.bin")
    let handler = MediaFileSchemeHandler(rootURL: root)
    let task = request("/Uploads/big.bin")

    handler.start(task)
    handler.stop(task)
    try await Task.sleep(for: .milliseconds(100))

    #expect(!task.finished, "finished a stopped task, which WebKit raises on")
    #expect(task.body.count < contents.count)
    #expect(handler.activeRequestCount == 0)
  }

  @Test("resolves only paths inside the root")
  func resolvesPaths() {
    #expect(MediaFileManager.fileURL(for: URL(string: "gbk-media-file:///Uploads/a.jpg")!, root: root)?.lastPathComponent == "a.jpg")
    #expect(MediaFileManager.fileURL(for: URL(string: "gbk-media-file:///../a.jpg")!, root: root) == nil)
    #expect(MediaFileManager.fileURL(for: URL(string: "gbk-media-file:///Uploads/%2E%2E/%2E%2E/a.jpg")!, root: root) == nil)
  }
}
