import Foundation
import Testing
import WebKit

@testable import GutenbergKit

@MainActor
@Suite("NativeFileInput", .enabled(if: NativeFileInput.isSupported))
struct NativeFileInputTests {
  private let files = [URL(fileURLWithPath: "/tmp/IMG_0001.MOV"), URL(fileURLWithPath: "/tmp/IMG_0002.HEIC")]

  @Test("is the web view's UI delegate only while files are on offer")
  func offersForTheOperationOnly() async {
    let input = NativeFileInput()
    let webView = WKWebView()

    let duringOffer = await input.offer(files, to: webView) {
      (delegate: webView.uiDelegate === input, hasOffer: input.hasOffer)
    }

    #expect(duringOffer.delegate)
    #expect(duringOffer.hasOffer)
    #expect(webView.uiDelegate == nil)
    #expect(!input.hasOffer)
  }

  @Test("gives the offer to the first file input that asks, in order, and to no other")
  func offerIsTakenOnce() async {
    let input = NativeFileInput()
    let webView = WKWebView()

    let (first, second) = await input.offer(files, to: webView) {
      (input.takeOffer(), input.takeOffer())
    }

    #expect(first == files)
    #expect(second == nil)
  }

  @Test("puts the host's own UI delegate back")
  func restoresTheHostDelegate() async {
    let input = NativeFileInput()
    let webView = WKWebView()
    let host = HostDelegate()
    webView.uiDelegate = host

    await input.offer(files, to: webView) {}

    #expect(webView.uiDelegate === host)
  }

  @Test("ends the offer when the operation throws")
  func endsTheOfferOnFailure() async {
    let input = NativeFileInput()
    let webView = WKWebView()

    await #expect(throws: CancellationError.self) {
      try await input.offer(files, to: webView) { throw CancellationError() }
    }

    #expect(webView.uiDelegate == nil)
    #expect(!input.hasOffer)
  }

  @Test("runs the operation without an offer when there is nothing to offer")
  func nothingToOffer() async {
    let input = NativeFileInput()
    let webView = WKWebView()

    let wasDelegate = await input.offer([], to: webView) { webView.uiDelegate === input }

    #expect(!wasDelegate)
  }

  @Test("leaves an open offer alone when asked for a second one")
  func oneOfferAtATime() async {
    let input = NativeFileInput()
    let webView = WKWebView()
    let other = [URL(fileURLWithPath: "/tmp/other.jpg")]

    let taken = await input.offer(files, to: webView) {
      await input.offer(other, to: webView) {}
      return (delegate: webView.uiDelegate === input, files: input.takeOffer())
    }

    #expect(taken.delegate, "the second offer ended the first")
    #expect(taken.files == files)
  }
}

@MainActor
@Suite("NativeFileInput before iOS 18.4", .enabled(if: !NativeFileInput.isSupported))
struct UnsupportedNativeFileInputTests {
  @Test("runs the operation without an offer, and leaves the web view's delegate alone")
  func makesNoOffer() async {
    let input = NativeFileInput()
    let webView = WKWebView()

    let during = await input.offer([URL(fileURLWithPath: "/tmp/IMG_0001.MOV")], to: webView) {
      (delegate: webView.uiDelegate === input, hasOffer: input.hasOffer)
    }

    #expect(!during.delegate)
    #expect(!during.hasOffer)
  }
}

private final class HostDelegate: NSObject, WKUIDelegate {}
