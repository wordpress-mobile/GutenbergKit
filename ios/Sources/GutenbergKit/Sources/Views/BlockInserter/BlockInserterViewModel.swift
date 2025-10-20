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
                let filtered = filterBlocks(in: section, searchText: searchText)
                return filtered.isEmpty ? nil : BlockInserterSection(
                    category: section.category,
                    name: section.name,
                    blocks: filtered
                )
            }
        }
    }
    
    private func filterBlocks(in section: BlockInserterSection, searchText: String) -> [EditorBlock] {
        let searchEngine = SearchEngine<EditorBlock>()
        let filtered = searchEngine.search(query: searchText, in: section.blocks)
        
        // Maintain paragraph first in text category when showing all blocks
        if searchText.isEmpty && section.name == "Text" && filtered.count > 1 {
            return sortTextBlocks(filtered)
        }
        
        return filtered
    }
    
    private func sortTextBlocks(_ blocks: [EditorBlock]) -> [EditorBlock] {
        let paragraphBlocks = blocks.filter { $0.name == "core/paragraph" }
        let otherBlocks = blocks.filter { $0.name != "core/paragraph" }
        return paragraphBlocks + otherBlocks
    }
    
    private static func createSections(from blockTypes: [EditorBlock]) -> [BlockInserterSection] {
        let categoryOrder = BlockInserterConstants.categoryOrder
        var grouped = Dictionary(grouping: blockTypes) { $0.category?.lowercased() ?? "common" }
        
        // Move core/embed from embed category to media category
        if let embedBlocks = grouped["embed"],
           let embedBlock = embedBlocks.first(where: { $0.name == "core/embed" }) {
            // Add to media category
            if var mediaBlocks = grouped["media"] {
                mediaBlocks.append(embedBlock)
                grouped["media"] = mediaBlocks
            } else {
                grouped["media"] = [embedBlock]
            }
            
            // Remove from embed category
            grouped["embed"] = embedBlocks.filter { $0.name != "core/embed" }
            if grouped["embed"]?.isEmpty == true {
                grouped.removeValue(forKey: "embed")
            }
        }
        
        var sections: [BlockInserterSection] = []
        
        // Add sections in WordPress standard order
        for (categoryKey, displayName) in categoryOrder {
            if let blocks = grouped[categoryKey] {
                let sortedBlocks = sortBlocks(blocks, category: categoryKey)
                sections.append(BlockInserterSection(category: categoryKey, name: displayName, blocks: sortedBlocks))
            }
        }
        
        // Add any remaining categories
        for (category, blocks) in grouped {
            let isStandardCategory = categoryOrder.contains { $0.key == category }
            if !isStandardCategory {
                sections.append(BlockInserterSection(category: category, name: category.capitalized, blocks: blocks))
            }
        }
        
        return sections
    }
    
    private static func sortBlocks(_ blocks: [EditorBlock], category: String) -> [EditorBlock] {
        switch category {
        case "text":
            return sortWithOrder(blocks, order: BlockInserterConstants.textBlockOrder)
        case "media":
            return sortWithOrder(blocks, order: BlockInserterConstants.mediaBlockOrder)
        case "design":
            return sortWithOrder(blocks, order: BlockInserterConstants.designBlockOrder)
        default:
            return blocks
        }
    }
    
    private static func sortWithOrder(_ blocks: [EditorBlock], order: [String]) -> [EditorBlock] {
        var orderedBlocks: [EditorBlock] = []
        
        // Add blocks in defined order
        for blockName in order {
            if let block = blocks.first(where: { $0.name == blockName }) {
                orderedBlocks.append(block)
            }
        }
        
        // Add remaining blocks in their original order
        let remainingBlocks = blocks.filter { block in
            !order.contains(block.name)
        }
        
        return orderedBlocks + remainingBlocks
    }
}

// MARK: - Constants

enum BlockInserterConstants {
    static let categoryOrder: [(key: String, displayName: String)] = [
        ("text", "Text"),
        ("media", "Media"),
        ("design", "Design"),
        ("widgets", "Widgets"),
        ("theme", "Theme"),
        ("embed", "Embeds")
    ]
    
    static let textBlockOrder = [
        "core/paragraph",
        "core/heading",
        "core/list",
        "core/list-item",
        "core/quote",
        "core/code",
        "core/preformatted",
        "core/verse",
        "core/table"
    ]
    
    static let mediaBlockOrder = [
        "core/image",
        "core/video",
        "core/gallery",
        "core/embed",
        "core/audio",
        "core/file"
    ]
    
    static let designBlockOrder = [
        "core/separator",
        "core/spacer",
        "core/columns",
        "core/column"
    ]
}

// MARK: - Supporting Types

struct BlockInserterSection: Identifiable {
    var id: String { category }
    let category: String
    let name: String
    let blocks: [EditorBlock]
}
