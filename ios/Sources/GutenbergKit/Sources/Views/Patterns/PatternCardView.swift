import SwiftUI

/// A simple card view showing only the pattern preview image
struct PatternCardView: View {
    let pattern: PatternType
    let onSelected: () -> Void
    let style: Style

    enum Style {
        case horizontal(height: CGFloat, maxWidth: CGFloat)
        case fullWidth(maxHeight: CGFloat)
    }

    var body: some View {
        Button(action: onSelected) {
            BlockPreviewView(pattern: pattern)
                .frame(
                    minWidth: style.minWidth,
                    maxWidth: style.maxWidth,
                    minHeight: style.minHeight,
                    maxHeight: style.maxHeight
                )
                .background(Color(uiColor: .white))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color(uiColor: .opaqueSeparator), lineWidth: 0.5)
                )
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}

private extension PatternCardView.Style {
    var minWidth: CGFloat? {
        switch self {
        case .horizontal:
            return 120
        case .fullWidth:
            return 200
        }
    }

    var maxWidth: CGFloat? {
        switch self {
        case .horizontal(_, let maxWidth):
            return maxWidth
        case .fullWidth:
            return .infinity
        }
    }

    var minHeight: CGFloat? {
        switch self {
        case .horizontal(let height, _):
            return height
        case .fullWidth:
            return 150
        }
    }

    var maxHeight: CGFloat? {
        switch self {
        case .horizontal(let height, _):
            return height
        case .fullWidth(let maxHeight):
            return maxHeight
        }
    }
}
