import SwiftUI

struct CardModifier: ViewModifier {
    let cornerRadius: CGFloat

    // - warning: It was previously using .overlay, but it turned out to be
    // incompatible with inline PhotosPicker – breaks gestures on a device.
    func body(content: Content) -> some View {
        content
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
}

extension View {
    func cardStyle(cornerRadius: CGFloat = 26) -> some View {
        modifier(CardModifier(cornerRadius: cornerRadius))
    }
 }
