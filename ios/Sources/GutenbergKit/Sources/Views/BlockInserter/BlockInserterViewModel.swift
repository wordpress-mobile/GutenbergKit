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
        var currentSection: BlockInserterSection?

        // Blocks are already ordered and have section metadata from JS
        // Simply iterate and create sections when the category changes
        for block in blocks {
            let category = block.sectionCategory ?? block.category?.lowercased() ?? "common"
            let sectionName = block.sectionName

            // Check if we need to start a new section
            if let current = currentSection, current.category == category {
                // Add block to current section
                var updatedBlocks = current.blocks
                updatedBlocks.append(block)
                currentSection = BlockInserterSection(
                    category: current.category,
                    name: current.name,
                    blocks: updatedBlocks
                )
            } else {
                // Save previous section if it exists
                if let current = currentSection {
                    sections.append(current)
                }
                // Start new section
                currentSection = BlockInserterSection(
                    category: category,
                    name: sectionName,
                    blocks: [block]
                )
            }
        }

        // Add the last section
        if let current = currentSection {
            sections.append(current)
        }

        return sections
    }
}
