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

  // "Addressable" is spelled as scheme and host both being present. A URL missing
  // either cannot reach the site, and every request built from it fails at the
  // URLSession layer. Android asserts the same two arms in its own
  // `MediaServerCredentialsTest` — keep the cases in step.

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

  // MARK: - requireCredentialsForUploader

  @Test("accepts usable credentials, uploader or not", arguments: [true, false])
  func acceptsUsableCredentials(hasUploader: Bool) {
    MediaServerCredentials.requireCredentialsForUploader(
      siteApiRoot: Self.siteRoot, authHeader: "Bearer t", hasUploader: hasUploader
    )
  }

  @Test("ignores missing credentials when there is no uploader")
  func ignoresMissingCredentialsWithoutUploader() {
    // Nothing to deliver through, so nothing to process. This is not an error — the
    // server just stays down (`areUsable` decides that) and uploads fall to the
    // default WebView path, so a processor-only host must not trap here.
    MediaServerCredentials.requireCredentialsForUploader(
      siteApiRoot: Self.siteRoot, authHeader: "", hasUploader: false
    )
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
      MediaServerCredentials.requireCredentialsForUploader(
        siteApiRoot: URL(string: "https://example.com/wp-json/")!, authHeader: "", hasUploader: true
      )
    }
  }

  @Test("traps for an uploader with no site root")
  func trapsForUploaderWithoutSiteRoot() async {
    await #expect(processExitsWith: .failure) {
      MediaServerCredentials.requireCredentialsForUploader(
        siteApiRoot: URL(string: "/")!, authHeader: "Bearer t", hasUploader: true
      )
    }
  }

#endif
}
