@preconcurrency import Darwin
import Foundation
import Testing

@testable import GutenbergKit

// MARK: - Streaming Multipart Body Tests

@Suite("InternalMediaClient streaming multipart body")
struct MultipartBodyStreamTests {

  @Test("streaming output matches in-memory multipart format")
  func streamMatchesInMemory() throws {
    let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("stream-test-\(UUID().uuidString)")
    let fileContent = Data("hello world".utf8)
    try fileContent.write(to: tempFile)
    defer { try? FileManager.default.removeItem(at: tempFile) }

    let boundary = "test-boundary-123"
    let filename = "photo.jpg"
    let mimeType = "image/jpeg"

    // Build expected output using the old in-memory approach.
    var expected = Data()
    expected.append(Data("--\(boundary)\r\n".utf8))
    expected.append(Data("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n".utf8))
    expected.append(Data("Content-Type: \(mimeType)\r\n\r\n".utf8))
    expected.append(fileContent)
    expected.append(Data("\r\n--\(boundary)--\r\n".utf8))

    // Build streaming output.
    let (stream, contentLength, _) = try InternalMediaClient.multipartBodyStream(
      fileURL: tempFile, boundary: boundary, filename: filename, mimeType: mimeType, extraFields: []
    )
    #expect(contentLength == expected.count)

    let result = readAllFromStream(stream)
    #expect(result == expected)
  }

  @Test("escapes CR/LF and quotes so a crafted filename can't inject headers or parts")
  func escapesHeaderInjection() throws {
    let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("stream-test-\(UUID().uuidString)")
    try Data("file-bytes".utf8).write(to: tempFile)
    defer { try? FileManager.default.removeItem(at: tempFile) }

    // Craft a filename, field name, and MIME type that each try to smuggle a CRLF
    // and a fake header into the body relayed to WordPress.
    let (stream, _, _) = try InternalMediaClient.multipartBodyStream(
      fileURL: tempFile,
      boundary: "boundary",
      filename: "evil\"\r\nX-Injected-File: 1.jpg",
      mimeType: "image/jpeg\r\nX-Injected-Type: 1",
      extraFields: [("field\"\r\nX-Injected-Name: 1", Data("v".utf8))]
    )
    let text = String(decoding: readAllFromStream(stream), as: UTF8.self)

    // None of the crafted CRLF sequences may survive as a real header break.
    #expect(!text.contains("\r\nX-Injected-File:"))
    #expect(!text.contains("\r\nX-Injected-Type:"))
    #expect(!text.contains("\r\nX-Injected-Name:"))
  }

  @Test("includes non-file parts (e.g. post) ahead of the file")
  func multipartBodyIncludesExtraParts() throws {
    let boundary = "boundary"
    let filename = "photo.jpg"
    let mimeType = "image/jpeg"
    let fileContent = Data("image bytes".utf8)
    let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("stream-extra-\(UUID().uuidString)")
    try fileContent.write(to: tempFile)
    defer { try? FileManager.default.removeItem(at: tempFile) }

    var expected = Data()
    expected.append(Data("--\(boundary)\r\n".utf8))
    expected.append(Data("Content-Disposition: form-data; name=\"post\"\r\n\r\n".utf8))
    expected.append(Data("123\r\n".utf8))
    expected.append(Data("--\(boundary)\r\n".utf8))
    expected.append(Data("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n".utf8))
    expected.append(Data("Content-Type: \(mimeType)\r\n\r\n".utf8))
    expected.append(fileContent)
    expected.append(Data("\r\n--\(boundary)--\r\n".utf8))

    let (stream, contentLength, _) = try InternalMediaClient.multipartBodyStream(
      fileURL: tempFile, boundary: boundary, filename: filename, mimeType: mimeType,
      extraFields: [("post", Data("123".utf8))]
    )
    #expect(contentLength == expected.count)
    #expect(readAllFromStream(stream) == expected)
  }

