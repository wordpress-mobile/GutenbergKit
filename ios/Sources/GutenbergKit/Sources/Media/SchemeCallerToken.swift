import Foundation
import Security

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
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        precondition(status == errSecSuccess, "Failed to generate a scheme caller token")
        self.value = bytes.map { String(format: "%02x", $0) }.joined()
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
        return Self.constantTimeEqual(Array(sent.dropFirst("Bearer ".count).utf8), Array(value.utf8))
    }

    /// Compares in time that depends only on the expected token's length, so the time
    /// a refusal takes doesn't reveal how much of a guess was right.
    private static func constantTimeEqual(_ provided: [UInt8], _ expected: [UInt8]) -> Bool {
        var difference = UInt8(provided.count == expected.count ? 0 : 1)
        for index in expected.indices {
            let byte = index < provided.count ? provided[index] : 0
            difference |= byte ^ expected[index]
        }
        return difference == 0
    }
}
