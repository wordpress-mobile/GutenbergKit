# GutenbergKitHTTP

A zero-dependency Swift module providing an HTTP/1.1 request parser and a lightweight local server built on Network.framework. Designed for use as the front-end of an in-process HTTP proxy server, where raw bytes arrive over a socket and need to be converted into structured request objects suitable for forwarding via `URLSession`.

## Why

GutenbergKit's iOS integration uses an in-process HTTP server to bridge requests between the embedded web editor and native networking. This module handles the parsing side of that bridge — turning raw TCP bytes into `URLRequest` objects — without pulling in a full HTTP server framework.

Key design goals:

- **Incremental parsing** — data can arrive in arbitrary chunks (byte-by-byte if needed); the parser buffers to disk so memory usage stays flat regardless of body size.
- **Lazy validation** — `append()` does only lightweight scanning (finding `\r\n\r\n` and extracting `Content-Length`). Full RFC validation is deferred to `parseRequest()`, keeping the hot path fast.
- **Strict conformance** — rejects request smuggling vectors (obs-fold, whitespace before colon), validates `Content-Length` per RFC 9110 §8.6, and combines duplicate headers per RFC 9110 §5.3.
- **No dependencies** — uses only Foundation.

## Types

| Type | Role |
|------|------|
| `HTTPServer` | Local HTTP/1.1 server on Network.framework. Binds to `127.0.0.1`, dispatches requests to an async handler. |
| `HTTPResponse` | Response struct with status, headers, and body. Can be initialized from a `(Data, URLResponse)` tuple for proxying. |
| `HTTPRequestParser` | Incremental, stateful parser. Feed it bytes with `append(_:)`, check `state`, then call `parseRequest()`. |
| `HTTPRequestSerializer` | Stateless header parser. Call `parseHeaders(from:)` with a complete `Data` buffer. |
| `ParsedHTTPRequest` | The result — either `.partial` (headers only) or `.complete` (headers + body). |
| `MultipartPart` | A parsed multipart/form-data part with `name`, `filename`, `contentType`, and `body`. |
| `RequestBody` | Abstracts body storage (in-memory or file-backed). Provides `count` (O(1) byte count), `data` (async accessor), and `makeInputStream()`. |
| `HTTPRequestParseError` | Error enum covering all rejection reasons, with human-readable `localizedDescription` messages. |

## Usage

### Running a local server

`HTTPServer` listens on the loopback interface (`127.0.0.1`) using Network.framework. Each incoming request is parsed automatically and delivered to your handler as a `ServerRequest`, which bundles the parsed HTTP request with timing diagnostics (`.parseDuration`). Your handler returns an `HTTPResponse` — the server serializes it back over the socket.

```swift
import GutenbergKitHTTP

let server = try await HTTPServer.start(name: "my-server", port: 8080) { req in
    print("\(req.parsed.method) \(req.parsed.target) (\(req.parseDuration))")
    return HTTPResponse(status: 200, body: Data("OK".utf8))
}
print("Listening on port \(server.port)")
// ... later ...
server.stop()
```

Pass `nil` (or omit `port`) to let the system assign an available port — useful for tests or when running multiple servers.

When `requiresAuthentication` is enabled (the default), each request must include a `Proxy-Authorization: Bearer <token>` header carrying the server's randomly-generated token. The server uses `Proxy-Authorization` per RFC 9110 §11.7.1 rather than `Authorization`, so the client's `Authorization` header remains available for upstream credentials (e.g. HTTP Basic auth to the remote server). Unauthenticated requests receive a `407 Proxy Authentication Required` response with a `Proxy-Authenticate: Bearer` challenge header.

### Proxying via URLSession

The most common use case: forward web editor requests to a remote WordPress site. `HTTPResponse` has a convenience initializer that accepts a `(Data, URLResponse)` tuple, so you can pipe `URLSession` results directly back.

```swift
let server = try await HTTPServer.start { req in
    let url = URL(string: "https://example.com\(req.parsed.target)")!
    var upstream = URLRequest(url: url)
    upstream.httpMethod = req.parsed.method
    return try await HTTPResponse(URLSession.shared.data(for: upstream))
}
```

### One-shot parsing

Use this when the full HTTP request is already in memory (e.g., from a test fixture or a buffered read). Pass the raw string or `Data` to the parser's convenience initializer, then call `parseRequest()` to get a `ParsedHTTPRequest`.

```swift
import GutenbergKitHTTP

let raw = "POST /wp/v2/posts HTTP/1.1\r\nHost: localhost\r\nContent-Length: 13\r\n\r\n{\"title\":\"Hi\"}"
let parser = HTTPRequestParser(raw)

let request = try parser.parseRequest()!
print(request.method)  // "POST"
print(request.target)  // "/wp/v2/posts"
print(request.header("Host"))  // Optional("localhost")
```

