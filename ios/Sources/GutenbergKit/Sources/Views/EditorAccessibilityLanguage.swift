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

    func makeUIView(context: Context) -> UIView {
        UIView()
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        uiView.rootHostingView?.accessibilityLanguage = language
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
