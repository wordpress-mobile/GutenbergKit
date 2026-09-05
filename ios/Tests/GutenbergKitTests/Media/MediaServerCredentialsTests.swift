import Foundation
import Testing

@testable import GutenbergKit

/// The upload server's start policy: both a site API root and an auth header are
/// required, and a `mediaUploader` set without them is a configuration error rather
/// than a silent fallback.
///
/// These run on the **host**, which is the point of `MediaServerCredentials` being
/// outside `EditorViewController` — that type is UIKit-gated and so untestable here,
/// and Swift Testing's exit tests (which is how the trap below is asserted) are
/// unavailable on iOS and the simulator. The Android counterparts live in
/// `GutenbergViewUploadServerTest`.
@Suite("Media server credentials")
struct MediaServerCredentialsTests {
    static let apiRoot = URL(string: "https://example.com/wp-json/")!

    @Test("both a site API root and an auth header are usable")
    func bothPresentIsUsable() {
        #expect(MediaServerCredentials.areUsable(siteApiRoot: Self.apiRoot, authHeader: "Bearer t"))
    }

    @Test("an empty auth header is not usable")
    func emptyAuthHeaderIsNotUsable() {
        #expect(!MediaServerCredentials.areUsable(siteApiRoot: Self.apiRoot, authHeader: ""))
    }

    @Test("a relative site API root is not usable")
    func relativeSiteApiRootIsNotUsable() {
        // The iOS analogue of Android's `siteApiRoot.isEmpty()`. A host can't pass "",
        // because the type is `URL` — but it can pass one with no scheme or host, which
        // is just as unusable: every request built from it fails at the URLSession layer.
        #expect(!MediaServerCredentials.areUsable(siteApiRoot: URL(string: "/wp-json/")!, authHeader: "Bearer t"))
    }

    @Test("a scheme without a host is not usable")
    func schemeWithoutHostIsNotUsable() {
        #expect(!MediaServerCredentials.areUsable(siteApiRoot: URL(string: "https:///wp-json/")!, authHeader: "Bearer t"))
    }

    @Test("a processor without credentials leaves the server down rather than trapping")
    func processorWithoutCredentialsDoesNotTrap() {
        // The other half of the fork: a processor only enhances GutenbergKit-owned
        // uploads, so with nothing to deliver through there's nothing to process. The
        // caller leaves the server down and uploads fall to the default WebView path.
        #expect(!MediaServerCredentials.canStartServer(siteApiRoot: Self.apiRoot, authHeader: "", hasUploader: false))
    }

    @Test("credentials present means the server can start")
    func credentialsPresentCanStart() {
        #expect(MediaServerCredentials.canStartServer(siteApiRoot: Self.apiRoot, authHeader: "Bearer t", hasUploader: true))
    }

    @Test("an uploader without an auth header traps")
    func uploaderWithoutAuthHeaderTraps() async {
        await #expect(processExitsWith: .failure) {
            _ = MediaServerCredentials.canStartServer(
                siteApiRoot: MediaServerCredentialsTests.apiRoot, authHeader: "", hasUploader: true
            )
        }
    }

    @Test("an uploader without a usable site API root traps")
    func uploaderWithoutSiteApiRootTraps() async {
        await #expect(processExitsWith: .failure) {
            _ = MediaServerCredentials.canStartServer(
                siteApiRoot: URL(string: "/wp-json/")!, authHeader: "Bearer t", hasUploader: true
            )
        }
    }
}
