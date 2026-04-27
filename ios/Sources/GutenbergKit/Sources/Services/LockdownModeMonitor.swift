import Foundation
import SwiftUI
import WebKit
import OSLog

#if canImport(UIKit)
import UIKit
#endif

/// Protocol for objects that can be checked for Lockdown Mode status.
///
/// This protocol enables testability by allowing mock implementations
/// that simulate different Lockdown Mode states.
@MainActor
protocol LockdownModeDetectable: AnyObject {
    /// Returns `true` if Lockdown Mode is enabled for this object.
    var isLockdownModeEnabled: Bool { get }
}

/// Extension to make WKWebView conform to LockdownModeDetectable.
extension WKWebView: LockdownModeDetectable {
    var isLockdownModeEnabled: Bool {
        configuration.defaultWebpagePreferences.isLockdownModeEnabled
    }
}

/// Monitors Lockdown Mode status and presents warning UI when needed.
///
/// This class handles detection of iOS Lockdown Mode in the WebView and manages
/// the presentation of a warning sheet to inform users about potential editor limitations.
@MainActor
class LockdownModeMonitor: ObservableObject {

    @Published
    public var isLockdownModeEnabled: Bool

    /// Indicates whether the Lockdown Mode sheet has been shown to the user.
    private var hasShownSheet = false

    /// Indicates whether we should show the lockdown sheet on next editor load.
    private var shouldShowSheet = false

    #if canImport(UIKit)
    /// Weak reference to the view controller that will present the sheet.
    private weak var presentingViewController: UIViewController?
    #endif

    /// Weak reference to the detectable object for re-checking on foreground.
    private weak var detectable: LockdownModeDetectable?

    init(isLockdownModeEnabled: Bool = false) {
        self.isLockdownModeEnabled = isLockdownModeEnabled
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    /// Detects Lockdown Mode status in the detectable object and triggers sheet presentation if needed.
    ///
    /// - Parameter detectable: The object to check for Lockdown Mode status.
    public func detectLockdownMode(for detectable: LockdownModeDetectable) {
        Logger.navigation.debug("Detecting Lockdown Mode")

        // Store weak reference to detectable object for later use (foreground reloads)
        self.detectable = detectable

        let wasEnabled = self.isLockdownModeEnabled
        self.isLockdownModeEnabled = detectable.isLockdownModeEnabled

        // Handle transition from disabled to enabled: show sheet
        if self.isLockdownModeEnabled && !wasEnabled && !hasShownSheet {
            shouldShowSheet = true
        }

        // Handle transition from enabled to disabled: clear sheet state
        // This happens when user excludes app from Lockdown Mode
        if !self.isLockdownModeEnabled && wasEnabled {
            hasShownSheet = false
            shouldShowSheet = false
        }
    }

    /// Resets the monitor state to re-check Lockdown Mode status.
    ///
    /// Call this when the app returns from background to re-evaluate Lockdown Mode
    /// and potentially show the sheet again if it's still enabled.
    public func resetForForegroundCheck() {
        hasShownSheet = false
    }
}

#if canImport(UIKit)
extension LockdownModeMonitor {

    /// Sets up the monitor with required dependencies and starts observing foreground notifications.
    ///
    /// - Parameter viewController: The view controller to use for sheet presentation.
    public func setup(presentingViewController viewController: UIViewController) {
        self.presentingViewController = viewController

        // Observe foreground notifications to re-check Lockdown Mode
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
    }

    @objc private func handleWillEnterForeground() {
        guard let detectable else { return }

        let newValue = detectable.isLockdownModeEnabled
        guard newValue != self.isLockdownModeEnabled else { return }

        Logger.navigation.debug("Lockdown Mode changed on foreground: \(newValue)")

        // Re-run detection to update state and trigger sheet if needed
        resetForForegroundCheck()
        detectLockdownMode(for: detectable)

        if shouldShowSheet {
            presentSheetIfNeeded(onDismiss: {})
        } else {
            // Lockdown Mode was disabled — dismiss the sheet if showing
            dismissSheetIfPresented()
        }
    }

    /// Presents the Lockdown Mode warning sheet if needed.
    ///
    /// - Parameters:
    ///   - onDismiss: Callback invoked when the user dismisses the sheet.
    /// - Returns: `true` if the sheet was presented, `false` otherwise.
    @discardableResult
    public func presentSheetIfNeeded(onDismiss: @escaping () -> Void) -> Bool {
        guard shouldShowSheet, let presentingViewController else {
            return false
        }

        hasShownSheet = true
        shouldShowSheet = false

        let sheetView = LockdownModeSheet(
            onDismiss: { [weak presentingViewController] in
                guard let presentingViewController else { return }
                presentingViewController.dismiss(animated: true) {
                    onDismiss()
                }
            },
            onLearnMore: {
                // Open support article directly to the exclusion section using text fragment
                if let url = URL(string: "https://support.apple.com/en-us/105120#:~:text=How%20to%20exclude%20apps%20or%20websites%20from%20Lockdown%20Mode") {
                    UIApplication.shared.open(url)
                }
            }
        )

        let hostingController = UIHostingController(rootView: sheetView)
        hostingController.modalPresentationStyle = .pageSheet
        hostingController.isModalInPresentation = true

        if let sheet = hostingController.sheetPresentationController {
            sheet.detents = [.large()]
            sheet.prefersGrabberVisible = false
        }

        presentingViewController.present(hostingController, animated: true)
        return true
    }

    /// Dismisses the sheet if it's currently presented.
    ///
    /// - Parameter completion: Optional callback invoked after dismissal completes.
    public func dismissSheetIfPresented(completion: (() -> Void)? = nil) {
        guard let presentingViewController, presentingViewController.presentedViewController != nil else {
            completion?()
            return
        }

        presentingViewController.dismiss(animated: false, completion: completion)
    }
}
#endif
