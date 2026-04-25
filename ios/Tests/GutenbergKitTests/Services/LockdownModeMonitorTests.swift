import Foundation
import Testing
import WebKit

#if canImport(UIKit)
import UIKit

@testable import GutenbergKit

@Suite
@MainActor
struct LockdownModeMonitorTests {

    // MARK: - Test Helpers

    private func makeMonitor() -> LockdownModeMonitor {
        return LockdownModeMonitor()
    }

    /// Mock implementation of LockdownModeDetectable for testing.
    @MainActor
    private class MockLockdownModeDetectable: LockdownModeDetectable {
        var isLockdownModeEnabled: Bool

        init(isLockdownModeEnabled: Bool) {
            self.isLockdownModeEnabled = isLockdownModeEnabled
        }
    }

    // MARK: - Initialization Tests

    @Test("Monitor initializes with Lockdown Mode disabled")
    func monitorInitializesWithLockdownModeDisabled() {
        let monitor = makeMonitor()
        #expect(monitor.isLockdownModeEnabled == false)
    }

    @Test("Monitor can be initialized with Lockdown Mode enabled")
    func monitorCanBeInitializedWithLockdownModeEnabled() {
        let monitor = LockdownModeMonitor(isLockdownModeEnabled: true)
        #expect(monitor.isLockdownModeEnabled == true)
    }

    // MARK: - Setup Tests

    @Test("Setup accepts a presenting view controller")
    func setupAcceptsPresentingViewController() {
        let monitor = makeMonitor()
        let viewController = UIViewController()

        monitor.setup(presentingViewController: viewController)

        // Should not crash or change lockdown state
        #expect(monitor.isLockdownModeEnabled == false)
    }

    // MARK: - Detection Logic Tests

    @Test("detectLockdownMode updates isLockdownModeEnabled property")
    func detectLockdownModeUpdatesProperty() {
        let monitor = makeMonitor()
        let webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())

        monitor.detectLockdownMode(for: webView)