The `header(_:)` method performs case-insensitive lookup per RFC 9110.

### Incremental parsing

Use this when data arrives in chunks from a socket. Call `append(_:)` as bytes arrive — the parser buffers body data to a temporary file so memory stays flat even for large uploads. Check `state` to decide when to parse.

```swift
let parser = HTTPRequestParser()

// Feed data as it arrives
parser.append(firstChunk)
parser.append(secondChunk)

switch parser.state {
case .needsMoreData:
    // Keep reading from the socket
    break
case .headersComplete:
    // Headers are available but body is still arriving
    let partial = try parser.parseRequest()!
    print(partial.method, partial.target)
case .complete:
    // Everything received — parse and forward
    let request = try parser.parseRequest()!
    // ...
}
```

You can call `parseRequest()` in either `.headersComplete` or `.complete` state. In `.headersComplete`, the returned `ParsedHTTPRequest` is `.partial` (headers only, no body). In `.complete`, it is `.complete` with the full body available via `request.body`.

### Converting to URLRequest for forwarding

`ParsedHTTPRequest` can generate a Foundation `URLRequest` for forwarding to a remote server. Pass a base URL — the request's target path is resolved relative to it. The method, headers, and body are carried over automatically.

```swift
let baseURL = URL(string: "https://example.com")!
if let urlRequest = request.urlRequest(relativeTo: baseURL) {
    let (data, response) = try await URLSession.shared.data(for: urlRequest)
}
```

### Multipart parsing

For `multipart/form-data` requests (e.g., media uploads), call `multipartParts()` on a parsed request. The boundary is extracted automatically from the `Content-Type` header. Each `MultipartPart` gives you the field `name`, optional `filename` and `contentType`, and a `body` backed by the same `RequestBody` abstraction (in-memory or file-backed).

```swift
let request = try parser.parseRequest()!
let parts = try request.multipartParts()

for part in parts {
    print("\(part.name): \(try readAll(part.body))")
    if let filename = part.filename {
        print("  filename: \(filename), contentType: \(part.contentType ?? "unknown")")
    }
}
```

### Error handling

`parseRequest()` throws `HTTPRequestParseError` for malformed input. Each case maps to a specific RFC violation or safety check, and carries a human-readable `localizedDescription`.

```swift
do {
    let request = try parser.parseRequest()
} catch let error as HTTPRequestParseError {
    switch error {
    case .emptyHeaderSection:           // No request line before \r\n\r\n
    case .malformedRequestLine:         // Missing method or target
    case .obsFoldDetected:              // Continuation line (rejected per RFC 7230 §3.2.4)
    case .whitespaceBeforeColon:        // Space or tab between field-name and colon (RFC 7230 §3.2.4)
    case .invalidContentLength:         // Non-numeric or negative Content-Length
    case .conflictingContentLength:     // Multiple Content-Length headers disagree
    case .unsupportedTransferEncoding:  // Transfer-Encoding not supported
    case .invalidHTTPVersion:           // Unrecognized HTTP version
    case .invalidFieldName:             // Invalid characters in header field name
    case .invalidFieldValue:            // Invalid characters in header field value
    case .missingHostHeader:            // HTTP/1.1 requires Host
    case .multipleHostHeaders:          // Duplicate Host headers
    case .payloadTooLarge:              // Body exceeds maxBodySize (HTTP 413)
    case .headersTooLarge:              // Headers exceed limit (HTTP 431)
    case .invalidEncoding:              // Headers aren't valid UTF-8
    }

    // All cases provide a human-readable description:
    print(error.localizedDescription)
}
```

You can also limit the maximum body size by passing `maxBodySize` to the parser initializer — requests exceeding the limit throw `.payloadTooLarge`.

## RFC Conformance

The parser enforces or documents behavior for the following:

- **RFC 7230 §3.2.4** — Rejects obs-fold (continuation lines) and whitespace before colon in field names.
- **RFC 7230 §3.3.3** — Rejects conflicting `Content-Length` values across multiple headers.
- **RFC 9110 §5.3** — Combines duplicate header field lines with comma-separated values.
- **RFC 9110 §8.6** — Validates `Content-Length` values including comma-separated lists of identical values (e.g., `5, 5`).
- **RFC 9112 §3** — Parses the request line into method, target, and optional HTTP version.

Conformance is verified by 115+ tests across `HTTPRequestParserTests`, `RFC7230ConformanceTests`, and `RFC9112ConformanceTests`, plus shared cross-platform JSON test fixtures (also used by the Kotlin test suite).

## Debug Server

The companion `GutenbergKitDebugServer` executable provides a ready-made server for manual testing. See its [README](../GutenbergKitDebugServer/README.md) for details.
