import SwiftUI
import PhotosUI
import Combine

@MainActor
class BlockInserterViewModel: ObservableObject {
    @Published var searchText = ""
    @Published private(set) var sections: [BlockInserterSection] = []

    private let allSections: [BlockInserterSection]
    private var cancellables = Set<AnyCancellable>()

    init(sections: [BlockInserterSection]) {
        self.allSections = sections
        self.sections = sections

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
}
