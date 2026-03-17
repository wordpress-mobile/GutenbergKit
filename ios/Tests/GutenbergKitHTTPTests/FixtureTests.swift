import Foundation
import Testing
@testable import GutenbergKitHTTP

// MARK: - Fixture Models

struct HeaderValueFixtures: Decodable {
    let tests: [HeaderValueTestCase]

    struct HeaderValueTestCase: Decodable {
        let description: String
        let parameter: String
        let headerValue: String
        let expected: String?
    }
}

struct RequestParsingFixtures: Decodable {
    let tests: [RequestTestCase]
    let errorTests: [RequestErrorTestCase]
    let incrementalTests: [IncrementalTestCase]

    struct ExpectedAfterHeaders: Decodable {
        var hasHeaders: Bool?
        var isComplete: Bool?
        var method: String?
        var target: String?
    }

    struct ExpectedRequest: Decodable {
        var method: String?
        var target: String?
        var headers: [String: String]?
        var isComplete: Bool?
        var hasHeaders: Bool?
        var parseResult: String?

        // body uses explicit key presence tracking so we can distinguish
        // "body key absent" (don't check) from "body": null (expect nil)
        private(set) var body: String?
        private(set) var hasBodyExpectation: Bool = false

        var afterHeaders: ExpectedAfterHeaders?

        private enum CodingKeys: String, CodingKey {
            case method, target, headers, body, isComplete, hasHeaders, parseResult, afterHeaders
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            method = try container.decodeIfPresent(String.self, forKey: .method)
            target = try container.decodeIfPresent(String.self, forKey: .target)
            headers = try container.decodeIfPresent([String: String].self, forKey: .headers)
            isComplete = try container.decodeIfPresent(Bool.self, forKey: .isComplete)
            hasHeaders = try container.decodeIfPresent(Bool.self, forKey: .hasHeaders)
            parseResult = try container.decodeIfPresent(String.self, forKey: .parseResult)
            hasBodyExpectation = container.contains(.body)
            body = try container.decodeIfPresent(String.self, forKey: .body)
            afterHeaders = try container.decodeIfPresent(ExpectedAfterHeaders.self, forKey: .afterHeaders)
        }
    }

    struct RequestTestCase: Decodable {
        let description: String
        let input: String
        let expected: ExpectedRequest
        var appendAfterComplete: String?
        var maxBodySize: Int64?
    }

    struct RequestErrorExpected: Decodable {
        let error: String
    }

    struct RequestErrorTestCase: Decodable {
        let description: String
        var input: String?
        var inputBase64: String?
        let expected: RequestErrorExpected
        var maxBodySize: Int64?
    }

    struct IncrementalTestCase: Decodable {
        let description: String
        var input: String?
        var headers: String?
        var bodyChunks: [String]?
        var chunkSize: Int?
        let expected: ExpectedRequest
    }
}

struct MultipartFixtures: Decodable {
    let tests: [MultipartTestCase]
    let errorTests: [MultipartErrorTestCase]

    struct ExpectedPart: Decodable {
        let name: String
        var filename: String?
        var contentType: String?
        var body: String?
        /// Whether the "filename" key was present in the JSON fixture (distinguishes absent from null).
        var filenameSpecified: Bool = false

        private enum CodingKeys: String, CodingKey {
            case name, filename, contentType, body
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            name = try container.decode(String.self, forKey: .name)
            contentType = try container.decodeIfPresent(String.self, forKey: .contentType)
            body = try container.decodeIfPresent(String.self, forKey: .body)
            if container.contains(.filename) {
                filename = try container.decodeIfPresent(String.self, forKey: .filename)
                filenameSpecified = true
            }
        }
    }

    struct Expected: Decodable {
        var contentType: String?
        var parts: [ExpectedPart]?
        var error: String?
    }

    struct MultipartTestCase: Decodable {
        let description: String
        let boundary: String
        var quotedBoundary: Bool?
        let rawBody: String
        let expected: Expected
    }

