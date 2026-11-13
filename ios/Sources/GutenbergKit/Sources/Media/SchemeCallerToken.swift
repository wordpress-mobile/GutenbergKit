import Foundation

/// A per-editor secret that a request to the native URL schemes must carry.
///
/// Native code hands it to the editor page in `window.GBKit`, which is injected into
/// the main frame only. The page sends it in ``header`` on every `gbk-rest:` and
/// `gbk-upload:` request, and ``RestRelaySchemeHandler`` and
/// ``MediaUploadSchemeHandler`` refuse a request without it. A frame that can't read
/// the page's `GBKit` can't learn it, so it can't use the schemes. Mirrors the token
/// Android's loopback `HttpServer` requires.
///
/// One token serves both schemes for the editor's lifetime. It is never stored.
struct SchemeCallerToken: Sendable {
    /// The request header that carries the token, as `Bearer <token>`. Android's
    /// loopback server takes the same header. Never sent on to the site.
    static let header = "Relay-Authorization"

    /// The token, as 64 lowercase hexadecimal characters.
    let value: String

    /// A new random token.
    init() {
        var generator = SystemRandomNumberGenerator()
        let words = (0..<4).map { _ in generator.next() }  // 4 × UInt64 = 256 bits
        self.value = words.map { String(format: "%016llx", $0) }.joined()
    }

    init(value: String) {
        self.value = value
    }

    /// Whether `request` carries this token in ``header``.
    func authorizes(_ request: URLRequest) -> Bool {
        guard let sent = request.value(forHTTPHeaderField: Self.header),
              sent.hasPrefix("Bearer ") else {
            return false
        }
        let provided = Array(sent.utf8.dropFirst("Bearer ".count))
        let expected = Array(value.utf8)
        return provided.count == expected.count
            && timingsafe_bcmp(provided, expected, expected.count) == 0
    }
}
