import Foundation
import GutenbergKitHTTP

let port: UInt16? = CommandLine.arguments.dropFirst().first.flatMap(UInt16.init)

let server = try await HTTPServer.start(name: "debug-server", port: port) { req in
    await logRequest(req)

    if let response = await fetchUrl(req) {
        return response
    }

    let request = req.parsed

    let json: [String: Any] = [
        "method": request.method,
        "target": request.target,
        "headers": request.headerCount,
        "status": "ok"
    ]
    let body = try! JSONSerialization.data(withJSONObject: json)

    return HTTPResponse(
        status: 200,
        headers: [("Content-Type", "application/json")],
        body: body
    )
}

print("GutenbergKitDebugServer listening on http://localhost:\(server.port)")
print("Proxy-Authorization: Bearer \(server.token)")
try await Task.sleep(for: .seconds(86400)) // Run the server for 24 hours

func fetchUrl(_ req: HTTPServer.Request) async -> HTTPServer.Response? {
    guard let urlString = req.parsed.header("X-URL-to-fetch"), let url = URL(string: urlString) else {
        return nil
    }

    guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
        return HTTPResponse(status: 400, body: Data("Only http/https URLs are supported".utf8))
    }

    do {
        let filteredHeaders: Set<String> = [
            "host", "x-url-to-fetch", "proxy-authorization"
        ]

        var request = URLRequest(url: url)
        request.httpMethod = req.parsed.method
        for (name, value) in req.parsed.allHeaders where !filteredHeaders.contains(name.lowercased()) {
            request.setValue(value, forHTTPHeaderField: name)
        }

        print("  Requesting \(url)")
        print("    Method: \(request.httpMethod)")
        print("    Headers: \(String(describing: request.allHTTPHeaderFields))")

        return try await HTTPResponse(URLSession.shared.data(for: request))
    } catch {
        print("    Request Failed: \(error.localizedDescription)")
        return HTTPResponse(status: 500, body: Data(error.localizedDescription.utf8))
    }
}

// MARK: - Logging

func logRequest(_ req: HTTPServer.Request) async {
    let request = req.parsed
    let timestamp = ISO8601DateFormatter().string(from: Date())
    let ms = String(format: "%.2f", Double(req.parseDuration.components.attoseconds) / 1e15)
    print("[\(timestamp)] \(request.method) \(request.target) (\(ms)ms)")

    for (name, value) in request.allHeaders {
        print("  \(name): \(value)")
    }

    if let body = request.body {
        print("  Body: \(body.count) bytes")

        if let parts = try? request.multipartParts() {
            print("  Multipart: \(parts.count) part(s)")
            for (i, part) in parts.enumerated() {
                let filename = part.filename.map { " filename=\"\($0)\"" } ?? ""
                print("    [\(i)] name=\"\(part.name)\"\(filename) (\(part.contentType))")
                print("        \(part.body.count) bytes")
                if part.body.count <= 200, let text = try? await String(data: part.body.data, encoding: .utf8) {
                    print("        \(text)")
                }
            }
        } else if body.count <= 500, let text = try? await String(data: body.data, encoding: .utf8) {
            print("  \(text)")
        }
    }
    print()
    fflush(stdout)
}
