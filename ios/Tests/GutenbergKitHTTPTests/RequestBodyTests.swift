import Foundation
import Testing
@testable import GutenbergKitHTTP

@Suite("RequestBody")
struct RequestBodyTests {

    // MARK: - makeInputStream (Data-backed)

    @Test("makeInputStream returns working stream for data-backed body")
    func dataBackedStream() throws {
        let expected = Data("hello world".utf8)
        let body = RequestBody(data: expected)

        let stream = try body.makeInputStream()
        #expect(readAll(stream) == expected)
    }

    // MARK: - makeInputStream (File-backed)

    @Test("makeInputStream returns working stream for file-backed body")
    func fileBackedStream() throws {
        let expected = Data("file contents".utf8)
        let url = makeTemporaryFile(contents: expected)
        defer { try? FileManager.default.removeItem(at: url) }

        let body = RequestBody(fileURL: url)

        let stream = try body.makeInputStream()
        #expect(readAll(stream) == expected)
    }

    @Test("makeInputStream throws fileNoSuchFile for missing file")
    func throwsForMissingFile() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("nonexistent-\(UUID().uuidString)")
        let body = RequestBody(fileURL: url)

        #expect(throws: CocoaError.self) {
            let error = try body.makeInputStream()
            _ = error  // suppress unused warning
        }
    }

    @Test("makeInputStream throws fileReadInvalidFileName for directory")
    func throwsForDirectory() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("dir-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: url) }

        let body = RequestBody(fileURL: url)

        #expect(throws: CocoaError.self) {
            let error = try body.makeInputStream()
            _ = error
        }
    }

    // MARK: - makeInputStream (FileSlice-backed)

    @Test("fileSlice stream reads correct byte range")
    func fileSliceReadsCorrectRange() throws {
        let contents = Data("Hello, World!".utf8)
        let url = makeTemporaryFile(contents: contents)
        defer { try? FileManager.default.removeItem(at: url) }

        // Slice "World" (offset 7, length 5)
        let body = RequestBody(fileURL: url, offset: 7, length: 5)

        let stream = try body.makeInputStream()
        #expect(readAll(stream) == Data("World".utf8))
    }

    @Test("fileSlice stream reads from beginning when offset is zero")
    func fileSliceFromBeginning() throws {
        let contents = Data("ABCDEFGHIJ".utf8)
        let url = makeTemporaryFile(contents: contents)
        defer { try? FileManager.default.removeItem(at: url) }

        let body = RequestBody(fileURL: url, offset: 0, length: 3)

        let stream = try body.makeInputStream()
        #expect(readAll(stream) == Data("ABC".utf8))
    }

    @Test("fileSlice stream reads to end of file")
    func fileSliceToEnd() throws {
        let contents = Data("ABCDEFGHIJ".utf8)
        let url = makeTemporaryFile(contents: contents)
        defer { try? FileManager.default.removeItem(at: url) }

        let body = RequestBody(fileURL: url, offset: 7, length: 3)

        let stream = try body.makeInputStream()
        #expect(readAll(stream) == Data("HIJ".utf8))
    }

    @Test("fileSlice stream reads entire file when slice covers all bytes")
    func fileSliceEntireFile() throws {
        let contents = Data("complete file".utf8)
        let url = makeTemporaryFile(contents: contents)
        defer { try? FileManager.default.removeItem(at: url) }

        let body = RequestBody(fileURL: url, offset: 0, length: contents.count)

        let stream = try body.makeInputStream()
        #expect(readAll(stream) == contents)
    }

    @Test("fileSlice stream reads single byte")
    func fileSliceSingleByte() throws {
        let contents = Data("ABCDE".utf8)
        let url = makeTemporaryFile(contents: contents)
        defer { try? FileManager.default.removeItem(at: url) }

        let body = RequestBody(fileURL: url, offset: 2, length: 1)

        let stream = try body.makeInputStream()
        #expect(readAll(stream) == Data("C".utf8))
    }

    @Test("fileSlice stream works with reads smaller than slice length")
    func fileSliceSmallReads() throws {
        // Create a body larger than a typical small read buffer
        let contents = Data(repeating: 0x42, count: 4096)
        let url = makeTemporaryFile(contents: contents)
        defer { try? FileManager.default.removeItem(at: url) }

        let body = RequestBody(fileURL: url, offset: 100, length: 3000)

        let stream = try body.makeInputStream()
        // Read in small chunks to exercise the bounded read logic
        let result = readAllWithBufferSize(stream, bufferSize: 128)
        #expect(result == contents[100..<3100])
    }

    @Test("fileSlice stream returns 0 after exhaustion")
    func fileSliceReadAfterExhaustion() throws {
        let contents = Data("AB".utf8)
        let url = makeTemporaryFile(contents: contents)
        defer { try? FileManager.default.removeItem(at: url) }

        let body = RequestBody(fileURL: url, offset: 0, length: 2)
        let stream = try body.makeInputStream()
        stream.open()

        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 10)
        defer { buffer.deallocate() }

        // First read gets all bytes
        let n1 = stream.read(buffer, maxLength: 10)
        #expect(n1 == 2)

        // Second read returns 0 (at end)
        let n2 = stream.read(buffer, maxLength: 10)
        #expect(n2 == 0)

        stream.close()
    }

    @Test("fileSlice init throws for missing file")
    func fileSliceThrowsForMissingFile() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("nonexistent-\(UUID().uuidString)")
        let body = RequestBody(fileURL: url, offset: 0, length: 10)

        #expect(throws: Error.self) {
            _ = try body.makeInputStream()
        }
    }

    @Test("fileSlice stream with zero length returns no data")
    func fileSliceZeroLength() throws {
        let contents = Data("ABCDE".utf8)
        let url = makeTemporaryFile(contents: contents)
        defer { try? FileManager.default.removeItem(at: url) }

        let body = RequestBody(fileURL: url, offset: 2, length: 0)

        let stream = try body.makeInputStream()
        #expect(readAll(stream) == Data())
    }

    @Test("fileSlice stream does not read beyond slice boundary")
    func fileSliceDoesNotReadBeyondBoundary() throws {
        let contents = Data("ABCDEFGHIJ".utf8)
        let url = makeTemporaryFile(contents: contents)
        defer { try? FileManager.default.removeItem(at: url) }

        // Slice is "CDE" (offset 2, length 3) — must not return "FGHIJ"
        let body = RequestBody(fileURL: url, offset: 2, length: 3)

        let stream = try body.makeInputStream()
        let result = readAll(stream)
        #expect(result == Data("CDE".utf8))
        #expect(result.count == 3)
    }

    @Test("fileSlice stream with binary data preserves all bytes")
    func fileSliceBinaryData() throws {
        // All byte values 0x00-0xFF
        let contents = Data(0...255)
        let url = makeTemporaryFile(contents: contents)
        defer { try? FileManager.default.removeItem(at: url) }

        let body = RequestBody(fileURL: url, offset: 100, length: 50)

        let stream = try body.makeInputStream()
        let result = readAll(stream)
        #expect(result == Data(100..<150))
    }

    @Test("multiple fileSlice streams from same file read independently")
    func fileSliceMultipleStreamsIndependent() throws {
        let contents = Data("ABCDEFGHIJKLMNOP".utf8)
        let url = makeTemporaryFile(contents: contents)
        defer { try? FileManager.default.removeItem(at: url) }

        let body1 = RequestBody(fileURL: url, offset: 0, length: 4)
        let body2 = RequestBody(fileURL: url, offset: 8, length: 4)

        let stream1 = try body1.makeInputStream()
        let stream2 = try body2.makeInputStream()

        #expect(readAll(stream1) == Data("ABCD".utf8))
        #expect(readAll(stream2) == Data("IJKL".utf8))
    }

    // MARK: - Equatable

    @Test("data-backed bodies with same data are equal")
    func dataEquality() {
        let data = Data("same".utf8)
        #expect(RequestBody(data: data) == RequestBody(data: data))
    }

    @Test("data-backed bodies with different data are not equal")
    func dataInequality() {
        #expect(RequestBody(data: Data("a".utf8)) != RequestBody(data: Data("b".utf8)))
    }

    @Test("file-backed bodies with same URL are equal")
    func fileEquality() {
        let url = URL(fileURLWithPath: "/tmp/same-file")
        #expect(RequestBody(fileURL: url) == RequestBody(fileURL: url))
    }

    @Test("data-backed and file-backed bodies are not equal")
    func dataVsFileInequality() {
        let data = Data("hello".utf8)
        let url = URL(fileURLWithPath: "/tmp/hello")
        #expect(RequestBody(data: data) != RequestBody(fileURL: url))
    }

    // MARK: - URLSession integration (file-slice via httpBodyStream)

    #if canImport(Network)
    @Test("fileSlice body sent via URLSession httpBodyStream delivers correct bytes")
    func fileSliceBodyStreamWorksWithURLSession() async throws {
        // Write a known payload to a temp file
        let payload = Data("The quick brown fox jumps over the lazy dog".utf8)
        let fileURL = makeTemporaryFile(contents: payload)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        // Slice out "brown fox" (offset 10, length 9)
        let expectedSlice = Data("brown fox".utf8)
        let body = RequestBody(fileURL: fileURL, offset: 10, length: 9)

        // Start an echo server that returns the request body as the response
        let server = try await HTTPServer.start(
            name: "body-echo",
            requiresAuthentication: false
        ) { request in
            guard let body = request.parsed.body,
                  let data = try? await body.data else {
                return HTTPResponse(status: 200, body: Data())
            }
            return HTTPResponse(status: 200, body: data)
        }
        defer { server.stop() }

        // Build a URLRequest using the same code path as the proxy:
        // this assigns body.makeInputStream() to request.httpBodyStream.
        let baseURL = URL(string: "http://127.0.0.1:\(server.port)")!
        let parsed = ParsedHTTPRequest.complete(
            method: "POST",
            target: "/echo",
            httpVersion: "HTTP/1.1",
            headers: ["Host": "localhost", "Content-Length": "9"],
            body: body
        )
        var request = try #require(parsed.urlRequest(relativeTo: baseURL))
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")

        let (responseData, response) = try await URLSession.shared.data(for: request)
        let http = try #require(response as? HTTPURLResponse)

        #expect(http.statusCode == 200)
        // This assertion would fail with the old FileSliceInputStream subclass
        // because URLSession reads from the empty Data() superclass instead of
        // the overridden read(_:maxLength:) — resulting in an empty body.
        #expect(responseData == expectedSlice)
    }
    #endif

    // MARK: - Helpers

    private func makeTemporaryFile(contents: Data) -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("RequestBodyTests-\(UUID().uuidString)")
        FileManager.default.createFile(atPath: url.path, contents: contents)
        return url
    }

    private func readAll(_ stream: InputStream) -> Data {
        readAllWithBufferSize(stream, bufferSize: 1024)
    }

    private func readAllWithBufferSize(_ stream: InputStream, bufferSize: Int) -> Data {
        stream.open()
        defer { stream.close() }

        var data = Data()
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
