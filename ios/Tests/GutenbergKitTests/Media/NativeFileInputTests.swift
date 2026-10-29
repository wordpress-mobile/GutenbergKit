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

  @Test("puts the host's delegate back when a second offer starts after the first was taken and ends after it")
  func overlappingOffersRestoreTheHostDelegate() async {
    let input = NativeFileInput()
    let webView = WKWebView()
    let host = HostDelegate()
    webView.uiDelegate = host
    let parked = ParkedOperations()

    // The first offer's files are taken, and its operation is still running when the
    // second offer starts. The second outlives the first.
    let first = Task {
      await input.offer(files, to: webView) {
        _ = input.takeOffer()
        await parked.park("first")
      }
    }
    await parked.waitUntilParked("first")
    let second = Task {
      await input.offer([URL(fileURLWithPath: "/tmp/other.jpg")], to: webView) {
        await parked.park("second")
      }
    }
    await parked.waitUntilParked("second")
    parked.release("first")
    await first.value
    parked.release("second")
    await second.value

    #expect(webView.uiDelegate === host, "the offer outlived both operations")
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

/// Operations that wait, each under a name, until the test releases them.
@MainActor
private final class ParkedOperations {
  private var waiting: [String: CheckedContinuation<Void, Never>] = [:]

  func park(_ name: String) async {
    await withCheckedContinuation { waiting[name] = $0 }
  }

  func waitUntilParked(_ name: String) async {
    while waiting[name] == nil {
      await Task.yield()
    }
  }

  func release(_ name: String) {
    waiting.removeValue(forKey: name)?.resume()
  }
}