    struct MultipartErrorTestCase: Decodable {
        let description: String
        var contentType: String?
        var body: String?
        var boundary: String?
        var rawBody: String?
        let expected: Expected
    }
}

// MARK: - Fixture Loading

private func fixtureURL(_ name: String) -> URL {
    Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "http")!
}

private func loadFixture<T: Decodable>(_ name: String) throws -> T {
    let data = try Data(contentsOf: fixtureURL(name))
    return try JSONDecoder().decode(T.self, from: data)
}

// MARK: - Header Value Fixture Tests

@Suite("Header Value Fixtures")
struct HeaderValueFixtureTests {

    @Test("All fixture cases pass", arguments: try! loadHeaderValueTests())
    func fixtureCase(_ testCase: HeaderValueFixtures.HeaderValueTestCase) {
        let result = HeaderValue.extractParameter(testCase.parameter, from: testCase.headerValue)
        #expect(result == testCase.expected, "\(testCase.description)")
    }
}

private func loadHeaderValueTests() throws -> [HeaderValueFixtures.HeaderValueTestCase] {
    let fixtures: HeaderValueFixtures = try loadFixture("header-value-parsing")
    return fixtures.tests
}

extension HeaderValueFixtures.HeaderValueTestCase: CustomTestStringConvertible {
    var testDescription: String { description }
}

// MARK: - Request Parsing Fixture Tests

@Suite("Request Parsing Fixtures")
struct RequestParsingFixtureTests {

    @Test("All basic parsing cases pass", arguments: try! loadRequestTests())
    func basicCase(_ testCase: RequestParsingFixtures.RequestTestCase) throws {
        let raw = testCase.input
        let parser: HTTPRequestParser
        if let maxBodySize = testCase.maxBodySize {
            parser = HTTPRequestParser(maxBodySize: maxBodySize)
            parser.append(Data(raw.utf8))
        } else {
            parser = HTTPRequestParser(raw)
        }

        if let extra = testCase.appendAfterComplete {
            parser.append(Data(extra.utf8))
        }

        let exp = testCase.expected

        if exp.isComplete == false && exp.hasHeaders == false {
            #expect(!parser.state.hasHeaders)
            #expect(try parser.parseRequest() == nil)
            return
        }

        let request = try #require(try parser.parseRequest())

        if let method = exp.method {
            #expect(request.method == method, "\(testCase.description): method")
        }
        if let target = exp.target {
            #expect(request.target == target, "\(testCase.description): target")
        }
        if let isComplete = exp.isComplete {
            if isComplete {
                #expect(parser.state.isComplete, "\(testCase.description): isComplete")
            }
        }
        if let headers = exp.headers {
            for (key, value) in headers {
                #expect(request.header(key) == value, "\(testCase.description): header \(key)")
            }
        }
        if exp.hasBodyExpectation {
            if let expectedBody = exp.body {
                let requestBody = try #require(request.body)
                #expect(try readAll(requestBody) == Data(expectedBody.utf8), "\(testCase.description): body content")
            } else {
                #expect(request.body == nil, "\(testCase.description): body should be nil")
            }
        }
    }

    @Test("All error cases pass", arguments: try! loadRequestErrorTests())
    func errorCase(_ testCase: RequestParsingFixtures.RequestErrorTestCase) {
        let parser: HTTPRequestParser

        if let base64 = testCase.inputBase64 {
            let data = Data(base64Encoded: base64)!
            if let maxBodySize = testCase.maxBodySize {
                parser = HTTPRequestParser(maxBodySize: maxBodySize)
            } else {
                parser = HTTPRequestParser()
            }
            parser.append(data)
        } else {
            let raw = testCase.input!
            if let maxBodySize = testCase.maxBodySize {
                parser = HTTPRequestParser(maxBodySize: maxBodySize)
                parser.append(Data(raw.utf8))
            } else {
                parser = HTTPRequestParser(raw)
            }
        }

        let expectedError = testCase.expected.error
        do {
            _ = try parser.parseRequest()
            Issue.record("Expected error \(expectedError) but parsing succeeded — \(testCase.description)")
        } catch {
            let errorName = String(describing: error)
            #expect(errorName == expectedError, "\(testCase.description): expected \(expectedError) but got \(errorName)")
        }
    }