  @Test("forwards a non-UTF-8 field value verbatim")
  func multipartBodyPreservesNonUTF8FieldValue() throws {
    let boundary = "boundary"
    let filename = "photo.jpg"
    let mimeType = "image/jpeg"
    let fileContent = Data("image bytes".utf8)
    let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("stream-binary-\(UUID().uuidString)")
    try fileContent.write(to: tempFile)
    defer { try? FileManager.default.removeItem(at: tempFile) }

    // A field value that is not valid UTF-8 (a lone 0xFF byte between ASCII bytes).
    let binaryValue = Data([0x61, 0xFF, 0x62])

    var expected = Data()
    expected.append(Data("--\(boundary)\r\n".utf8))
    expected.append(Data("Content-Disposition: form-data; name=\"blob\"\r\n\r\n".utf8))
    expected.append(binaryValue)
    expected.append(Data("\r\n".utf8))
    expected.append(Data("--\(boundary)\r\n".utf8))
    expected.append(Data("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n".utf8))
    expected.append(Data("Content-Type: \(mimeType)\r\n\r\n".utf8))
    expected.append(fileContent)
    expected.append(Data("\r\n--\(boundary)--\r\n".utf8))

    let (stream, contentLength, _) = try InternalMediaClient.multipartBodyStream(
      fileURL: tempFile, boundary: boundary, filename: filename, mimeType: mimeType,
      extraFields: [("blob", binaryValue)]
    )
    #expect(contentLength == expected.count)
    // The raw 0xFF byte survives — it was not coerced through String.
    #expect(readAllFromStream(stream) == expected)
  }

  @Test("content length matches actual stream output for larger files")
  func contentLengthAccurate() throws {
    let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("stream-test-\(UUID().uuidString)")
    let fileContent = Data(repeating: 0x42, count: 100_000)
    try fileContent.write(to: tempFile)
    defer { try? FileManager.default.removeItem(at: tempFile) }

    let (stream, contentLength, _) = try InternalMediaClient.multipartBodyStream(
      fileURL: tempFile, boundary: "boundary", filename: "big.bin", mimeType: "application/octet-stream", extraFields: []
    )

    let result = readAllFromStream(stream)
    #expect(result.count == contentLength)
  }

  @Test("streams a large file without holding it in memory")
  func streamsWithoutAccumulating() throws {
    // A sparse file: 96 MB long without 96 MB being written, or held by this test.
    let megabyte = 1024 * 1024
    let fileSize = 96 * megabyte
    let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("stream-test-\(UUID().uuidString)")
    #expect(FileManager.default.createFile(atPath: tempFile.path(percentEncoded: false), contents: nil))
    defer { try? FileManager.default.removeItem(at: tempFile) }
    let handle = try FileHandle(forWritingTo: tempFile)
    try handle.truncate(atOffset: UInt64(fileSize))
    try handle.close()

    let (stream, contentLength, _) = try InternalMediaClient.multipartBodyStream(
      fileURL: tempFile, boundary: "boundary", filename: "big.bin", mimeType: "application/octet-stream", extraFields: []
    )
    stream.open()
    defer { stream.close() }

    // Sampled while the body is still being produced: whatever the writer was
    // holding is freed once it finishes, so a measurement afterwards shows nothing.
    let baseline = memoryFootprint()
    var peak = baseline
    var total = 0
    var sinceSample = 0
    var buffer = [UInt8](repeating: 0, count: 65_536)
    while true {
      let read = stream.read(&buffer, maxLength: buffer.count)
      if read <= 0 { break }
      total += read
      sinceSample += read
      if sinceSample >= megabyte {
        sinceSample = 0
        peak = max(peak, memoryFootprint())
      }
    }

    #expect(total == contentLength)
    // Half the file's size: far above what a 64 KB chunk and other tests running
    // alongside need, far below what holding the file takes.
    let growth = peak > baseline ? peak - baseline : 0
    #expect(growth < UInt64(fileSize / 2), "streaming a \(fileSize / megabyte) MB file grew memory by \(growth / UInt64(megabyte)) MB")
  }

  @Test("the writer sends the full body and closing boundary when the file reads cleanly")
  func writerSendsFullBody() async throws {
    let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("wmb-\(UUID().uuidString)")
    let fileContent = Data("the file bytes".utf8)
    try fileContent.write(to: tempFile)
    defer { try? FileManager.default.removeItem(at: tempFile) }

    let output = OutputStream.toMemory()
    let preamble = Data("PREAMBLE".utf8)
    let epilogue = Data("EPILOGUE".utf8)
    let writer = MultipartBodyWriter(
      fileHandle: try FileHandle(forReadingFrom: tempFile), fileSize: fileContent.count,
      preamble: preamble, epilogue: epilogue, output: output
    )

    let wroteEverything = await finish(writer)

    #expect(wroteEverything)
    let written = output.property(forKey: .dataWrittenToMemoryStreamKey) as? Data
    #expect(written == preamble + fileContent + epilogue)
  }

