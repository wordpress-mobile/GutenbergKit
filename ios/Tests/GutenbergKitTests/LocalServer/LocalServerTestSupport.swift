import Foundation
@testable import GutenbergKit

/// Whether `HTTPServer` can bind in this environment (it cannot in some test
/// sandboxes). Suites that start a real server are enabled on this.
let localServerCanBind: Bool = {
  let result = UnsafeMutableSendablePointer(false)
  let semaphore = DispatchSemaphore(value: 0)
  Task {
    do {
      let server = try await EditorLocalServer.start(routes: [])
      server.stop()
      result.value = true
    } catch {
      result.value = false
    }
    semaphore.signal()
  }
  semaphore.wait()
  return result.value
}()

/// Sendable wrapper for a mutable value, used to communicate results out of a Task.
private final class UnsafeMutableSendablePointer<T>: @unchecked Sendable {
  var value: T
  init(_ value: T) { self.value = value }
}

/// A `multipart/form-data` body carrying one file part, as the editor's upload
/// request does.
func buildMultipartBody(boundary: String, filename: String, mimeType: String, data: Data) -> Data {
  var body = Data()
  body.append("--\(boundary)\r\n")
  body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n")
  body.append("Content-Type: \(mimeType)\r\n\r\n")
  body.append(data)
  body.append("\r\n--\(boundary)--\r\n")
  return body
}

extension URLRequest {
  /// Adds the header WebKit sets on every cross-origin `fetch()` the editor
  /// makes. The server rejects requests carrying neither `Origin` nor
  /// `Sec-Fetch-Site` (see `requiresBrowserOrigin`), so a test standing in for
  /// the web view has to look like one.
  mutating func setBrowserOrigin() {
    setValue("file://", forHTTPHeaderField: "Origin")
  }
}

private extension Data {
  mutating func append(_ string: String) {
    append(string.data(using: .utf8)!)
  }
}
