import Foundation
import Testing
@testable import GutenbergKitHTTP

@Suite("CORSPolicy")
struct CORSPolicyTests {

    @Test("advertises exactly the request headers it allows")
    func advertisesAllowedRequestHeaders() {
        // One source of truth: the advertised value is built from the list the
        // preflight diagnostic checks against, so the two cannot disagree.
        let headers = CORSPolicy.permissive.responseHeaders
        let advertised = headers.first { $0.0 == "Access-Control-Allow-Headers" }?.1

        #expect(advertised == "Authorization, Content-Type, Relay-Authorization, X-HTTP-Method-Override")
    }

    @Test("reports an announced header the policy will not allow")
    func reportsUnallowedHeader() {
        // The browser refuses the request on this, reporting only an opaque
        // CORS error — a plugin's api-fetch middleware adding its own header is
        // the case that produces it.
        let announced = "relay-authorization, x-wp-api-fetch-from-editor"

        #expect(
            CORSPolicy.permissive.unallowedHeaders(announced: announced)
                == ["x-wp-api-fetch-from-editor"]
        )
    }

    @Test("reports nothing when every announced header is allowed")
    func allowsAnnouncedHeaders() {
        // Case and spacing vary by browser; neither should read as a refusal.
        #expect(CORSPolicy.permissive.unallowedHeaders(announced: "relay-authorization").isEmpty)
        #expect(CORSPolicy.permissive.unallowedHeaders(announced: "Content-Type,  RELAY-AUTHORIZATION").isEmpty)
        #expect(CORSPolicy.permissive.unallowedHeaders(announced: nil).isEmpty)
        #expect(CORSPolicy.permissive.unallowedHeaders(announced: "").isEmpty)
    }

    @Test("reports nothing under a policy that does not answer preflights")
    func reportsNothingWithoutAPolicy() {
        // `.none` sends no allow list and forwards the preflight to the
        // handler, so the library is in no position to call a header refused.
        #expect(CORSPolicy.none.unallowedHeaders(announced: "x-anything").isEmpty)
    }
}
