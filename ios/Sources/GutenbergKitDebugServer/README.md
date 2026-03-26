# GutenbergKitDebugServer

A command-line HTTP server for testing and debugging the `GutenbergKitHTTP` module. It logs incoming requests in detail and can optionally proxy them to an upstream URL.

## Running

```bash
swift run GutenbergKitDebugServer        # auto-assign a port
swift run GutenbergKitDebugServer 8080   # listen on port 8080
```

## What it does

For every incoming request, the server:

1. **Logs** the method, target, headers, body size, and parse duration.
2. **Inspects multipart bodies** — if the request has a `multipart/form-data` content type, each part's name, filename, content type, and size are printed. Small parts (≤ 200 bytes) have their text content printed inline.
3. **Proxies** the request if an `X-URL-to-fetch` header is present. The header value is used as the upstream URL; the original method and headers (minus `Host` and `X-URL-to-fetch`) are forwarded via `URLSession`. The upstream response is returned to the client.
4. **Echoes** a JSON summary if no proxy header is set.

## Example output

```
GutenbergKitDebugServer listening on http://localhost:49312
[2026-03-10T12:00:00Z] POST /wp/v2/media (0.42ms)
  Host: localhost:49312
  Content-Type: multipart/form-data; boundary=----FormBoundary
  Content-Length: 1234
  Body: 1234 bytes
  Multipart: 2 part(s)
    [0] name="title" (text/plain)
        5 bytes
        Hello
    [1] name="file" filename="photo.jpg" (image/jpeg)
        1100 bytes
```
