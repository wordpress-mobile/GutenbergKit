import Foundation
import Network

/// A local HTTP server for `XMLHttpRequest` lifecycle tests, which a web view's own
/// `XMLHttpRequest` and the REST relay can both reach.
///
/// Each request is answered by its path, with CORS headers that let a `file://` page
/// read the response:
///
/// - `/echo`: the request's method, body size and `Content-Type`, as JSON.
/// - `/delay`: as `/echo`, after 10 seconds.
/// - `/stall`: the headers and the start of the body, then nothing more.
/// - `/cut`: the headers and the start of the body, then the connection closes.
/// - `/cut-chunked`: as `/cut`, with the body sent in chunks.
///
/// The start of the body is 1 KB. `URLSession` holds back up to 512 bytes of a body
/// to guess its type, so the relay would get none of a shorter one.
///
/// Every response closes its connection, so no request waits behind another.
final class LifecycleHTTPServer: @unchecked Sendable {
    /// Where the server listens, such as `http://127.0.0.1:52100`.
    let origin: String

    private let listener: NWListener
    private let queue: DispatchQueue

    /// Connections that are still answering, kept until `stop()`.
    private var connections: [ObjectIdentifier: NWConnection] = [:]

    init() async throws {
        let queue = DispatchQueue(label: "LifecycleHTTPServer")
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        let listener = try NWListener(using: parameters)
        self.queue = queue
        self.listener = listener

        let port: UInt16 = try await withCheckedThrowingContinuation { continuation in
            // State changes arrive one at a time on `queue`.
            final class Once: @unchecked Sendable { var resumed = false }
            let once = Once()
            listener.stateUpdateHandler = { state in
                guard !once.resumed else { return }
                switch state {
                case .ready:
                    once.resumed = true
                    continuation.resume(returning: listener.port?.rawValue ?? 0)
                case .failed(let error):
                    once.resumed = true
                    continuation.resume(throwing: error)
                default:
                    break
                }
            }
            listener.newConnectionHandler = { _ in }
            listener.start(queue: queue)
        }
        origin = "http://127.0.0.1:\(port)"
        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }
    }

    /// Stops listening and closes every connection.
    func stop() {
        queue.sync {
            listener.cancel()
            for connection in connections.values {
                connection.cancel()
            }
            connections.removeAll()
        }
    }

    private func accept(_ connection: NWConnection) {
        connections[ObjectIdentifier(connection)] = connection
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard let self, let connection else { return }
            switch state {
            case .failed, .cancelled:
                connections.removeValue(forKey: ObjectIdentifier(connection))
            default:
                break
            }
        }
        connection.start(queue: queue)
        receive(on: connection, buffer: Data())
    }

    /// Reads until the request's head and its `Content-Length` of body have arrived.
    private func receive(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            var buffer = buffer
            if let data {
                buffer.append(data)
            }
            if let request = Request(buffer) {
                answer(request, on: connection)
            } else if isComplete || error != nil {
                connection.cancel()
            } else {
                receive(on: connection, buffer: buffer)
            }
        }
    }

    private func answer(_ request: Request, on connection: NWConnection) {
        let cors = [
            "Access-Control-Allow-Origin": "*",
            "Access-Control-Allow-Headers": "*",
            "Access-Control-Allow-Methods": "*",
            "Access-Control-Expose-Headers": "*",
        ]
        if request.method == "OPTIONS" {
            send(status: 204, headers: cors, body: Data(), on: connection)
            return
        }

        switch request.path {
        case "/stall", "/cut":
            let head = Self.head(status: 200, headers: cors.merging([
                "Content-Type": "application/octet-stream",
                "Content-Length": "100000",
            ]) { $1 })
            connection.send(content: head + Data(repeating: 97, count: 1024), completion: .contentProcessed { _ in })
            if request.path == "/cut" {
                queue.asyncAfter(deadline: .now() + 0.2) { connection.cancel() }
            }
        case "/cut-chunked":
            let head = Self.head(status: 200, headers: cors.merging([
                "Content-Type": "application/octet-stream",
                "Transfer-Encoding": "chunked",
            ]) { $1 })
            let chunk = Data("400\r\n".utf8) + Data(repeating: 97, count: 1024) + Data("\r\n".utf8)
            connection.send(content: head + chunk, completion: .contentProcessed { _ in })
            queue.asyncAfter(deadline: .now() + 0.2) { connection.cancel() }
        case "/delay":
            queue.asyncAfter(deadline: .now() + 10) { [weak self] in
                self?.echo(request, headers: cors, on: connection)
            }
        default:
            echo(request, headers: cors, on: connection)
        }
    }

    private func echo(_ request: Request, headers: [String: String], on connection: NWConnection) {
        // A multipart boundary is different on every request.
        let contentType = request.headers["content-type"].map {
            $0.hasPrefix("multipart/form-data") ? "multipart/form-data" : $0
        }
        let echo: [String: Any] = [
            "method": request.method,
            "bodyLength": request.body.count,
            "contentType": contentType ?? NSNull(),
        ]
        let body = (try? JSONSerialization.data(withJSONObject: echo, options: .sortedKeys)) ?? Data()
        send(status: 200, headers: headers.merging(["Content-Type": "application/json"]) { $1 }, body: body, on: connection)
    }

    private func send(status: Int, headers: [String: String], body: Data, on connection: NWConnection) {
        let head = Self.head(status: status, headers: headers.merging([
            "Content-Length": String(body.count),
        ]) { $1 })
        connection.send(content: head + body, completion: .contentProcessed { _ in connection.cancel() })
    }

    private static func head(status: Int, headers: [String: String]) -> Data {
        var head = "HTTP/1.1 \(status) \(HTTPURLResponse.localizedString(forStatusCode: status).capitalized)\r\n"
        for (name, value) in headers.merging(["Connection": "close"], uniquingKeysWith: { $1 }) {
            head += "\(name): \(value)\r\n"
        }
        return Data((head + "\r\n").utf8)
    }

    /// A request whose head and body have arrived whole.
    private struct Request {
        let method: String
        let path: String
        let headers: [String: String]
        let body: Data

        init?(_ data: Data) {
            guard let end = data.firstRange(of: Data("\r\n\r\n".utf8)),
                  let head = String(data: data[..<end.lowerBound], encoding: .utf8) else {
                return nil
            }
            var lines = head.components(separatedBy: "\r\n")
            let requestLine = lines.removeFirst().split(separator: " ")
            guard requestLine.count >= 2 else { return nil }

            var headers: [String: String] = [:]
            for line in lines {
                guard let colon = line.firstIndex(of: ":") else { continue }
                let name = line[..<colon].lowercased()
                headers[name] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            }
            let length = headers["content-length"].flatMap(Int.init) ?? 0
            let body = data[end.upperBound...]
            guard body.count >= length else { return nil }

            self.method = String(requestLine[0])
            self.path = URLComponents(string: String(requestLine[1]))?.path ?? "/"
            self.headers = headers
            self.body = Data(body.prefix(length))
        }
    }
}
