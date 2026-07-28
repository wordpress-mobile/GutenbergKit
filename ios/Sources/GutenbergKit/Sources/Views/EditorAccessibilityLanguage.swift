#if canImport(UIKit)
import UIKit
import SwiftUI

extension View {
    /// Declares the editor's language for this view's accessibility tree, so
    /// assistive technology selects a matching speech voice.
    ///
    /// Apply at every presentation boundary. `accessibilityLanguage` is
    /// inherited down a view hierarchy, but a sheet is presented as a sibling
    /// rather than a descendant, so its content does not inherit the value set
    /// on the presenting view. The locale comes from the SwiftUI environment,
    /// which *does* cross sheets.
    ///
    /// - Note: Content rendered out of process — the system photo picker — has
    ///   its own accessibility tree and cannot be annotated from here.
    func editorAccessibilityLanguage() -> some View {
        modifier(EditorAccessibilityLanguageModifier())
    }
}

private struct EditorAccessibilityLanguageModifier: ViewModifier {
    @Environment(\.locale) private var locale

    func body(content: Content) -> some View {
        content.background(
            AccessibilityLanguageHost(language: locale.identifier)
                .accessibilityHidden(true)
        )
    }
}

/// Applies `accessibilityLanguage` to the UIKit view hosting this content.
///
/// SwiftUI has no equivalent modifier — the property exists only on `UIView`
/// and `UIAccessibilityElement`.
private struct AccessibilityLanguageHost: UIViewRepresentable {
    let language: String

    func makeUIView(context: Context) -> AccessibilityLanguageView {
        AccessibilityLanguageView()
    }

    func updateUIView(_ uiView: AccessibilityLanguageView, context: Context) {
        uiView.language = language
    }
}

/// Applies the language once the view is in a hierarchy.
///
/// `updateUIView` runs before this view is necessarily attached to a superview,
/// and with no superview the walk up the responder chain finds no hosting
/// controller. Because the language does not change afterward, SwiftUI has no
/// reason to call `updateUIView` again, so a miss there would be permanent.
/// Re-applying on move to a window retries once the hierarchy exists.
private final class AccessibilityLanguageView: UIView {
    var language: String? {
        didSet { applyLanguage() }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        applyLanguage()
    }

    private func applyLanguage() {
        guard let language else { return }
        rootHostingView?.accessibilityLanguage = language
    }
}

private extension UIView {
    /// The outermost view of the hosting controller presenting this view.
    var rootHostingView: UIView? {
        var candidate: UIView? = self
        while let view = candidate {
            if let controller = view.next as? UIViewController {
                return controller.view
            }
            candidate = view.superview
        }
        return nil
    }
}
#endif
