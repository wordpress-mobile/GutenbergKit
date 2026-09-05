import Foundation
import Testing

@testable import GutenbergKit

@Suite("MediaServerCredentials")
struct MediaServerCredentialsTests {
  private static let siteRoot = URL(string: "https://example.com/wp-json/")!

  @Test("accepts an absolute site root with an auth header")
  func acceptsUsableCredentials() {
    #expect(MediaServerCredentials.areUsable(siteApiRoot: Self.siteRoot, authHeader: "Bearer t"))
  }

  @Test("rejects an empty auth header")
  func rejectsEmptyAuthHeader() {
    #expect(!MediaServerCredentials.areUsable(siteApiRoot: Self.siteRoot, authHeader: ""))
  }

  // The two arms below are what a `URL` makes different from Android's `String`:
  // `isEmpty()` has no direct equivalent, so "addressable" is spelled as scheme and
  // host both being present. A URL missing either cannot reach the site, and every
  // request built from it fails at the URLSession layer.

  @Test("rejects a site root with no scheme")
  func rejectsSchemelessSiteRoot() {
    let relative = URL(string: "example.com/wp-json/")!
    #expect(!MediaServerCredentials.areUsable(siteApiRoot: relative, authHeader: "Bearer t"))
  }

  @Test("rejects a site root with no host")
  func rejectsHostlessSiteRoot() {
    let fileURL = URL(fileURLWithPath: "/tmp/wp-json")
    #expect(!MediaServerCredentials.areUsable(siteApiRoot: fileURL, authHeader: "Bearer t"))
  }

  @Test("rejects an empty site root, the default when a host configures none")
  func rejectsEmptySiteRoot() {
    #expect(!MediaServerCredentials.areUsable(siteApiRoot: URL(string: "/")!, authHeader: "Bearer t"))
  }

  // MARK: - canStartServer

  @Test("starts with usable credentials, uploader or not", arguments: [true, false])
  func startsWithUsableCredentials(hasUploader: Bool) {
    #expect(MediaServerCredentials.canStartServer(
      siteApiRoot: Self.siteRoot, authHeader: "Bearer t", hasUploader: hasUploader
    ))
  }

  @Test("declines to start for a processor with no credentials")
  func declinesForProcessorWithoutCredentials() {
    // Nothing to deliver through, so nothing to process — the caller leaves the
    // server down and uploads fall to the default WebView path.
    #expect(!MediaServerCredentials.canStartServer(
      siteApiRoot: Self.siteRoot, authHeader: "", hasUploader: false
    ))
  }

  // Exit tests run the body in a child process, so they can assert the trap itself.
  // They are unavailable on iOS — including the simulator — and referencing them
  // there is a *compile* error rather than a skip, so the whole block is gated to
  // the host platform. This is exactly why the policy lives outside
  // `EditorViewController`: that type is `#if canImport(UIKit)`, so on the one
  // platform that can run these tests it does not exist.
#if os(macOS)

  @Test("traps for an uploader with no auth header")
  func trapsForUploaderWithoutAuthHeader() async {
    await #expect(processExitsWith: .failure) {
      _ = MediaServerCredentials.canStartServer(
        siteApiRoot: URL(string: "https://example.com/wp-json/")!, authHeader: "", hasUploader: true
      )
    }
  }

  @Test("traps for an uploader with no site root")
  func trapsForUploaderWithoutSiteRoot() async {
    await #expect(processExitsWith: .failure) {
      _ = MediaServerCredentials.canStartServer(
        siteApiRoot: URL(string: "/")!, authHeader: "Bearer t", hasUploader: true
      )
    }
  }

#endif
}
