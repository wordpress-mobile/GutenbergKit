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
                    .foregroundStyle(Color(.label))
                    .symbolRenderingMode(.hierarchical)
            }
        }
    }
}

private struct SVGIconView: UIViewRepresentable {
    let view: SVGKFastImageView

    @Environment(\.colorScheme) private var colorScheme

    func makeUIView(context: Context) -> SVGKFastImageView {
        view.contentMode = .scaleAspectFit
        return view
    }

    func updateUIView(_ uiView: SVGKFastImageView, context: Context) {
        view.image?.fillColor(color: UIColor.label)
        view.setNeedsDisplay()
    }
}

private extension SVGKImage {
    /// SVGKit maintains two parallel representations of every SVG file: a
    /// DOMTree following W3C SVG specifications and a CALayerTree for native
    /// iOS rendering. The easiest and fastest way to change the colors of the
    /// shapes it creates is by recursively traversing the layers.
    private func fillColorForSubLayer(layer: CALayer, color: UIColor, opacity: Float) {
        if let shapeLayer = layer as? CAShapeLayer {
            shapeLayer.fillColor = color.cgColor
            shapeLayer.opacity = opacity
        }
        if let sublayers = layer.sublayers {
            for subLayer in sublayers {
                fillColorForSubLayer(layer: subLayer, color: color, opacity: opacity)
            }
        }
    }

    func fillColor(color: UIColor, opacity: Float = 1.0) {
        if let layer = caLayerTree {
            fillColorForSubLayer(layer: layer, color: color, opacity: opacity)
        }
    }
}
