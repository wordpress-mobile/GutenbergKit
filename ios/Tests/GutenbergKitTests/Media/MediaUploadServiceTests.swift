import Foundation
import Testing

@testable import GutenbergKit

@Suite("MediaUploadService")
struct MediaUploadServiceTests {
  private let fields = [MediaUploadField(name: "post", value: "7"), MediaUploadField(name: "field[]", value: "a")]

  private func file(_ contents: String = "original bytes", mimeType: String = "image/jpeg") throws -> MediaUploadFile {
    MediaUploadFile(url: try makeTemporaryFile(Data(contents.utf8)), mimeType: mimeType, filename: "photo.jpg")
  }

  // MARK: - GutenbergKit's own client

  @Test("uploads the original file, fields, and query through the internal client")
  func uploadsThroughTheInternalClient() async throws {
    let client = RecordingInternalMediaClient()
    let service = MediaUploadService(processor: nil, uploader: nil, internalClient: client)
    let file = try file()

    let response = try await service.upload(file, fields: fields, query: "?_embed=wp:featuredmedia")

    #expect(response.statusCode == 201)
    let upload = try #require(client.uploads.first)
    #expect(upload.fileURL == file.url)
    #expect(upload.contents == Data("original bytes".utf8))
    #expect(upload.fields == fields)
    #expect(upload.query == "?_embed=wp:featuredmedia")
  }

  @Test("uploads the processor's file with the processor's metadata, then deletes it")
  func uploadsTheProcessedFile() async throws {
    let client = RecordingInternalMediaClient()
    let processor = ResizingProcessor()
    let service = MediaUploadService(processor: processor, uploader: nil, internalClient: client)
    let file = try file()

    _ = try await service.upload(file, fields: fields, query: "")

    let upload = try #require(client.uploads.first)
    #expect(upload.contents == Data("processed".utf8))
    #expect(upload.mimeType == "video/mp4")
    #expect(upload.filename == "clip.mp4")
    let produced = try #require(processor.producedURL)
    #expect(!FileManager.default.fileExists(atPath: produced.path), "the processed file outlived the upload")
    #expect(FileManager.default.fileExists(atPath: file.url.path), "the service deleted a file it doesn't own")
  }

  @Test("a value-type processor is admitted, called, and its result delivered")
  func valueTypeProcessor() async throws {
    let client = RecordingInternalMediaClient()
    let service = MediaUploadService(processor: ValueTypeProcessor(), uploader: nil, internalClient: client)

    _ = try await service.upload(try file(), fields: [], query: "")

    #expect(client.uploads.first?.contents == Data("transcoded".utf8))
  }

  @Test("skips processFile for a file the processor declines by metadata")
  func declinedByMetadata() async throws {
    let client = RecordingInternalMediaClient()
    let processor = DeclineByMetadataProcessor()
    let service = MediaUploadService(processor: processor, uploader: nil, internalClient: client)

    _ = try await service.upload(try file(), fields: [], query: "")

    #expect(!processor.processFileCalled)
    #expect(client.uploads.first?.contents == Data("original bytes".utf8))
  }

