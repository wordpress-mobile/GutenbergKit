import Foundation

public final class Block: Decodable {
    /// The name of the block, e.g. `core/paragraph`.
    public var name: String
    /// The attributes of the block.
    public var attributes: [String: AnyDecodable]
    /// The nested blocks.
    public var innerBlocks: [Block]
}
