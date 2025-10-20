import Foundation
import SVGKit

@MainActor
final class BlockIconCache: ObservableObject {
    var icons: [String: Result<SVGKImage, Error>] = [:]

    func getIcon(for block: EditorBlock) -> SVGKImage? {
        if let result = icons[block.id] {
            return try? result.get()
        }
        let result = Result { try _getIcon(for: block) }
        icons[block.id] = result
        return try? result.get()
    }

    private func _getIcon(for block: EditorBlock) throws -> SVGKImage {
        guard let svg = block.icon,
              !svg.isEmpty,
              let source = SVGKSourceString.source(fromContentsOf: svg),
              let image = SVGKImage(source: source) else {
            throw BlockIconCacheError.unknown
        }
        if let result = image.parseErrorsAndWarnings,
           let error = result.errorsFatal.firstObject {
#if DEBUG
            debugPrint("failed to parse SVG for block: \(block.name) with errors: \(String(describing: result.errorsFatal))")
#endif
            throw (error as? Error) ?? BlockIconCacheError.unknown
        }
        return image
    }
}

private enum BlockIconCacheError: Error {
    case unknown
}
