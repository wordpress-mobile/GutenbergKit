import SwiftUI
import PhotosUI
import Combine

@MainActor
class BlockInserterViewModel: ObservableObject {
    @Published var searchText = ""
    @Published private(set) var sections: [BlockInserterSection] = []

    private let blocks: [EditorBlock]
    private let allSections: [BlockInserterSection]
    private var cancellables = Set<AnyCancellable>()

    init(blocks: [EditorBlock]) {
        let blocks = blocks.filter { $0.name != "core/missing" }

        self.blocks = blocks

        self.allSections = BlockInserterViewModel.createSections(from: blocks)
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
                let filtered = SearchEngine<EditorBlock>()
                    .search(query: searchText, in: section.blocks)
                return filtered.isEmpty ? nil : BlockInserterSection(
                    category: section.category,
                    name: section.name,
                    blocks: filtered
                )
            }
        }
    }

    private static func createSections(from blocks: [EditorBlock]) -> [BlockInserterSection] {
        let blocks = Dictionary(grouping: blocks) {
            $0.category?.lowercased() ?? "common"
        }

        var sections: [BlockInserterSection] = []

        let categories = Constants.orderedCategories

        // Add known categories in a predefined order
        for (category, name) in categories {
            if let blocks = blocks[category] {
                let sortedBlocks = orderBlocks(blocks, category: category)
                sections.append(BlockInserterSection(category: category, name: name, blocks: sortedBlocks))
            }
        }
        
        // Add any remaining categories
        for (category, blocks) in blocks {
            let isStandardCategory = categories.contains { $0.key == category }
            if !isStandardCategory {
                sections.append(BlockInserterSection(category: category, name: category.capitalized, blocks: blocks))
            }
        }
        
        return sections
    }
}

// MARK: Ordering

private func orderBlocks(_ blocks: [EditorBlock], category: String) -> [EditorBlock] {
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

private func _orderBlocks(_ blocks: [EditorBlock], order: [String]) -> [EditorBlock] {
    var orderedBlocks: [EditorBlock] = []

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