    @Test("All incremental cases pass", arguments: try! loadIncrementalTests())
    func incrementalCase(_ testCase: RequestParsingFixtures.IncrementalTestCase) throws {
        let parser = HTTPRequestParser()

        if let input = testCase.input, let chunkSize = testCase.chunkSize {
            let raw = input
            let data = Data(raw.utf8)
            for i in stride(from: 0, to: data.count, by: chunkSize) {
                let end = min(i + chunkSize, data.count)
                parser.append(data[i..<end])
            }
        } else if let headers = testCase.headers {
            let headerRaw = headers
            parser.append(Data(headerRaw.utf8))

            if let afterHeaders = testCase.expected.afterHeaders {
                if let hasHeaders = afterHeaders.hasHeaders {
                    #expect(parser.state.hasHeaders == hasHeaders, "\(testCase.description): hasHeaders after headers")
                }
                if let isComplete = afterHeaders.isComplete {
                    if isComplete {
                        #expect(parser.state.isComplete, "\(testCase.description): isComplete after headers")
                    } else {
                        #expect(!parser.state.isComplete, "\(testCase.description): not isComplete after headers")
                    }
                }
                if afterHeaders.method != nil || afterHeaders.target != nil {
                    let partialRequest = try #require(try parser.parseRequest())
                    if let method = afterHeaders.method {
                        #expect(partialRequest.method == method)
                    }
                    if let target = afterHeaders.target {
                        #expect(partialRequest.target == target)
                    }
                }
            }

            if let bodyChunks = testCase.bodyChunks {
                for chunk in bodyChunks {
                    parser.append(Data(chunk.utf8))
                }
            }
        } else if let input = testCase.input {
            let raw = input
            parser.append(Data(raw.utf8))
        }

        let exp = testCase.expected
        if exp.isComplete == false && exp.hasHeaders == false {
            #expect(!parser.state.hasHeaders)
            #expect(try parser.parseRequest() == nil)
            return
        }

        let request = try #require(try parser.parseRequest())
        if let method = exp.method {
            #expect(request.method == method, "\(testCase.description): method")
        }
        if let target = exp.target {
            #expect(request.target == target, "\(testCase.description): target")
        }
        if let isComplete = exp.isComplete, isComplete {
            #expect(parser.state.isComplete, "\(testCase.description): isComplete")
        }
        if let expectedBody = exp.body {
            let requestBody = try #require(request.body)
            #expect(try readAll(requestBody) == Data(expectedBody.utf8), "\(testCase.description): body")
        }
    }
}

private func loadRequestTests() throws -> [RequestParsingFixtures.RequestTestCase] {
    let fixtures: RequestParsingFixtures = try loadFixture("request-parsing")
    return fixtures.tests
}

private func loadRequestErrorTests() throws -> [RequestParsingFixtures.RequestErrorTestCase] {
    let fixtures: RequestParsingFixtures = try loadFixture("request-parsing")
    return fixtures.errorTests
}

private func loadIncrementalTests() throws -> [RequestParsingFixtures.IncrementalTestCase] {
    let fixtures: RequestParsingFixtures = try loadFixture("request-parsing")
    return fixtures.incrementalTests
}

extension RequestParsingFixtures.RequestTestCase: CustomTestStringConvertible {
    var testDescription: String { description }
}

extension RequestParsingFixtures.RequestErrorTestCase: CustomTestStringConvertible {
    var testDescription: String { description }
}

extension RequestParsingFixtures.IncrementalTestCase: CustomTestStringConvertible {
    var testDescription: String { description }
}

// MARK: - Multipart Parsing Fixture Tests

@Suite("Multipart Parsing Fixtures")
struct MultipartParsingFixtureTests {

