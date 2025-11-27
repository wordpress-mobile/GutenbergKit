import SwiftUI
internal import SVGView

struct BlockIconView: View {
    let block: BlockType
    let size: CGFloat

    @EnvironmentObject private var cache: BlockIconCache

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(uiColor: .secondarySystemFill))
                .frame(width: size, height: size)
                .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)

            if let image = cache.getIcon(for: block) {
                Color(.label).mask {
                    SVGView(svg: image)
                }
                .frame(width: size * 0.5, height: size * 0.5)
            } else {
                Image(systemName: "square")
                    .font(.system(size: size * 0.5))
                    .foregroundStyle(Color(.label))
                    .symbolRenderingMode(.hierarchical)
            }
        }
    }
}
