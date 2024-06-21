import Foundation

final class EditorBlock: Decodable {
    /// The name of the block, e.g. `core/paragraph`.
    var name: String
    /// The attributes of the block.
    var attributes: [String: AnyDecodable]
    /// The nested blocks.
    var innerBlocks: [EditorBlock]
}