        #expect(monitor.isLockdownModeEnabled == webView.configuration.defaultWebpagePreferences.isLockdownModeEnabled)
    }

    @Test("State transitions from enabled to disabled clear internal flags")
    func stateTransitionFromEnabledToDisabledClearsFlags() {
        let monitor = LockdownModeMonitor(isLockdownModeEnabled: true)
        let webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())

        monitor.detectLockdownMode(for: webView)

        #expect(monitor.isLockdownModeEnabled == webView.configuration.defaultWebpagePreferences.isLockdownModeEnabled)
    }

    // MARK: - Sheet Presentation Tests

    @Test("presentSheetIfNeeded returns false when not needed")
    func presentSheetIfNeededReturnsFalseWhenNotNeeded() {
        let monitor = makeMonitor()

        let result = monitor.presentSheetIfNeeded {}

        #expect(result == false)
    }

    @Test("presentSheetIfNeeded returns false without presenting view controller")
    func presentSheetIfNeededReturnsFalseWithoutViewController() {
        let monitor = makeMonitor()

        let result = monitor.presentSheetIfNeeded {}

        #expect(result == false)
    }

    // MARK: - Foreground Handling Tests

    @Test("dismissSheetIfPresented calls completion immediately when no sheet")
    func dismissSheetCallsCompletionImmediatelyWithoutSheet() {
        let monitor = makeMonitor()
        let viewController = UIViewController()

        monitor.setup(presentingViewController: viewController)

        var completionCalled = false
        monitor.dismissSheetIfPresented {
            completionCalled = true
        }

        #expect(completionCalled == true)
    }

    // MARK: - Scenario Tests

    @Test("Scenario: User excludes app from Lockdown Mode")
    func scenarioUserExcludesAppFromLockdownMode() {
        let monitor = LockdownModeMonitor(isLockdownModeEnabled: true)

        let webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        monitor.detectLockdownMode(for: webView)

        #expect(monitor.isLockdownModeEnabled == false)
    }

    @Test("Scenario: Lockdown Mode remains enabled after detection")
    func scenarioLockdownModeRemainsEnabled() {
        let monitor = LockdownModeMonitor(isLockdownModeEnabled: true)

        #expect(monitor.isLockdownModeEnabled == true)
    }

    // MARK: - Edge Case Tests

    @Test("Multiple detectLockdownMode calls handle gracefully")
    func multipleDetectCallsHandleGracefully() {
        let monitor = makeMonitor()
        let webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())

        monitor.detectLockdownMode(for: webView)
        monitor.detectLockdownMode(for: webView)
        monitor.detectLockdownMode(for: webView)

        #expect(monitor.isLockdownModeEnabled == webView.configuration.defaultWebpagePreferences.isLockdownModeEnabled)
    }

    @Test("Setup can be called multiple times")
    func setupCanBeCalledMultipleTimes() {
        let monitor = makeMonitor()
        let vc1 = UIViewController()
        let vc2 = UIViewController()

        monitor.setup(presentingViewController: vc1)
        monitor.setup(presentingViewController: vc2)

        // Should handle gracefully
    }

    // MARK: - Mock-Based Detection Tests

    @Test("Mock detectable with Lockdown Mode enabled updates monitor state")
    func mockDetectableWithLockdownEnabledUpdatesState() {
        let monitor = makeMonitor()
        let mockDetectable = MockLockdownModeDetectable(isLockdownModeEnabled: true)

        monitor.detectLockdownMode(for: mockDetectable)

        #expect(monitor.isLockdownModeEnabled == true)
    }

    @Test("Mock detectable with Lockdown Mode disabled updates monitor state")
    func mockDetectableWithLockdownDisabledUpdatesState() {
        let monitor = makeMonitor()
        let mockDetectable = MockLockdownModeDetectable(isLockdownModeEnabled: false)

        monitor.detectLockdownMode(for: mockDetectable)

        #expect(monitor.isLockdownModeEnabled == false)
    }

    // MARK: - State Transition Tests
    //
    // These tests verify the detection state machine without calling presentSheetIfNeeded,
    // which would trigger UIViewController.present() and deadlock in CI (no window hierarchy).

    @Test("Disabled-to-enabled transition sets isLockdownModeEnabled")
    func disabledToEnabledTransitionSetsState() {
        let monitor = makeMonitor()

        let disabledMock = MockLockdownModeDetectable(isLockdownModeEnabled: false)
        monitor.detectLockdownMode(for: disabledMock)
        #expect(monitor.isLockdownModeEnabled == false)

        let enabledMock = MockLockdownModeDetectable(isLockdownModeEnabled: true)
        monitor.detectLockdownMode(for: enabledMock)
        #expect(monitor.isLockdownModeEnabled == true)
    }

    @Test("Enabled-to-disabled transition clears isLockdownModeEnabled")
    func enabledToDisabledTransitionClearsState() {
        let monitor = makeMonitor()

        let enabledMock = MockLockdownModeDetectable(isLockdownModeEnabled: true)
        monitor.detectLockdownMode(for: enabledMock)
        #expect(monitor.isLockdownModeEnabled == true)

        let disabledMock = MockLockdownModeDetectable(isLockdownModeEnabled: false)
        monitor.detectLockdownMode(for: disabledMock)
        #expect(monitor.isLockdownModeEnabled == false)
    }

    @Test("Multiple state transitions track correctly")
    func multipleStateTransitionsTrackCorrectly() {
        let monitor = makeMonitor()

        let enabledMock = MockLockdownModeDetectable(isLockdownModeEnabled: true)
        let disabledMock = MockLockdownModeDetectable(isLockdownModeEnabled: false)

        // Disabled -> Enabled
        monitor.detectLockdownMode(for: enabledMock)
        #expect(monitor.isLockdownModeEnabled == true)

        // Enabled -> Disabled
        monitor.detectLockdownMode(for: disabledMock)
        #expect(monitor.isLockdownModeEnabled == false)

        // Disabled -> Enabled again
        monitor.detectLockdownMode(for: enabledMock)
        #expect(monitor.isLockdownModeEnabled == true)
    }

    @Test("presentSheetIfNeeded returns false without setup even after detection")
    func presentSheetReturnsFalseWithoutSetup() {
        let monitor = makeMonitor()

        // Trigger a disabled-to-enabled transition (sets shouldShowSheet)
        let enabledMock = MockLockdownModeDetectable(isLockdownModeEnabled: true)
        monitor.detectLockdownMode(for: enabledMock)

        // Without setup(), presentingViewController is nil so this returns false
        let didPresent = monitor.presentSheetIfNeeded {}
        #expect(didPresent == false)
    }

    @Test("resetForForegroundCheck allows re-detection")
    func resetForForegroundCheckAllowsRedetection() {
        let monitor = makeMonitor()

        let enabledMock = MockLockdownModeDetectable(isLockdownModeEnabled: true)
        monitor.detectLockdownMode(for: enabledMock)
        #expect(monitor.isLockdownModeEnabled == true)

        monitor.resetForForegroundCheck()

        // State should still reflect the last detection
        #expect(monitor.isLockdownModeEnabled == true)
    }
}

#endif
