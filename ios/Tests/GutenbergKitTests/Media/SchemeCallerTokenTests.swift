import Foundation
import Testing

@testable import GutenbergKit

@Suite("SchemeCallerToken")
struct SchemeCallerTokenTests {
    private let token = SchemeCallerToken(value: "0123456789abcdef")

    private func request(_ value: String?) -> URLRequest {
        var request = URLRequest(url: URL(string: "gbk-rest://relay/fetch")!)
        request.setValue(value, forHTTPHeaderField: SchemeCallerToken.header)
        return request
    }

    @Test("makes a different 64-character hex token each time")
    func generatesRandomTokens() {
        let first = SchemeCallerToken()
        let second = SchemeCallerToken()
        #expect(first.value.count == 64)
        let isHex = first.value.allSatisfy { $0.isHexDigit }
        #expect(isHex)
        #expect(first.value != second.value)
    }

    @Test("authorizes a request carrying the token")
    func authorizesTheToken() {
        #expect(token.authorizes(request("Bearer 0123456789abcdef")))
    }

    @Test("refuses a request without the exact token", arguments: [
        nil,
        "",
        "Bearer ",
        "0123456789abcdef",
        "Basic 0123456789abcdef",
        "Bearer 0123456789abcdee",
        "Bearer 0123456789abcde",
        "Bearer 0123456789abcdef0",
        "Bearer 0123456789ABCDEF",
    ])
    func refusesOtherValues(value: String?) {
        #expect(!token.authorizes(request(value)))
    }
}
