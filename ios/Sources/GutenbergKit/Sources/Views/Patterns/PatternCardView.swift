import SwiftUI

/// A simple card view showing only the pattern preview image
struct PatternCardView: View {
    let pattern: PatternType
    let onSelected: () -> Void

    var body: some View {
        Button(action: onSelected) {
            BlockPreviewView(pattern: pattern)
                .frame(width: 160, height: 140)
                .background(Color(uiColor: .systemBackground))
                .cornerRadius(12)
                .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
        }
        .buttonStyle(.plain)
    }
}