    @Test("All cases pass", arguments: try! loadMultipartTests())
    func testCase(_ testCase: MultipartFixtures.MultipartTestCase) throws {
        let request = try buildRawMultipartRequest(
            body: testCase.rawBody,
            boundary: testCase.boundary,
            quotedBoundary: testCase.quotedBoundary ?? false
        )

        if let expectedCT = testCase.expected.contentType {
            #expect(request.header("Content-Type") == expectedCT, "\(testCase.description): Content-Type")
        }

        let expectedParts = testCase.expected.parts ?? []
        let parts = try request.multipartParts()
        #expect(parts.count == expectedParts.count, "\(testCase.description): part count")

        for (i, expectedPart) in expectedParts.enumerated() where i < parts.count {
            #expect(parts[i].name == expectedPart.name, "\(testCase.description): part[\(i)].name")
            if expectedPart.filenameSpecified {
                #expect(parts[i].filename == expectedPart.filename, "\(testCase.description): part[\(i)].filename")
            }
            if let ct = expectedPart.contentType {
                #expect(parts[i].contentType == ct, "\(testCase.description): part[\(i)].contentType")
            }
            if let body = expectedPart.body {
                #expect(try readAll(parts[i].body) == Data(body.utf8), "\(testCase.description): part[\(i)].body")
            }
        }
    }

    @Test("All error cases pass", arguments: try! loadMultipartErrorTests())
    func errorCase(_ testCase: MultipartFixtures.MultipartErrorTestCase) throws {
        let request: ParsedHTTPRequest

        let contentType = testCase.contentType ?? testCase.expected.contentType

        if let rawBody = testCase.rawBody, let boundary = testCase.boundary {
            request = try buildRawMultipartRequest(body: rawBody, boundary: boundary)
        } else if let contentType, let body = testCase.body {
            let raw = "POST /wp/v2/posts HTTP/1.1\r\nHost: localhost\r\nContent-Type: \(contentType)\r\nContent-Length: \(body.utf8.count)\r\n\r\n\(body)"
            let parser = HTTPRequestParser(raw)
            request = try #require(try parser.parseRequest())
        } else if let contentType {
            let raw = "GET /upload HTTP/1.1\r\nHost: localhost\r\nContent-Type: \(contentType)\r\n\r\n"
            let parser = HTTPRequestParser(raw)
            request = try #require(try parser.parseRequest())
        } else {
            Issue.record("Invalid error test case: \(testCase.description)")
            return
        }

        let expectedError = testCase.expected.error!
        do {
            _ = try request.multipartParts()
            Issue.record("Expected error \(expectedError) but succeeded — \(testCase.description)")
        } catch {
            let errorName = String(describing: error)
            #expect(errorName == expectedError, "\(testCase.description): expected \(expectedError) but got \(errorName)")
        }
    }
}

private func loadMultipartTests() throws -> [MultipartFixtures.MultipartTestCase] {
    let fixtures: MultipartFixtures = try loadFixture("multipart-parsing")
    return fixtures.tests
}

private func loadMultipartErrorTests() throws -> [MultipartFixtures.MultipartErrorTestCase] {
    let fixtures: MultipartFixtures = try loadFixture("multipart-parsing")
    return fixtures.errorTests
}

extension MultipartFixtures.MultipartTestCase: CustomTestStringConvertible {
    var testDescription: String { description }
}

extension MultipartFixtures.MultipartErrorTestCase: CustomTestStringConvertible {
    var testDescription: String { description }
}

private func buildRawMultipartRequest(
    body: String,
    boundary: String,
    quotedBoundary: Bool = false
) throws -> ParsedHTTPRequest {
    let boundaryParam = quotedBoundary ? "\"\(boundary)\"" : boundary
    let raw = "POST /wp/v2/media HTTP/1.1\r\nHost: localhost\r\nContent-Type: multipart/form-data; boundary=\(boundaryParam)\r\nContent-Length: \(body.utf8.count)\r\n\r\n\(body)"
    let parser = HTTPRequestParser(raw)
    return try #require(try parser.parseRequest())
}
