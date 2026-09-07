import Foundation
import GutenbergKitHTTP
import Testing
@testable import GutenbergKit

/// The server's own behavior: what it admits, how it refuses, and where a
/// request goes when no route claims it. Route behavior is tested with the
/// routes.
@Suite("EditorLocalServer", .enabled(if: localServerCanBind))
struct EditorLocalServerTests {

  @Test("starts and provides a port and token")
  func startAndStop() async throws {
    let server = try await EditorLocalServer.start(routes: [])
    #expect(server.port > 0)
    #expect(!server.token.isEmpty)
    server.stop()
  }

  @Test("rejects requests without auth token")
  func rejectsUnauthenticated() async throws {
    let server = try await EditorLocalServer.start(routes: [])
    defer { server.stop() }

    let url = URL(string: "http://127.0.0.1:\(server.port)/upload")!
    var request = URLRequest(url: url)
    request.httpMethod = "POST"

    let (_, response) = try await URLSession.shared.data(for: request)
    let httpResponse = try #require(response as? HTTPURLResponse)
    #expect(httpResponse.statusCode == 407)
  }

  @Test("refuses in the JSON shape the editor parses")
  func refusalIsParseableByTheEditor() async throws {
    // `@wordpress/api-fetch` reads every response as JSON, so a `text/plain`
    // refusal reaches the editor as `invalid_json` — "The response is not a
    // valid JSON response." — with the real reason lost. Under the relay this
    // server answers every REST request the editor makes.
    let server = try await EditorLocalServer.start(routes: [])
    defer { server.stop() }

    let url = URL(string: "http://127.0.0.1:\(server.port)/upload")!
    var request = URLRequest(url: url)
    request.httpMethod = "POST"

    let (data, response) = try await URLSession.shared.data(for: request)
    let httpResponse = try #require(response as? HTTPURLResponse)

    #expect(httpResponse.statusCode == 407)
    #expect(httpResponse.value(forHTTPHeaderField: "Content-Type") == "application/json")
    let error = try #require((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])
    #expect(error["code"] as? String == "server_unauthorized")
    #expect(error["message"] is String)
  }

  @Test("rejects requests with wrong token")
  func rejectsWrongToken() async throws {
    let server = try await EditorLocalServer.start(routes: [])
    defer { server.stop() }

    let url = URL(string: "http://127.0.0.1:\(server.port)/upload")!
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("Bearer wrong-token", forHTTPHeaderField: "Relay-Authorization")

    let (_, response) = try await URLSession.shared.data(for: request)
    let httpResponse = try #require(response as? HTTPURLResponse)
    #expect(httpResponse.statusCode == 407)
  }

  @Test("responds to OPTIONS preflight with CORS headers")
  func corsPreflightResponse() async throws {
    let server = try await EditorLocalServer.start(routes: [])
    defer { server.stop() }

    let url = URL(string: "http://127.0.0.1:\(server.port)/upload")!
    var request = URLRequest(url: url)
    request.httpMethod = "OPTIONS"
    request.setValue("POST", forHTTPHeaderField: "Access-Control-Request-Method")
    request.setBrowserOrigin()

    let (_, response) = try await URLSession.shared.data(for: request)
    let httpResponse = try #require(response as? HTTPURLResponse)
    #expect(httpResponse.statusCode == 204)
    #expect(httpResponse.value(forHTTPHeaderField: "Access-Control-Allow-Origin") == "*")
    #expect(httpResponse.value(forHTTPHeaderField: "Access-Control-Allow-Methods")?.contains("POST") == true)
  }

  @Test("rejects a request that did not come from the web view")
  func rejectsNonBrowserRequest() async throws {
    let server = try await EditorLocalServer.start(routes: [])
    defer { server.stop() }

    // A correct token but none of the headers WebKit sets on a `fetch()`: the
    // shape another process on the device would produce over a raw socket.
    let url = URL(string: "http://127.0.0.1:\(server.port)/upload")!
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("Bearer \(server.token)", forHTTPHeaderField: "Relay-Authorization")

    let (_, response) = try await URLSession.shared.data(for: request)
    let httpResponse = try #require(response as? HTTPURLResponse)
    #expect(httpResponse.statusCode == 403)
  }

  @Test("returns 404 for unknown paths")
  func unknownPath() async throws {
    let server = try await EditorLocalServer.start(routes: [])
    defer { server.stop() }

    let url = URL(string: "http://127.0.0.1:\(server.port)/unknown")!
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("Bearer \(server.token)", forHTTPHeaderField: "Relay-Authorization")
    request.setBrowserOrigin()

    let (_, response) = try await URLSession.shared.data(for: request)
    let httpResponse = try #require(response as? HTTPURLResponse)
    #expect(httpResponse.statusCode == 404)
  }

  @Test("returns 413 with CORS headers when request body exceeds max size")
  func oversizedUploadReturns413WithCORSHeaders() async throws {
    let server = try await EditorLocalServer.start(routes: [], maxRequestBodySize: 1024)
    defer { server.stop() }

    let boundary = UUID().uuidString
    let oversizedData = Data(repeating: 0x42, count: 2048)
    let body = buildMultipartBody(boundary: boundary, filename: "big.bin", mimeType: "application/octet-stream", data: oversizedData)

    let url = URL(string: "http://127.0.0.1:\(server.port)/upload")!
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("Bearer \(server.token)", forHTTPHeaderField: "Relay-Authorization")
    request.setBrowserOrigin()
    request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
    request.httpBody = body

    let (data, response) = try await URLSession.shared.data(for: request)
    let httpResponse = try #require(response as? HTTPURLResponse)
    #expect(httpResponse.statusCode == 413)
    #expect(httpResponse.value(forHTTPHeaderField: "Access-Control-Allow-Origin") == "*")

    let responseBody = String(data: data, encoding: .utf8) ?? ""
    #expect(responseBody.contains("too large"))
  }

  @Test("unauthenticated oversized request returns 407, not 413 (auth precedes drain)")
  func oversizedUploadWithoutTokenReturns407() async throws {
    let server = try await EditorLocalServer.start(routes: [], maxRequestBodySize: 1024)
    defer { server.stop() }

    let boundary = UUID().uuidString
    let oversizedData = Data(repeating: 0x42, count: 2048)
    let body = buildMultipartBody(boundary: boundary, filename: "big.bin", mimeType: "application/octet-stream", data: oversizedData)

    let url = URL(string: "http://127.0.0.1:\(server.port)/upload")!
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    // Deliberately no Relay-Authorization header.
    request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
    request.httpBody = body

    // Auth is checked on headers alone, before the oversized body is drained
    // or the handler runs — so the request is rejected with 407, not answered
    // with the handler's 413. An unauthenticated client must not be able to
    // make the server read (and discard) an arbitrarily large body.
    let (_, response) = try await URLSession.shared.data(for: request)
    let httpResponse = try #require(response as? HTTPURLResponse)
    #expect(httpResponse.statusCode == 407)
  }
}
