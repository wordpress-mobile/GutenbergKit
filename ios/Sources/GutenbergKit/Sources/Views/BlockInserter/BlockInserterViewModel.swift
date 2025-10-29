import SwiftUI
import PhotosUI
import Combine

@MainActor
class BlockInserterViewModel: ObservableObject {
    @Published var searchText = ""
    @Published private(set) var sections: [BlockInserterSection] = []

    private let blocks: [BlockType]
    private let allSections: [BlockInserterSection]
    private var cancellables = Set<AnyCancellable>()

    init(blocks: [BlockType], destinationBlockName: String?) {
        self.blocks = blocks

        self.allSections = BlockInserterViewModel.createSections(from: blocks, destinationBlockName: destinationBlockName)
        self.sections = allSections

        setupSearchObserver()
    }
    
    private func setupSearchObserver() {
        $searchText
            .debounce(for: .milliseconds(200), scheduler: RunLoop.main)
            .sink { [weak self] searchText in
                self?.updateFilteredSections(searchText: searchText)
            }
            .store(in: &cancellables)
    }

    private func updateFilteredSections(searchText: String) {
        if searchText.isEmpty {
            sections = allSections
        } else {
            sections = allSections.compactMap { section in
                let filtered = SearchEngine<BlockType>()
                    .search(query: searchText, in: section.blocks)
                return filtered.isEmpty ? nil : BlockInserterSection(
                    category: section.category,
                    name: section.name,
                    blocks: filtered
                )
            }
        }
    }

    private static func createSections(from blocks: [BlockType], destinationBlockName: String?) -> [BlockInserterSection] {
        var sections: [BlockInserterSection] = []

        // Separate contextual blocks (specifically allowed in current parent block)
        // A block is contextual if the destination block name is in its parents array
        let contextualBlocks = blocks.filter { block in
            guard let destinationBlockName = destinationBlockName else { return false }
            return !block.parents.isEmpty && block.parents.contains(destinationBlockName)
        }
 
        // Add contextual section at the top if there are contextual blocks
        if !contextualBlocks.isEmpty {
            sections.append(BlockInserterSection(category: "gbk-contextual", name: nil, blocks: contextualBlocks))
        }

        // Group regular blocks by category
        let blocksByCategory = Dictionary(grouping: blocks) {
            $0.category?.lowercased() ?? "common"
        }

        let categories = Constants.orderedCategories

        // Add known categories in a predefined order
        for (category, name) in categories {
            if let blocks = blocksByCategory[category] {
                let sortedBlocks = orderBlocks(blocks, category: category)
                // Use nil for text category, otherwise use the display name
                let displayName = (category == "text" && contextualBlocks.isEmpty) ? nil : name
                sections.append(BlockInserterSection(category: category, name: displayName, blocks: sortedBlocks))
            }
        }

        // Add any remaining categories
        for (category, blocks) in blocksByCategory {
            let isStandardCategory = categories.contains { $0.key == category }
            if !isStandardCategory {
                sections.append(BlockInserterSection(category: category, name: category.capitalized, blocks: blocks))
            }
        }

        return sections
    }
}

// MARK: Ordering

private func orderBlocks(_ blocks: [BlockType], category: String) -> [BlockType] {
    switch category {
    case "text":
        return _orderBlocks(blocks, order: [
            "core/paragraph",
            "core/heading",
            "core/list",
            "core/list-item",
            "core/quote",
            "core/code",
            "core/preformatted",
            "core/verse",
            "core/table"
        ])
    case "media":
        return _orderBlocks(blocks, order: [
            "core/image",
            "core/video",
            "core/gallery",
            "core/embed",
            "core/audio",
            "core/file"
        ])
    case "design":
        return _orderBlocks(blocks, order: [
            "core/separator",
            "core/spacer",
            "core/columns",
            "core/column"
        ])
    default:
        return blocks
    }
}

private func _orderBlocks(_ blocks: [BlockType], order: [String]) -> [BlockType] {
    var orderedBlocks: [BlockType] = []

    // Add blocks in a predefined order
    for name in order {
        if let block = blocks.first(where: { $0.name == name }) {
            orderedBlocks.append(block)
        }
    }

    // Add remaining blocks in their original order
    let remainingBlocks = blocks.filter { block in
        !order.contains(block.name)
    }

    return orderedBlocks + remainingBlocks
}

private enum Constants {
    static let orderedCategories: [(key: String, displayName: String)] = [
        ("text", "Text"),
        ("media", "Media"),
        ("design", "Design"),
        ("widgets", "Widgets"),
        ("theme", "Theme"),
        ("embed", "Embeds")
    ]
}
