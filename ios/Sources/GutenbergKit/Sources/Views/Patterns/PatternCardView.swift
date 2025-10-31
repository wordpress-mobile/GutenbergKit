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
            switch style {
            case .horizontal(let height, let maxWidth):
                HTMLPreviewView(pattern: pattern, targetSize: CGSize(width: maxWidth, height: height))
                    .frame(minWidth: 120, maxWidth: maxWidth, minHeight: height, maxHeight: height)
                    .cardStyle(cornerRadius: 10)
            case .fullWidth(let maxHeight):
                HTMLPreviewView(pattern: pattern, targetSize: nil)
                    .frame(minWidth: 200, maxWidth: .infinity, minHeight: 150, maxHeight: maxHeight)
                    .cardStyle(cornerRadius: 14)
            }
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

private struct PatternDetailedView: View {
    let pattern: Pattern
    let onSelected: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Large preview
            HTMLPreviewView(pattern: pattern, targetSize: CGSize(width: 400, height: 300))
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
