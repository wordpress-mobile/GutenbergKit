import Foundation
import Testing
@testable import GutenbergKitHTTP

/// Tests for the chunked (file-backed) multipart parsing path.
///
/// The in-memory path is tested extensively in ``RFC7578ConformanceTests`` and
/// the shared fixture tests. These tests verify the chunked scanner that runs
/// when the body is backed by a file on disk.
@Suite("Chunked Multipart Parsing")
struct ChunkedMultipartTests {

    // MARK: - Basic Parsing

    @Test("single text field parsed from file-backed body")
    func singleTextField() throws {
        let (url, request) = try makeFileBackedRequest(
            fields: [("title", nil, nil, Data("My Blog Post".utf8))],
            boundary: "AaB03x"
        )
        defer { try? FileManager.default.removeItem(at: url) }

        let parts = try request.multipartParts()

        #expect(parts.count == 1)
        #expect(parts[0].name == "title")
        #expect(parts[0].filename == nil)
        #expect(parts[0].contentType == "text/plain")
        #expect(try readAll(parts[0].body) == Data("My Blog Post".utf8))
    }

    @Test("multiple parts parsed from file-backed body")
    func multipleParts() throws {
        let (url, request) = try makeFileBackedRequest(
            fields: [
                ("title", nil, nil, Data("Hello".utf8)),
                ("file", "photo.jpg", "image/jpeg", Data("jpeg-data".utf8)),
                ("caption", nil, nil, Data("A photo".utf8)),
            ],
            boundary: "WebKitBoundary123"
        )
        defer { try? FileManager.default.removeItem(at: url) }

        let parts = try request.multipartParts()

        #expect(parts.count == 3)
        #expect(parts[0].name == "title")
        #expect(try readAll(parts[0].body) == Data("Hello".utf8))
        #expect(parts[1].name == "file")
        #expect(parts[1].filename == "photo.jpg")
        #expect(parts[1].contentType == "image/jpeg")
        #expect(try readAll(parts[1].body) == Data("jpeg-data".utf8))
        #expect(parts[2].name == "caption")
        #expect(try readAll(parts[2].body) == Data("A photo".utf8))
    }

    @Test("empty part body parsed correctly")
    func emptyPartBody() throws {
        let (url, request) = try makeFileBackedRequest(
            fields: [("empty", nil, nil, Data())],
            boundary: "AaB03x"
        )
        defer { try? FileManager.default.removeItem(at: url) }

        let parts = try request.multipartParts()

        #expect(parts.count == 1)
        #expect(parts[0].name == "empty")
        #expect(try readAll(parts[0].body) == Data())
    }

    @Test("binary data preserved through file-backed parsing")
    func binaryData() throws {
        // Include bytes that would be problematic if treated as text: NUL, 0xFF, CRLF sequences.
        var binaryContent = Data(repeating: 0x00, count: 128)
        binaryContent.append(contentsOf: (0...255).map { UInt8($0) })
        binaryContent.append(Data(repeating: 0xFF, count: 128))

        let (url, request) = try makeFileBackedRequest(
            fields: [("file", "binary.bin", "application/octet-stream", binaryContent)],
            boundary: "BinaryBoundary99"
        )
        defer { try? FileManager.default.removeItem(at: url) }

        let parts = try request.multipartParts()

        #expect(parts.count == 1)
        #expect(parts[0].filename == "binary.bin")
        #expect(try readAll(parts[0].body) == binaryContent)
    }

    @Test("preamble before first boundary is ignored")
    func preambleIgnored() throws {
        let boundary = "AaB03x"
        let preamble = "This is the preamble. It should be ignored.\r\n"
        let body = "\(preamble)--\(boundary)\r\nContent-Disposition: form-data; name=\"field\"\r\n\r\nvalue\r\n--\(boundary)--\r\n"

        let (url, request) = try makeFileBackedRequestFromRawBody(body: body, boundary: boundary)
        defer { try? FileManager.default.removeItem(at: url) }

        let parts = try request.multipartParts()

        #expect(parts.count == 1)
        #expect(parts[0].name == "field")
        #expect(try readAll(parts[0].body) == Data("value".utf8))
    }

