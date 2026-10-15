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
    let (stream, contentLength) = try InternalMediaClient.multipartBodyStream(
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
    let (stream, _) = try InternalMediaClient.multipartBodyStream(
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

    let (stream, contentLength) = try InternalMediaClient.multipartBodyStream(
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

    let (stream, contentLength) = try InternalMediaClient.multipartBodyStream(
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

    let (stream, contentLength) = try InternalMediaClient.multipartBodyStream(
      fileURL: tempFile, boundary: "boundary", filename: "big.bin", mimeType: "application/octet-stream", extraFields: []
    )

    let result = readAllFromStream(stream)
    #expect(result.count == contentLength)
  }

  @Test("writeMultipartBody streams the full body and closing boundary when the file reads cleanly")
  func writeMultipartBodyWritesFullBody() throws {
    let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("wmb-\(UUID().uuidString)")
    let fileContent = Data("the file bytes".utf8)
    try fileContent.write(to: tempFile)
    defer { try? FileManager.default.removeItem(at: tempFile) }

    let fileHandle = try FileHandle(forReadingFrom: tempFile)
    defer { try? fileHandle.close() }

    let output = OutputStream.toMemory()
    output.open()
    defer { output.close() }

    let preamble = Data("PREAMBLE".utf8)
    let epilogue = Data("EPILOGUE".utf8)
    let ok = InternalMediaClient.writeMultipartBody(
      fileHandle: fileHandle, fileSize: fileContent.count,
      preamble: preamble, epilogue: epilogue, to: output
    )

    #expect(ok)
    let written = output.property(forKey: .dataWrittenToMemoryStreamKey) as? Data
    #expect(written == preamble + fileContent + epilogue)
  }

  @Test("writeMultipartBody aborts without the closing boundary when the file is shorter than measured")
  func writeMultipartBodyAbortsOnShortFile() throws {
    let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("wmb-short-\(UUID().uuidString)")
    let fileContent = Data("only ten!!".utf8) // 10 bytes
    try fileContent.write(to: tempFile)
    defer { try? FileManager.default.removeItem(at: tempFile) }

    let fileHandle = try FileHandle(forReadingFrom: tempFile)
    defer { try? fileHandle.close() }

    let output = OutputStream.toMemory()
    output.open()
    defer { output.close() }

    let preamble = Data("PREAMBLE".utf8)
    let epilogue = Data("EPILOGUE".utf8)
    // Claim the file is larger than it is, as if it shrank after being measured.
    let ok = InternalMediaClient.writeMultipartBody(
      fileHandle: fileHandle, fileSize: fileContent.count + 100,
      preamble: preamble, epilogue: epilogue, to: output
    )

    #expect(!ok)
    // The preamble and the real file bytes were written, but NOT the closing
    // boundary — a short body must not masquerade as a complete multipart.
    let written = (output.property(forKey: .dataWrittenToMemoryStreamKey) as? Data) ?? Data()
    #expect(written == preamble + fileContent)
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
