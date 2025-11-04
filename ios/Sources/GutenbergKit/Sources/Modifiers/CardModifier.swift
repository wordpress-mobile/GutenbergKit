import SwiftUI

struct CardModifier: ViewModifier {
    // - warning: It was previously using .overlay, but it turned out to be
    // incompatible with inline PhotosPicker – breaks gestures on a device.
    func body(content: Content) -> some View {
        content
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 26))
    }
}

extension View {
    func cardStyle() -> some View {
        modifier(CardModifier())
    }
 }
