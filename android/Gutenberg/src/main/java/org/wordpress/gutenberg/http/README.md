# Kotlin HTTP Parser

A zero-dependency pure-Kotlin module providing an HTTP/1.1 request parser. Designed for use as the front-end of an in-process HTTP proxy server, where raw bytes arrive over a socket and need to be converted into structured request objects suitable for forwarding via `HttpURLConnection`.

## Why

GutenbergKit's Android integration uses an in-process HTTP server to bridge requests between the embedded web editor and native networking. This module handles the parsing side of that bridge — turning raw TCP bytes into structured request objects — without pulling in a full HTTP server framework.

Key design goals:

- **Incremental parsing** — data can arrive in arbitrary chunks (byte-by-byte if needed); the parser buffers to disk so memory usage stays flat regardless of body size.
- **Lazy validation** — `append()` does only lightweight scanning (finding `\r\n\r\n` and extracting `Content-Length`). Full RFC validation is deferred to `parseRequest()`, keeping the hot path fast.
- **Strict conformance** — rejects request smuggling vectors (obs-fold, whitespace before colon), validates `Content-Length` per RFC 9110 §8.6, and combines duplicate headers per RFC 9110 §5.3.
- **No dependencies** — uses only the Kotlin and Java standard libraries.

## Types

| Type | Role |
|------|------|
| `HTTPRequestParser` | Incremental, stateful parser. Feed it bytes with `append()`, check `state`, then call `parseRequest()`. |
| `HTTPRequestSerializer` | Stateless header parser. Call `parseHeaders()` with a complete `ByteArray` buffer. |
| `ParsedHTTPRequest` | The result — a data class with `isComplete` indicating whether the body has fully arrived. |
| `RequestBody` | Abstracts body storage (in-memory or file-backed). Provides `size` (O(1) byte count), `readBytes()`, and `inputStream()`. |
| `MultipartPart` | A parsed multipart/form-data part with `name`, `filename`, `contentType`, and `body`. |
| `HTTPRequestParseError` | Error enum covering all rejection reasons, with `errorId` strings matching the Swift implementation. |

The `HttpServer` class in the parent package (`org.wordpress.gutenberg`) provides a complete local HTTP/1.1 server built on top of this parser.

## Usage

### One-shot parsing

Use this when the full HTTP request is already in memory (e.g., from a test fixture or a buffered read). Pass the raw string to the parser's convenience constructor, then call `parseRequest()` to get a `ParsedHTTPRequest`.

```kotlin
import org.wordpress.gutenberg.http.HTTPRequestParser

val raw = "POST /wp/v2/posts HTTP/1.1\r\nHost: localhost\r\nContent-Length: 13\r\n\r\n{\"title\":\"Hi\"}"
val parser = HTTPRequestParser(raw)

val request = parser.parseRequest()!!
println(request.method)           // "POST"
println(request.target)           // "/wp/v2/posts"
println(request.header("Host"))   // "localhost"
```

The `header()` method performs case-insensitive lookup per RFC 9110. You can also access the full `headers` map directly.

### Incremental parsing

Use this when data arrives in chunks from a socket. Call `append()` as bytes arrive — the parser buffers body data to a temporary file so memory stays flat even for large uploads. Check `state` to decide when to parse.

```kotlin
val parser = HTTPRequestParser()

// Feed data as it arrives
parser.append(firstChunk)
parser.append(secondChunk)

when {
    parser.state == State.NEEDS_MORE_DATA -> {
        // Keep reading from the socket
    }
    parser.state == State.HEADERS_COMPLETE -> {
        // Headers are available but body is still arriving
        val partial = parser.parseRequest()!!
        println("${partial.method} ${partial.target}")
    }
    parser.state == State.COMPLETE -> {
        // Everything received — parse and forward
        val request = parser.parseRequest()!!
        // ...
    }
}
```

You can call `parseRequest()` in either `HEADERS_COMPLETE` or `COMPLETE` state. In `HEADERS_COMPLETE`, the returned `ParsedHTTPRequest` has `isComplete = false` (headers only, body still arriving). In `COMPLETE`, `isComplete = true` with the full body available via `request.body`.

### Running a local server

`HttpServer` uses a `ServerSocket` on a background thread. Set `externallyAccessible = true` to bind to `0.0.0.0` (for device-to-device testing), or `false` to bind to `127.0.0.1` only. Each request is parsed automatically and delivered to your handler as an `HttpRequest`, which includes `parseDurationMs` for diagnostics. The server generates a random `token` that clients must include as `Proxy-Authorization: Bearer <token>` (per RFC 9110 §11.7.1). Using `Proxy-Authorization` instead of `Authorization` keeps the client's `Authorization` header available for upstream credentials (e.g. HTTP Basic auth to the remote server).