  @Test("the writer stops without the closing boundary when the file is shorter than measured")
  func writerStopsOnShortFile() async throws {
    let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("wmb-short-\(UUID().uuidString)")
    let fileContent = Data("only ten!!".utf8) // 10 bytes
    try fileContent.write(to: tempFile)
    defer { try? FileManager.default.removeItem(at: tempFile) }

    let output = OutputStream.toMemory()
    let preamble = Data("PREAMBLE".utf8)
    let epilogue = Data("EPILOGUE".utf8)
    // Claim the file is larger than it is, as if it shrank after being measured.
    let writer = MultipartBodyWriter(
      fileHandle: try FileHandle(forReadingFrom: tempFile), fileSize: fileContent.count + 100,
      preamble: preamble, epilogue: epilogue, output: output
    )

    let wroteEverything = await finish(writer)

    #expect(!wroteEverything)
    // The preamble and the real file bytes were written, but NOT the closing
    // boundary — a short body must not masquerade as a complete multipart.
    let written = (output.property(forKey: .dataWrittenToMemoryStreamKey) as? Data) ?? Data()
    #expect(written == preamble + fileContent)
  }

  @Test("the writer stops when its reader closes the stream")
  func writerStopsWhenTheReaderLeaves() async throws {
    let (input, writer) = try pairedWriter(fileSize: 1024 * 1024)
    input.open()

    async let wroteEverything = finish(writer)
    // Take part of the body, then go: the request was cancelled, or failed.
    var buffer = [UInt8](repeating: 0, count: 8192)
    _ = input.read(&buffer, maxLength: buffer.count)
    input.close()

    #expect(await wroteEverything == false)
  }

  @Test("cancel stops a writer whose reader never opened the stream")
  func cancelStopsAWriterNobodyRead() async throws {
    // A reader that never opens its end sends the writer no event when it goes, so
    // without `cancel` the writer would keep the file open for good.
    let (input, writer) = try pairedWriter(fileSize: 1024 * 1024)

    async let wroteEverything = finish(writer)
    try await Task.sleep(for: .milliseconds(50))
    input.close()
    writer.cancel()

    #expect(await wroteEverything == false)
  }

  @Test("bodies nobody is reading yet hold no threads")
  func unreadBodiesHoldNoThreads() async throws {
    let megabyte = 1024 * 1024
    let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("stream-test-\(UUID().uuidString)")
    try Data(repeating: 0x42, count: megabyte).write(to: tempFile)
    defer { try? FileManager.default.removeItem(at: tempFile) }

    // A hundred uploads waiting for a connection: each has more to send than the
    // stream will hold, and nobody is taking it.
    let before = threadCount()
    var bodies: [(InputStream, MultipartBodyWriter)] = []
    for _ in 0..<100 {
      let (stream, _, writer) = try InternalMediaClient.multipartBodyStream(
        fileURL: tempFile, boundary: "boundary", filename: "big.bin", mimeType: "application/octet-stream", extraFields: []
      )
      bodies.append((stream, writer))
    }
    try await Task.sleep(for: .milliseconds(300))
    let during = threadCount()

    for (stream, writer) in bodies {
      stream.close()
      writer.cancel()
    }
    // Far fewer than one each, with room for whatever else is running alongside.
    #expect(during - before < 30, "a hundred unread bodies added \(during - before) threads")
  }

  /// Starts `writer` and waits for it to finish. `true` if it wrote the whole body.
  private func finish(_ writer: MultipartBodyWriter) async -> Bool {
    await withCheckedContinuation { continuation in
      writer.start { continuation.resume(returning: $0) }
    }
  }

  /// A writer for a file of `fileSize` zero bytes, and the stream its reader would read.
  private func pairedWriter(fileSize: Int) throws -> (InputStream, MultipartBodyWriter) {
    let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("wmb-pair-\(UUID().uuidString)")
    try Data(count: fileSize).write(to: tempFile)
    defer { try? FileManager.default.removeItem(at: tempFile) }

    var input: InputStream?
    var output: OutputStream?
    Stream.getBoundStreams(withBufferSize: 65_536, inputStream: &input, outputStream: &output)
    let writer = MultipartBodyWriter(
      fileHandle: try FileHandle(forReadingFrom: tempFile), fileSize: fileSize,
      preamble: Data("PREAMBLE".utf8), epilogue: Data("EPILOGUE".utf8), output: try #require(output)
    )
    return (try #require(input), writer)
  }
}

// MARK: - InternalMediaClient Relay Tests

@Suite("InternalMediaClient relay")
struct InternalMediaClientRelayTests {

