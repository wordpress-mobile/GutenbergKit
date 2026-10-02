import Foundation
import WebKit

/// Hands files native code holds to the editor's page as `File` objects.
///
/// The page clicks a file input (`requestNativeFiles` in `src/utils/native-files.js`),
/// and this object answers the open panel WebKit would otherwise show with the files on
/// offer. The page gets what the system picker gives it: `File`s that WebKit reads from
/// disk as they are sliced, so a large video costs the page no memory, and a block that
/// uploads on its own gets the real bytes.
///
/// WebKit asks its UI delegate for the panel from iOS 18.4. A delegate that implements
/// the method answers every file input, so this object is the web view's UI delegate
/// only while it has files on offer — any other input keeps the system picker.
@MainActor
final class NativeFileInput: NSObject, WKUIDelegate {
    /// Whether WebKit asks the UI delegate for a file input's files on this OS.
    nonisolated static var isSupported: Bool {
        if #available(iOS 18.4, macOS 10.12, visionOS 2.4, *) {
            return true
        }
        return false
    }

    private var offered: [URL]?

    /// Whether files are on offer and no file input has claimed them yet.
    var hasOffer: Bool { offered != nil }

    /// Runs `operation` with `files` on offer to the first file input `webView`'s page
    /// clicks, and returns its result.
    ///
    /// The offer ends when `operation` returns, whether or not the page took it. With
    /// nothing to offer, or an offer already open, `operation` runs without one and the
    /// page fetches the files itself.
    func offer<T>(
        _ files: [URL],
        to webView: WKWebView,
        while operation: () async throws -> T
    ) async rethrows -> T {
        guard Self.isSupported, !files.isEmpty, offered == nil else {
            return try await operation()
        }
        let previousDelegate = webView.uiDelegate
        offered = files
        webView.uiDelegate = self
        defer {
            offered = nil
            webView.uiDelegate = previousDelegate
        }
        return try await operation()
    }

    /// The files on offer, which the first file input to ask gets. A second one gets
    /// `nil`, which WebKit treats as the panel being cancelled.
    func takeOffer() -> [URL]? {
        defer { offered = nil }
        return offered
    }

    @available(iOS 18.4, macOS 10.12, visionOS 2.4, *)
    func webView(
        _ webView: WKWebView,
        runOpenPanelWith parameters: WKOpenPanelParameters,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping @MainActor @Sendable ([URL]?) -> Void
    ) {
        completionHandler(takeOffer())
    }
}