```kotlin
import org.wordpress.gutenberg.HttpServer
import org.wordpress.gutenberg.HttpResponse

val server = HttpServer(
    name = "my-server",
    externallyAccessible = true,
    handler = { request ->
        println("${request.method} ${request.target} (${"%.2f".format(request.parseDurationMs)}ms)")
        HttpResponse(body = "OK\n".toByteArray())
    }
)
server.start()
println("Listening on port ${server.port}, token: ${server.token}")
// ... later ...
server.stop()
```

### Multipart parsing

For `multipart/form-data` requests (e.g., media uploads), call `multipartParts()` on a parsed request. The boundary is extracted automatically from the `Content-Type` header. Each `MultipartPart` gives you the field `name`, optional `filename` and `contentType`, and a `body` backed by the same `RequestBody` abstraction (in-memory or file-backed).

```kotlin
val request = parser.parseRequest()!!
val parts = request.multipartParts()

for (part in parts) {
    println("${part.name}: ${String(part.body.readBytes())}")
    if (part.filename != null) {
        println("  filename: ${part.filename}, contentType: ${part.contentType}")
    }
}
```

### Error handling

`parseRequest()` throws `HTTPRequestParseException` for malformed input. Each error case maps to a specific RFC violation or safety check. The `errorId` strings match the Swift implementation for cross-platform consistency, and each error carries an `httpStatus` code suitable for responding to the client.

```kotlin
try {
    val request = parser.parseRequest()
} catch (e: HTTPRequestParseException) {
    when (e.error) {
        HTTPRequestParseError.EMPTY_HEADER_SECTION -> // No request line before \r\n\r\n
        HTTPRequestParseError.MALFORMED_REQUEST_LINE -> // Missing method or target
        HTTPRequestParseError.OBS_FOLD_DETECTED -> // Continuation line (rejected per RFC 7230 §3.2.4)
        HTTPRequestParseError.WHITESPACE_BEFORE_COLON -> // Space or tab between field-name and colon (RFC 7230 §3.2.4)
        HTTPRequestParseError.INVALID_CONTENT_LENGTH -> // Non-numeric or negative Content-Length
        HTTPRequestParseError.CONFLICTING_CONTENT_LENGTH -> // Multiple Content-Length headers disagree
        HTTPRequestParseError.UNSUPPORTED_TRANSFER_ENCODING -> // Transfer-Encoding not supported
        HTTPRequestParseError.INVALID_HTTP_VERSION -> // Unrecognized HTTP version
        HTTPRequestParseError.INVALID_FIELD_NAME -> // Invalid characters in header field name
        HTTPRequestParseError.INVALID_FIELD_VALUE -> // Invalid characters in header field value
        HTTPRequestParseError.MISSING_HOST_HEADER -> // HTTP/1.1 requires Host
        HTTPRequestParseError.MULTIPLE_HOST_HEADERS -> // Duplicate Host headers
        HTTPRequestParseError.PAYLOAD_TOO_LARGE -> // Body exceeds maxBodySize (HTTP 413)
        HTTPRequestParseError.HEADERS_TOO_LARGE -> // Headers exceed limit (HTTP 431)
        HTTPRequestParseError.INVALID_ENCODING -> // Headers aren't valid UTF-8
    }

    // All cases provide an HTTP status code:
    println("HTTP ${e.error.httpStatus}")
}
```

You can also limit the maximum body size by passing `maxBodySize` to the parser constructor — requests exceeding the limit throw `PAYLOAD_TOO_LARGE`.

## RFC Conformance

The parser enforces or documents behavior for the following:

- **RFC 7230 §3.2.4** — Rejects obs-fold (continuation lines) and whitespace before colon in field names.
- **RFC 7230 §3.3.3** — Rejects conflicting `Content-Length` values across multiple headers.
- **RFC 9110 §5.3** — Combines duplicate header field lines with comma-separated values.
- **RFC 9110 §8.6** — Validates `Content-Length` values including comma-separated lists of identical values (e.g., `5, 5`).
- **RFC 9112 §3** — Parses the request line into method, target, and optional HTTP version.

Conformance is verified by shared cross-platform JSON test fixtures (also used by the Swift test suite) plus Kotlin-specific unit tests.
