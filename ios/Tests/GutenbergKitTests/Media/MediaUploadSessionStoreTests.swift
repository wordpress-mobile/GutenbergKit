import Foundation
import Testing

@testable import GutenbergKit

@Suite("MediaUploadSessionStore")
struct MediaUploadSessionStoreTests {
  private func makeStore(maxFileSize: Int = MediaUploadSessionStore.defaultMaxFileSize) -> MediaUploadSessionStore {
    MediaUploadSessionStore(
      directory: FileManager.default.temporaryDirectory.appending(component: "store-tests-\(UUID().uuidString)"),
      maxFileSize: maxFileSize
    )
  }

  @Test("assembles the chunks it receives into the file, in order")
  func assemblesChunks() async throws {
    let store = makeStore()
    let id = try await store.begin(filename: "clip.mp4", mimeType: "video/mp4", expectedSize: 10)

    #expect(try await store.append(Data("01234".utf8), to: id, at: 0) == 5)
    #expect(try await store.append(Data("56789".utf8), to: id, at: 5) == 10)
    let finished = try await store.take(id)
    defer { finished.cleanUp() }

    #expect(finished.isStagingCopy)
    #expect(finished.file.filename == "clip.mp4")
    #expect(finished.file.mimeType == "video/mp4")
    #expect(try Data(contentsOf: finished.file.url) == Data("0123456789".utf8))
  }

  @Test("refuses a chunk that doesn't start where the last one ended")
  func refusesOutOfOrderChunks() async throws {
    let store = makeStore()
    let id = try await store.begin(filename: "a.jpg", mimeType: "image/jpeg", expectedSize: nil)
    _ = try await store.append(Data("abc".utf8), to: id, at: 0)

    await #expect(throws: MediaUploadSessionStore.Failure.offsetMismatch(expected: 3, offset: 0)) {
      _ = try await store.append(Data("abc".utf8), to: id, at: 0)
    }
    await #expect(throws: MediaUploadSessionStore.Failure.offsetMismatch(expected: 3, offset: 9)) {
      _ = try await store.append(Data("abc".utf8), to: id, at: 9)
    }
  }

  @Test("refuses a file announced as larger than the limit")
  func refusesAnnouncedOversize() async throws {
    let store = makeStore(maxFileSize: 8)

    await #expect(throws: MediaUploadSessionStore.Failure.tooLarge(limit: 8)) {
      _ = try await store.begin(filename: "a.jpg", mimeType: "image/jpeg", expectedSize: 9)
    }
  }

  @Test("abandons a session whose chunks outgrow the limit")
  func abandonsOversizedSession() async throws {
    let store = makeStore(maxFileSize: 8)
    let id = try await store.begin(filename: "a.jpg", mimeType: "image/jpeg", expectedSize: nil)
    _ = try await store.append(Data("12345".utf8), to: id, at: 0)

    await #expect(throws: MediaUploadSessionStore.Failure.tooLarge(limit: 8)) {
      _ = try await store.append(Data("6789".utf8), to: id, at: 5)
    }
    await #expect(throws: MediaUploadSessionStore.Failure.unknownSession) { _ = try await store.take(id) }
  }

  @Test("refuses more bytes than the page announced")
  func refusesMoreThanAnnounced() async throws {
    let store = makeStore()
    let id = try await store.begin(filename: "a.jpg", mimeType: "image/jpeg", expectedSize: 3)

    await #expect(throws: MediaUploadSessionStore.Failure.tooLarge(limit: 3)) {
      _ = try await store.append(Data("abcd".utf8), to: id, at: 0)
    }
  }

  @Test("refuses to finish a file that is missing bytes, and deletes what arrived")
  func refusesIncompleteFile() async throws {
    let store = makeStore()
    let id = try await store.begin(filename: "a.jpg", mimeType: "image/jpeg", expectedSize: 6)
    _ = try await store.append(Data("abc".utf8), to: id, at: 0)

    await #expect(throws: MediaUploadSessionStore.Failure.incomplete(expected: 6, received: 3)) {
      _ = try await store.take(id)
    }
    await #expect(throws: MediaUploadSessionStore.Failure.unknownSession) { _ = try await store.take(id) }
  }

  @Test("finishes a session only once")
  func sessionsAreOneShot() async throws {
    let store = makeStore()
    let id = try await store.begin(filename: "a.jpg", mimeType: "image/jpeg", expectedSize: 0)

    let finished = try await store.take(id)
    finished.cleanUp()
    await #expect(throws: MediaUploadSessionStore.Failure.unknownSession) { _ = try await store.take(id) }
  }

  @Test("hands back a registered file as it is, and never deletes it")
  func registeredFiles() async throws {
    let store = makeStore()
    let url = try makeTemporaryFile(Data("imported".utf8), named: "IMG_0001.HEIC")
    let id = await store.register(MediaUploadFile(url: url, mimeType: "image/heic", filename: "IMG_0001.HEIC"))

    await #expect(throws: MediaUploadSessionStore.Failure.notReceiving) {
      _ = try await store.append(Data("x".utf8), to: id, at: 0)
    }
    let finished = try await store.take(id)
    finished.cleanUp()

    #expect(!finished.isStagingCopy)
    #expect(finished.file.url == url)
    #expect(FileManager.default.fileExists(atPath: url.path), "cleaned up a file the store doesn't own")
  }

  @Test("discarding a session deletes its staging copy")
  func discardDeletes() async throws {
    let store = makeStore()
    let id = try await store.begin(filename: "a.jpg", mimeType: "image/jpeg", expectedSize: nil)
    _ = try await store.append(Data("abc".utf8), to: id, at: 0)
    let staged = await store.directory.appending(component: id)

    await store.discard(id)

    #expect(!FileManager.default.fileExists(atPath: staged.path))
    #expect(await store.sessionCount == 0)
  }

  @Test("sweeps sessions that have sat idle")
  func sweepsIdleSessions() async throws {
    let store = makeStore()
    _ = try await store.begin(filename: "a.jpg", mimeType: "image/jpeg", expectedSize: nil)

    await store.sweep(idleFor: 3600)
    #expect(await store.sessionCount == 1, "swept a session that is still in use")

    await store.sweep(idleFor: -1)
    #expect(await store.sessionCount == 0)
  }

  @Test("removeAll abandons every session and its directory")
  func removeAll() async throws {
    let store = makeStore()
    _ = try await store.begin(filename: "a.jpg", mimeType: "image/jpeg", expectedSize: nil)
    _ = try await store.begin(filename: "b.jpg", mimeType: "image/jpeg", expectedSize: nil)

    await store.removeAll()

    #expect(await store.sessionCount == 0)
    #expect(!FileManager.default.fileExists(atPath: await store.directory.path))
  }

  @Test("keeps a crafted filename inside the session's directory")
  func sanitizesFilenames() async throws {
    #expect(MediaUploadSessionStore.sanitizeFilename("../../etc/passwd") == "passwd")
    #expect(MediaUploadSessionStore.sanitizeFilename("..") == "upload")
    #expect(MediaUploadSessionStore.sanitizeFilename("") == "upload")
    #expect(MediaUploadSessionStore.sanitizeFilename("a\\b.jpg") == "ab.jpg")

    let store = makeStore()
    let id = try await store.begin(filename: "../../escape.jpg", mimeType: "image/jpeg", expectedSize: 0)
    let finished = try await store.take(id)
    defer { finished.cleanUp() }
    #expect(finished.file.url.deletingLastPathComponent().lastPathComponent == id)
    #expect(finished.file.filename == "../../escape.jpg", "the filename sent to WordPress should be the page's")
  }
}