  @Test("relays a non-2xx WordPress response instead of throwing")
  func relaysWordPressErrors() async throws {
    let client = RecordingInternalMediaClient(response: MediaUploadResponse(
      statusCode: 500,
      body: Data(#"{"code":"rest_upload_sideload_error"}"#.utf8),
      headers: ["x-wp-upload-attachment-id": "42"]
    ))
    let service = MediaUploadService(processor: nil, uploader: nil, internalClient: client)

    let response = try await service.upload(try file(), fields: [], query: "")

    #expect(response.statusCode == 500)
    #expect(response.headers["x-wp-upload-attachment-id"] == "42")
  }

  // MARK: - The host's uploader

  @Test("an uploader performs the upload and receives the fields and query")
  func uploaderReceivesFieldsAndQuery() async throws {
    let uploader = RecordingUploader()
    let client = RecordingInternalMediaClient()
    let service = MediaUploadService(processor: nil, uploader: uploader, internalClient: client)

    let response = try await service.upload(try file(), fields: fields, query: "?_embed")

    #expect(response.statusCode == 201)
    #expect(String(decoding: response.body, as: UTF8.self).contains(#""id":7"#))
    #expect(uploader.received?.fields == fields)
    #expect(uploader.received?.query == "?_embed")
    #expect(client.uploads.isEmpty, "GutenbergKit uploaded a file the host's uploader owns")
  }

  @Test("a processor still processes the file an uploader delivers")
  func processorBeforeUploader() async throws {
    let uploader = RecordingUploader()
    let service = MediaUploadService(processor: ResizingProcessor(), uploader: uploader, internalClient: nil)

    _ = try await service.upload(try file(), fields: [], query: "")

    #expect(uploader.receivedContents == Data("processed".utf8))
    #expect(uploader.received?.mimeType == "video/mp4")
  }

  @Test("an uploader sees a file the processor's metadata gate declined, unprocessed")
  func uploaderGetsDeclinedFile() async throws {
    let uploader = RecordingUploader()
    let processor = DeclineByMetadataProcessor()
    let service = MediaUploadService(processor: processor, uploader: uploader, internalClient: nil)

    _ = try await service.upload(try file(), fields: [], query: "")

    #expect(!processor.processFileCalled)
    #expect(uploader.receivedContents == Data("original bytes".utf8))
  }

  @Test("an uploader that throws surfaces as a failure, with no GutenbergKit retry")
  func throwingUploader() async throws {
    let client = RecordingInternalMediaClient()
    let service = MediaUploadService(processor: nil, uploader: ThrowingUploader(), internalClient: client)

    await #expect(throws: ThrowingUploader.Failure.self) {
      _ = try await service.upload(try file(), fields: [], query: "")
    }
    #expect(client.uploads.isEmpty)
  }

  // MARK: - Cancellation and configuration

  @Test("doesn't start an upload once the task is cancelled")
  func cancelledBeforeDelivery() async throws {
    let client = RecordingInternalMediaClient()
    let gate = AsyncGate()
    let service = MediaUploadService(processor: GatedProcessor(gate: gate), uploader: nil, internalClient: client)
    let file = try file()

    let upload = Task { try await service.upload(file, fields: [], query: "") }
    await gate.waitUntilEntered()
    upload.cancel()
    await gate.open()

    await #expect(throws: CancellationError.self) { _ = try await upload.value }
    #expect(client.uploads.isEmpty, "uploaded a file nobody will read the response for")
  }

  @Test("fails without an uploader or an internal client")
  func noUploader() async throws {
    let service = MediaUploadService(processor: nil, uploader: nil, internalClient: nil)

    await #expect(throws: UploadError.self) {
      _ = try await service.upload(try file(), fields: [], query: "")
    }
  }

  @Test("deletes through the internal client, carrying the query")
  func deletes() async throws {
    let client = RecordingInternalMediaClient()
    let service = MediaUploadService(processor: nil, uploader: RecordingUploader(), internalClient: client)

    let response = try await service.delete(attachmentId: "42", query: "?force=true")

    #expect(response.statusCode == 200)
    #expect(client.deletes.first?.id == "42")
    #expect(client.deletes.first?.query == "?force=true")
  }
}

/// A one-shot gate: a waiter parks until someone opens it.
actor AsyncGate {
  private var isOpen = false
  private var entered = false
  private var waiters: [CheckedContinuation<Void, Never>] = []
  private var enterWaiters: [CheckedContinuation<Void, Never>] = []

  func enter() async {
    entered = true
    enterWaiters.forEach { $0.resume() }
    enterWaiters.removeAll()
    guard !isOpen else { return }
    await withCheckedContinuation { waiters.append($0) }
  }

  func waitUntilEntered() async {
    guard !entered else { return }
    await withCheckedContinuation { enterWaiters.append($0) }
  }

  func open() {
    isOpen = true
    waiters.forEach { $0.resume() }
    waiters.removeAll()
  }
}

/// A processor that parks in `processFile` until its gate opens.
struct GatedProcessor: MediaProcessor {
  let gate: AsyncGate

  func processFile(at url: URL, mimeType: String, filename: String) async throws -> ProcessedProxyFile {
    await gate.enter()
    return .original
  }
}
