import SwiftUI
import SVGKit

struct BlockIconView: View {
    let block: EditorBlock
    let size: CGFloat

    @EnvironmentObject private var cache: BlockIconCache

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(uiColor: .secondarySystemFill))
                .frame(width: size, height: size)
                .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)

            if let image = cache.getIcon(for: block),
               let view = SVGKFastImageView(svgkImage: image) {
                SVGIconView(view: view)
                    .frame(width: size * 0.5, height: size * 0.5)
            } else {
                Image(systemName: "square")
                    .font(.system(size: size * 0.5))
                    .foregroundStyle(Color.black)
                    .symbolRenderingMode(.hierarchical)
            }
        }
    }
}

private struct SVGIconView: UIViewRepresentable {
    let view: SVGKFastImageView

    func makeUIView(context: Context) -> SVGKFastImageView {
        view.contentMode = .scaleAspectFit
        view.tintColor = .red
        return view
    }

    func updateUIView(_ uiView: SVGKFastImageView, context: Context) {
        // No special handling needed - SVGKit will render as-is
    }
}
