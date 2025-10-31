import SwiftUI

/// A simple card view showing only the pattern preview image
struct PatternCardView: View {
    let pattern: Pattern
    let onSelected: () -> Void
    let style: Style

    enum Style {
        case horizontal(height: CGFloat, maxWidth: CGFloat)
        case fullWidth(maxHeight: CGFloat)
    }

    var body: some View {
        Button(action: onSelected) {
            BlockPreviewView(pattern: pattern, maximumDimension: style.maximumDimension)
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
        .contextMenu {
            Button {
                onSelected()
            } label: {
                // TODO: CMM-874 l10n
                Label("Insert Pattern", systemImage: "plus")
            }
        } preview: {
            PatternDetailedView(pattern: pattern, onSelected: onSelected)
        }
    }
}

private extension PatternCardView.Style {
    var maximumDimension: HTMLPreviewRenderer.MaximumDimension {
        switch self {
        case .horizontal(let height, _):
            // In horizontal scroll, constrain by height
            return .height(height)
        case .fullWidth:
            // In full-width list, constrain by width (use screen width)
            return .width(UIScreen.main.bounds.width - 32) // Account for padding
        }
    }

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

private struct PatternDetailedView: View {
    let pattern: Pattern
    let onSelected: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Large preview
            BlockPreviewView(pattern: pattern, maximumDimension: .width(400))
                .frame(maxWidth: .infinity)
                .frame(height: 300)
                .background(Color(uiColor: .white))
                .clipped()

            // Pattern information
            VStack(alignment: .leading, spacing: 20) {
                // Title and name
                VStack(alignment: .leading, spacing: 4) {
                    Text(pattern.title)
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)

                    Text(pattern.name)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                // Description
                if let description = pattern.description, !description.isEmpty {
                    Text(description)
                        .font(.body)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                // Source
                if let source = pattern.source, !source.isEmpty {
                    HStack(spacing: 4) {
                        Text("Source:")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                        Text(source)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(20)
        }
        .frame(width: 400)
        .background(Color(uiColor: .systemBackground))
    }
}