    @Test("transport padding after boundary is skipped")
    func transportPadding() throws {
        let boundary = "AaB03x"
        // Add spaces and tabs after the boundary delimiter
        let body = "--\(boundary)  \t \r\nContent-Disposition: form-data; name=\"field\"\r\n\r\nvalue\r\n--\(boundary)--\r\n"

        let (url, request) = try makeFileBackedRequestFromRawBody(body: body, boundary: boundary)
        defer { try? FileManager.default.removeItem(at: url) }

        let parts = try request.multipartParts()

        #expect(parts.count == 1)
        #expect(parts[0].name == "field")
        #expect(try readAll(parts[0].body) == Data("value".utf8))
    }

    // MARK: - Error Cases

    @Test("close-delimiter-only body throws malformedBody")
    func closeDelimiterOnly() throws {
        let boundary = "AaB03x"
        let body = "--\(boundary)--\r\n"

        let (url, request) = try makeFileBackedRequestFromRawBody(body: body, boundary: boundary)
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(throws: MultipartParseError.malformedBody) {
            try request.multipartParts()
        }
    }

    @Test("missing close delimiter throws malformedBody")
    func missingCloseDelimiter() throws {
        let boundary = "AaB03x"
        let body = "--\(boundary)\r\nContent-Disposition: form-data; name=\"field\"\r\n\r\nvalue"

        let (url, request) = try makeFileBackedRequestFromRawBody(body: body, boundary: boundary)
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(throws: MultipartParseError.malformedBody) {
            try request.multipartParts()
        }
    }

    // MARK: - Chunk Boundary Edge Cases

    @Test("boundary split across chunk boundary is found correctly")
    func boundarySplitAcrossChunk() throws {
        let boundary = "AaB03x"
        let delimiter = "--\(boundary)"  // 10 bytes

        // We want the second delimiter to start 5 bytes before the 65536 chunk boundary,
        // so it straddles the boundary: 5 bytes in chunk 1, 5 bytes in chunk 2.
        let splitPoint = 65_536 - 5

        // Calculate the header overhead for the first part:
        //   "--AaB03x\r\n" = 12 bytes
        //   "Content-Disposition: form-data; name=\"pad\"\r\n" = 45 bytes
        //   "\r\n" = 2 bytes  (header/body separator)
        // Total: 59 bytes
        // After the body: "\r\n" = 2 bytes (CRLF before next delimiter)
        // So: padding_length = splitPoint - 59 - 2 = splitPoint - 61
        let headerOverhead = Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"pad\"\r\n\r\n".utf8).count
        let crlfBeforeDelimiter = 2
        let paddingLength = splitPoint - headerOverhead - crlfBeforeDelimiter

        let padding = Data(repeating: UInt8(ascii: "A"), count: paddingLength)

        let (url, request) = try makeFileBackedRequest(
            fields: [
                ("pad", nil, nil, padding),
                ("after", nil, nil, Data("found-it".utf8)),
            ],
            boundary: boundary
        )
        defer { try? FileManager.default.removeItem(at: url) }

        // Verify the delimiter actually straddles the chunk boundary.
        let fileData = try Data(contentsOf: url)
        let delimData = Data(delimiter.utf8)
        if let range = fileData.range(of: delimData, in: (fileData.startIndex + headerOverhead)..<fileData.endIndex) {
            let delimStart = fileData.distance(from: fileData.startIndex, to: range.lowerBound)
            #expect(delimStart == splitPoint, "Delimiter should start at \(splitPoint), got \(delimStart)")
        }

        let parts = try request.multipartParts()

