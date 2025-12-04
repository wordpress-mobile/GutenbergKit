import SwiftUI

struct BlockInserterBlockView: View {
    let block: BlockType
    let action: () -> Void
    
    @State private var isPressed = false
    @State private var isHovered = false

    @ScaledMetric(relativeTo: .largeTitle) private var iconSize = 44

    @EnvironmentObject private var iconCache: BlockIconCache

    var body: some View {
        Button(action: {
            onSelected()
        }) {
            VStack(spacing: 8) {
                BlockIconView(block: block, size: iconSize)
                Text(title)
                    .font(.caption)
                    .lineLimit(2, reservesSpace: true)
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(Color.primary)
            .scaleEffect(isPressed ? 0.9 : 1.0)
            .animation(.spring, value: isPressed)
            .padding(.horizontal, 4)
        }
        .buttonStyle(.plain)
        .disabled(block.isDisabled)
        .frame(maxWidth: .infinity, alignment: .center)
        .contextMenu {
            Button {
                onSelected()
            } label: {
                Label(EditorLocalization[.insertBlock], systemImage: "plus")
            }
        } preview: {
            BlockDetailedView(block: block)
                .environmentObject(iconCache)
        }
    }

    private func onSelected() {
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
        isPressed = true
        action()
    }

    private var title: String {
        block.title ?? block.name
            .split(separator: "/")
            .last
            .map(String.init) ?? "-"
    }
}

private struct BlockDetailedView: View {
    let block: BlockType

    var body: some View {
        HStack(spacing: 16) {
            BlockIconView(block: block, size: 56)

            VStack(alignment: .leading, spacing: 2) {
                if let title = block.title {
                    Text(title)
                        .font(.headline)
                        .foregroundColor(.primary)
                    Text(block.name)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                } else {
                    Text(block.name)
                        .font(.headline)
                        .foregroundColor(.primary)
                }

                if let description = block.description {
                    Text(description)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(4)
                        .padding(.top, 8)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .frame(width: 360)
        .background(Color(platformColor: .systemBackground))
    }
}
