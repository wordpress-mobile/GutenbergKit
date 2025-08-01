import SwiftUI

struct BlockInserterItemView: View {
    let blockType: EditorBlockType
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                iconView
                titleView
                    .padding(.horizontal, 4)
            }
            .foregroundStyle(Color.primary)
        }
        .buttonStyle(.plain)
    }
    
    private var iconView: some View {
        BlockIconView(blockType: blockType, size: 44)
    }
    
    private var titleView: some View {
        Text(blockTitle)
            .font(.caption)
            .lineLimit(2, reservesSpace: true)
            .multilineTextAlignment(.center)
    }
    
    private var blockTitle: String {
        blockType.title ?? blockType.name
            .split(separator: "/")
            .last
            .map(String.init) ?? "Block"
    }
}

struct BlockIconView: View {
    let blockType: EditorBlockType
    let size: CGFloat

    var body: some View {
        ZStack {
            // Background
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(uiColor: .secondarySystemFill))
                .frame(width: size, height: size)

            // Icon
            Image(systemName: blockType.iconName)
                .font(.system(size: size * 0.5))
                .foregroundColor(.primary)
        }
    }
}