  @Test("relays a non-2xx WordPress response instead of throwing")
  func relaysErrorResponseVerbatim() async throws {
    // A WordPress REST error body, returned with a non-2xx status.
    let errorBody = Data(#"{"code":"rest_cannot_create","message":"Sorry, you are not allowed to upload this file type."}"#.utf8)
    let client = RelayStubHTTPClient(statusCode: 403, body: errorBody)
    let uploader = InternalMediaClient(httpClient: client, siteApiRoot: URL(string: "https://example.com/wp-json/")!)

    let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("relay-\(UUID().uuidString).jpg")
    try Data("fake image".utf8).write(to: tempFile)
    defer { try? FileManager.default.removeItem(at: tempFile) }

    // performUpload must route through performRaw, which does NOT validate status,
    // so WordPress's 403 + body flow through verbatim. A revert to perform() would
    // throw on the non-2xx (RelayStubHTTPClient.perform mirrors that), failing here.
    let response = try await uploader.upload(
      fileURL: tempFile, mimeType: "image/jpeg", filename: "photo.jpg", fields: [], query: ""
    )

    #expect(response.statusCode == 403)
    #expect(response.body == errorBody)
  }

  @Test("relays the upload attachment ID header from a failed upload")
  func relaysUploadAttachmentIdHeader() async throws {
    // WordPress sets this header on an upload whose attachment row was created
    // before metadata generation fataled. The editor reads it to retry
    // post-process and clean up the orphan, so it must survive the relay.
    let client = RelayStubHTTPClient(
      statusCode: 500,
      body: Data(#"{"code":"rest_upload_error"}"#.utf8),
      headerFields: ["x-wp-upload-attachment-id": "4242"]
    )
    let uploader = InternalMediaClient(
      httpClient: client, siteApiRoot: URL(string: "https://example.com/wp-json/")!)

    let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent(
      "header-\(UUID().uuidString).jpg")
    try Data("fake image".utf8).write(to: tempFile)
    defer { try? FileManager.default.removeItem(at: tempFile) }

    let response = try await uploader.upload(
      fileURL: tempFile, mimeType: "image/jpeg", filename: "photo.jpg", fields: [], query: ""
    )

    #expect(response.statusCode == 500)
    #expect(response.headers["x-wp-upload-attachment-id"] == "4242")
  }

  @Test("omits unrelated upstream headers from the relay")
  func omitsUnrelatedHeaders() async throws {
    let client = RelayStubHTTPClient(
      statusCode: 201,
      body: Data("{}".utf8),
      headerFields: ["X-Powered-By": "PHP/8.2", "Set-Cookie": "session=secret"]
    )
    let uploader = InternalMediaClient(
      httpClient: client, siteApiRoot: URL(string: "https://example.com/wp-json/")!)

    let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent(
      "unrelated-\(UUID().uuidString).jpg")
    try Data("fake image".utf8).write(to: tempFile)
    defer { try? FileManager.default.removeItem(at: tempFile) }

    let response = try await uploader.upload(
      fileURL: tempFile, mimeType: "image/jpeg", filename: "photo.jpg", fields: [], query: ""
    )

    #expect(response.headers.isEmpty)
  }

  @Test("deletes an attachment, carrying the namespace and force query")
  func deletesAttachment() async throws {
    let client = URLCapturingHTTPClient()
    let uploader = InternalMediaClient(
      httpClient: client,
      siteApiRoot: URL(string: "https://example.com/wp-json")!,
      siteApiNamespace: ["sites/123"]
    )

    _ = try await uploader.deleteMedia(attachmentId: "42", query: "?force=true")

    let url = try #require(client.lastURL)
    #expect(
      url.absoluteString == "https://example.com/wp-json/wp/v2/sites/123/media/42?force=true")
  }

  @Test("carries the namespace and request query through to the media endpoint")
  func forwardsNamespaceAndQuery() async throws {
    let client = URLCapturingHTTPClient()
    let uploader = InternalMediaClient(
      httpClient: client,
      siteApiRoot: URL(string: "https://example.com/wp-json")!,
      siteApiNamespace: ["sites/123"]
    )
    let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("query-\(UUID().uuidString).jpg")
    try Data("img".utf8).write(to: tempFile)
    defer { try? FileManager.default.removeItem(at: tempFile) }

    _ = try await uploader.upload(
      fileURL: tempFile, mimeType: "image/jpeg", filename: "photo.jpg",
      fields: [], query: "?_embed=wp:featuredmedia"
    )

    // Namespace inserted via the shared builder, and the query preserved verbatim —
    // including the `:`, which would make URL(string:) return nil and drop it (#6).
    let url = try #require(client.lastURL)
    #expect(url.absoluteString == "https://example.com/wp-json/wp/v2/sites/123/media?_embed=wp:featuredmedia")
  }

  // The page sends the query as it wrote it, and `URLComponents.percentEncodedQuery`
  // traps on a character a URL can't hold: before these were encoded, each of the
  // first four ended the process.
  @Test(
    "encodes a query the page sent raw, and keeps the escapes it already has",
    arguments: [
      ("?title=café", "title=caf%C3%A9"),
      ("?title=a b", "title=a%20b"),
      ("?title=\"a\"", "title=%22a%22"),
      ("?title=50%zz", "title=50%25zz"),
      ("?title=a%20b", "title=a%20b"),
      ("?include[]=1&include[]=2", "include%5B%5D=1&include%5B%5D=2"),
    ]
  )
  func encodesRawQueries(query: String, expected: String) async throws {
    let client = URLCapturingHTTPClient()
    let uploader = InternalMediaClient(httpClient: client, siteApiRoot: URL(string: "https://example.com/wp-json")!)

    _ = try await uploader.deleteMedia(attachmentId: "42", query: query)

    let url = try #require(client.lastURL)
    #expect(url.absoluteString == "https://example.com/wp-json/wp/v2/media/42?\(expected)")
  }

  @Test("sends the editor's fields ahead of the file, in order, with repeated names intact")
  func sendsFieldsInOrder() async throws {
    let client = BodyCapturingHTTPClient()
    let uploader = InternalMediaClient(httpClient: client, siteApiRoot: URL(string: "https://example.com/wp-json/")!)
    let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("fields-\(UUID().uuidString).jpg")
    try Data("img".utf8).write(to: tempFile)
    defer { try? FileManager.default.removeItem(at: tempFile) }

    _ = try await uploader.upload(
      fileURL: tempFile, mimeType: "image/jpeg", filename: "photo.jpg",
      fields: [
        MediaUploadField(name: "post", value: "7"),
        MediaUploadField(name: "field[]", value: "a"),
        MediaUploadField(name: "field[]", value: "日本語"),
      ],
      query: ""
    )

    let body = String(decoding: try #require(client.lastBody), as: UTF8.self)
    let post = try #require(body.range(of: "name=\"post\"\r\n\r\n7\r\n"))
    let first = try #require(body.range(of: "name=\"field[]\"\r\n\r\na\r\n"))
    let second = try #require(body.range(of: "name=\"field[]\"\r\n\r\n日本語\r\n"))
    let file = try #require(body.range(of: "name=\"file\"; filename=\"photo.jpg\""))
    #expect(post.lowerBound < first.lowerBound)
    #expect(first.lowerBound < second.lowerBound)
    #expect(second.lowerBound < file.lowerBound)
  }
}

/// The memory this process is charged for, in bytes.
private func memoryFootprint() -> UInt64 {
  var info = task_vm_info_data_t()
  var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
  let result = withUnsafeMutablePointer(to: &info) {
    $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
      task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
    }
  }
  return result == KERN_SUCCESS ? info.phys_footprint : 0
}

/// How many threads this process has.
private func threadCount() -> Int {
  var threads: thread_act_array_t?
  var count: mach_msg_type_number_t = 0
  guard task_threads(mach_task_self_, &threads, &count) == KERN_SUCCESS, let threads else { return 0 }
  vm_deallocate(
    mach_task_self_,
    vm_address_t(UInt(bitPattern: threads)),
    vm_size_t(Int(count) * MemoryLayout<thread_t>.stride)
  )
  return Int(count)
}
