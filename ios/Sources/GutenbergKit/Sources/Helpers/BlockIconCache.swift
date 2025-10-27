import Foundation
import SVGView

@MainActor
final class BlockIconCache: ObservableObject {
    var icons: [String: Result<SVGNode, Error>] = [:]

    func getIcon(for block: BlockType) -> SVGNode? {
        if let result = icons[block.id] {
            return try? result.get()
        }
        let result = Result { try _getIcon(for: block) }
        icons[block.id] = result
        return try? result.get()
    }

    private func _getIcon(for block: BlockType) throws -> SVGNode {
        guard let svg = block.icon, !svg.isEmpty else {
            throw BlockIconCacheError.unknown
        }
        guard let image = SVGParser.parse(string: svg) else {
#if DEBUG
            debugPrint("failed to parse SVG for block: \(block.name), svg: \(svg)")
#endif
            throw BlockIconCacheError.unknown
        }
        return image
    }
}

private enum BlockIconCacheError: Error {
    case unknown
}
