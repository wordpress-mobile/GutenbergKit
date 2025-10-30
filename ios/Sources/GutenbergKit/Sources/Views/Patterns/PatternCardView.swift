import SwiftUI

/// A simple card view showing only the pattern preview image
struct PatternCardView: View {
    let pattern: PatternType
    let onSelected: () -> Void
    let style: Style

    enum Style {
        case horizontal(height: CGFloat)
        case fullWidth
    }

    var body: some View {
        Button(action: onSelected) {
            BlockPreviewView(pattern: pattern)
                .frame(maxWidth: style.maxWidth, maxHeight: style.maxHeight)
                .background(Color(uiColor: .systemBackground))
                .cornerRadius(12)
                .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
        }
        .buttonStyle(.plain)
    }
}

private extension PatternCardView.Style {
    var maxWidth: CGFloat? {
        switch self {
        case .horizontal:
            return nil // Let aspect ratio determine width
        case .fullWidth:
            return .infinity
        }
    }

    var maxHeight: CGFloat? {
        switch self {
        case .horizontal(let height):
            return height
        case .fullWidth:
            return nil // Let aspect ratio determine height
        }
    }
}