        #expect(parts.count == 2)
        #expect(parts[0].name == "pad")
        #expect(parts[0].body.count == paddingLength)
        #expect(parts[1].name == "after")
        #expect(try readAll(parts[1].body) == Data("found-it".utf8))
    }

    @Test("large body spanning multiple chunks parses correctly")
    func largeBodyMultipleChunks() throws {
        // Create a body larger than 2 chunks (> 128 KB).
        let largeContent = Data(repeating: UInt8(ascii: "X"), count: 200_000)

        let (url, request) = try makeFileBackedRequest(
            fields: [
                ("large", "big.bin", "application/octet-stream", largeContent),
                ("meta", nil, nil, Data("description".utf8)),
            ],
            boundary: "LargeBoundary42"
        )
        defer { try? FileManager.default.removeItem(at: url) }

        let parts = try request.multipartParts()

        #expect(parts.count == 2)
        #expect(parts[0].name == "large")
        #expect(parts[0].body.count == largeContent.count)
        #expect(try readAll(parts[0].body) == largeContent)
        #expect(parts[1].name == "meta")
        #expect(try readAll(parts[1].body) == Data("description".utf8))
    }

    // MARK: - fileSlice Source

    @Test("file-backed body with non-zero offset (fileSlice) parses correctly")
    func fileSliceSource() throws {
        let boundary = "AaB03x"
        let multipartBody = "--\(boundary)\r\nContent-Disposition: form-data; name=\"field\"\r\n\r\nvalue\r\n--\(boundary)--\r\n"
        let multipartData = Data(multipartBody.utf8)

        // Write garbage prefix + multipart body to the file.
        let garbagePrefix = Data(repeating: UInt8(ascii: "Z"), count: 500)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("slice-test-\(UUID().uuidString)")
        try (garbagePrefix + multipartData).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        // Create a fileSlice body that starts after the garbage prefix.
        let body = RequestBody(fileURL: url, offset: UInt64(garbagePrefix.count), length: multipartData.count)
        let request = ParsedHTTPRequest.complete(
            method: "POST",
            target: "/upload",
            httpVersion: "HTTP/1.1",
            headers: ["Content-Type": "multipart/form-data; boundary=\(boundary)", "Host": "localhost"],
            body: body
        )

        let parts = try request.multipartParts()

        #expect(parts.count == 1)
        #expect(parts[0].name == "field")
        #expect(try readAll(parts[0].body) == Data("value".utf8))
    }

    // MARK: - Helpers

    /// Builds a multipart body from field descriptors, writes it to a temp file,
    /// and returns a `ParsedHTTPRequest` with a file-backed body.
    private func makeFileBackedRequest(
        fields: [(name: String, filename: String?, contentType: String?, value: Data)],
        boundary: String
    ) throws -> (URL, ParsedHTTPRequest) {
        var body = Data()
        for field in fields {
            body.append(Data("--\(boundary)\r\n".utf8))
            var disposition = "Content-Disposition: form-data; name=\"\(field.name)\""
            if let filename = field.filename {
                disposition += "; filename=\"\(filename)\""
            }
            body.append(Data("\(disposition)\r\n".utf8))
            if let ct = field.contentType {
                body.append(Data("Content-Type: \(ct)\r\n".utf8))
            }
            body.append(Data("\r\n".utf8))
            body.append(field.value)
            body.append(Data("\r\n".utf8))
        }
        body.append(Data("--\(boundary)--\r\n".utf8))

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("multipart-test-\(UUID().uuidString)")
        try body.write(to: url)

        let requestBody = RequestBody(fileURL: url)
        let request = ParsedHTTPRequest.complete(
            method: "POST",
            target: "/upload",
            httpVersion: "HTTP/1.1",
            headers: ["Content-Type": "multipart/form-data; boundary=\(boundary)", "Host": "localhost"],
            body: requestBody
        )

        return (url, request)
    }

    /// Writes a raw multipart body string to a temp file and returns a file-backed request.
    private func makeFileBackedRequestFromRawBody(
        body: String,
        boundary: String
    ) throws -> (URL, ParsedHTTPRequest) {
        let bodyData = Data(body.utf8)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("multipart-test-\(UUID().uuidString)")
        try bodyData.write(to: url)

        let requestBody = RequestBody(fileURL: url)
        let request = ParsedHTTPRequest.complete(
            method: "POST",
            target: "/upload",
            httpVersion: "HTTP/1.1",
            headers: ["Content-Type": "multipart/form-data; boundary=\(boundary)", "Host": "localhost"],
            body: requestBody
        )

        return (url, request)
    }

    private func readAll(_ body: RequestBody) throws -> Data {
        let stream = try body.makeInputStream()
        stream.open()
        defer { stream.close() }

        var data = Data()
        let bufferSize = 1024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }

        // Use read() directly instead of hasBytesAvailable to avoid race
        // conditions with bound stream pairs, where data from the writer
        // thread may not have arrived yet when hasBytesAvailable is checked.
        while true {
            let bytesRead = stream.read(buffer, maxLength: bufferSize)
            if bytesRead <= 0 { break }
            data.append(buffer, count: bytesRead)
        }

        return data
    }
}
