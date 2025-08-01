import SwiftUI
import PhotosUI
import Combine
import UniformTypeIdentifiers

struct BlockInserterView: View {
    let blockTypes: [EditorBlockType]
    let onBlockSelected: (EditorBlockType) -> Void
    
    @StateObject private var viewModel: BlockInserterViewModel

    @State private var isShowingFilesPicker = false
    @State private var selectedMediaItems: [PhotosPickerItem] = []

    @Environment(\.dismiss) private var dismiss
    
    init(blockTypes: [EditorBlockType], 
         onBlockSelected: @escaping (EditorBlockType) -> Void) {
        let blockTypes = blockTypes.filter { $0.title != "Unsupported" }
        self.blockTypes = blockTypes.filter { $0.title != "Unsupported" }
        self.onBlockSelected = onBlockSelected
        self._viewModel = StateObject(wrappedValue: BlockInserterViewModel(blockTypes: blockTypes))
    }
    
    var body: some View {
        NavigationView {
            mainContent
                .background(Material.ultraThin)
                .scrollContentBackground(.hidden)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbarContent }
                .searchable(text: $viewModel.searchText)
                .fileImporter(
                    isPresented: $isShowingFilesPicker,
                    allowedContentTypes: [.text, .plainText, .pdf, .image],
                    allowsMultipleSelection: false,
                    onCompletion: handleFileImportResult
                )
        }
    }
    
    // MARK: - View Components
    
    private var mainContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ForEach(viewModel.filteredSections) { section in
                    BlockInserterSectionView(
                        section: section,
                        isSearching: !viewModel.searchText.isEmpty,
                        onBlockSelected: insertBlock,
                        onMediaSelected: insertMedia
                    )
                }
            }
            .padding(.vertical)
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
            }
            .tint(Color.primary)
        }
        ToolbarItemGroup(placement: .automatic) {
            mediaToolbarButtons
                .tint(Color.primary)
        }
    }
    
    @ViewBuilder
    private var mediaToolbarButtons: some View {
        PhotosPicker(selection: $selectedMediaItems) {
            Image(systemName: "photo.on.rectangle.angled")
        }
        .onChange(of: selectedMediaItems) {
            insertMedia($0)
            selectedMediaItems = []
        }

        Button(action: {
            // TODO: Implement camera
            print("Camera tapped")
        }) {
            Image(systemName: "camera")
        }

        Menu {
            Section {
                Button(action: {
                    // TODO: Implement Image Playground integration
                    print("Image Playground tapped")
                }) {
                    Label("Image Playground", systemImage: "apple.image.playground")
                }
                Button(action: { isShowingFilesPicker = true }) {
                    Label("Files", systemImage: "folder")
                }
            }

            Section {
                Button(action: {
                    // TODO: Implement Free Photos Library
                    print("Free Photos Library tapped")
                }) {
                    Label("Free Photos Library", systemImage: "photo.on.rectangle")
                }

                Button(action: {
                    // TODO: Implement Free GIF Library
                    print("Free GIF Library tapped")
                }) {
                    Label("Free GIF Library", systemImage: "photo.stack")
                }
            }


            Section {
                // Non-tappable footer showing library size
                Button(action: {}) {
                    HStack {
                        // TODO: pass this information to the editor
                        Text("10% of 2 TB used on your site")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                }
                .disabled(true)
            }

        } label: {
            Image(systemName: "ellipsis")
        }
    }

    // MARK: - File Import Handler
    
    private func handleFileImportResult(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            if let url = urls.first {
                handleFileSelection(url)
            }
        case .failure(let error):
            print("File selection error: \(error)")
        }
    }
    
    private func handleFileSelection(_ url: URL) {
        // TODO: Handle file selection
        print("Selected file: \(url.lastPathComponent)")
        dismiss()
    }
    
    private func insertBlock(_ blockType: EditorBlockType) {
        onBlockSelected(blockType)
        dismiss()
    }
    
    private func insertMedia(_ items: [PhotosPickerItem]) {
        // TODO: figure out how to allow the editor to access the files (WKWebView needs explicit access to the file system)
    }
    
    private func createImageBlock() -> EditorBlockType {
        EditorBlockType(
            name: "core/image",
            title: "Image",
            description: nil,
            category: "media",
            keywords: nil
        )
    }
    
    private func createVideoBlock() -> EditorBlockType {
        EditorBlockType(
            name: "core/video",
            title: "Video",
            description: nil,
            category: "media",
            keywords: nil
        )
    }
}

// MARK: - View Model

@MainActor
class BlockInserterViewModel: ObservableObject {
    @Published var searchText = ""
    @Published private(set) var filteredSections: [BlockInserterSection] = []
    
    private let blockTypes: [EditorBlockType]
    private let allSections: [BlockInserterSection]
    
    init(blockTypes: [EditorBlockType]) {
        let filteredBlockTypes = blockTypes.filter { $0.title != "Unsupported" }
        self.blockTypes = filteredBlockTypes

        self.allSections = BlockInserterViewModel.createSections(from: filteredBlockTypes)
        self.filteredSections = allSections

        setupSearchObserver()
    }
    
    private func setupSearchObserver() {
        $searchText
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] searchText in
                self?.updateFilteredSections(searchText: searchText)
            }
            .store(in: &cancellables)
    }
    
    private var cancellables = Set<AnyCancellable>()
    
    private func updateFilteredSections(searchText: String) {
        if searchText.isEmpty {
            filteredSections = allSections
        } else {
            filteredSections = allSections.compactMap { section in
                let filtered = filterBlocks(in: section, searchText: searchText)
                return filtered.isEmpty ? nil : BlockInserterSection(name: section.name, blockTypes: filtered)
            }
        }
    }
    
    private func filterBlocks(in section: BlockInserterSection, searchText: String) -> [EditorBlockType] {
        let searchEngine = SearchEngine<EditorBlockType>()
        let filtered = searchEngine.search(query: searchText, in: section.blockTypes)
        
        // Maintain paragraph first in text category when showing all blocks
        if searchText.isEmpty && section.name == "Text" && filtered.count > 1 {
            return sortTextBlocks(filtered)
        }
        
        return filtered
    }
    
    private func sortTextBlocks(_ blocks: [EditorBlockType]) -> [EditorBlockType] {
        let paragraphBlocks = blocks.filter { $0.name == "core/paragraph" }
        let otherBlocks = blocks.filter { $0.name != "core/paragraph" }
        return paragraphBlocks + otherBlocks
    }
    
    private static func createSections(from blockTypes: [EditorBlockType]) -> [BlockInserterSection] {
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
                sections.append(BlockInserterSection(name: displayName, blockTypes: sortedBlocks))
            }
        }
        
        // Add any remaining categories
        for (category, blocks) in grouped {
            let isStandardCategory = categoryOrder.contains { $0.key == category }
            if !isStandardCategory {
                sections.append(BlockInserterSection(name: category.capitalized, blockTypes: blocks))
            }
        }
        
        return sections
    }
    
    private static func sortBlocks(_ blocks: [EditorBlockType], category: String) -> [EditorBlockType] {
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
    
    private static func sortWithOrder(_ blocks: [EditorBlockType], order: [String]) -> [EditorBlockType] {
        var orderedBlocks: [EditorBlockType] = []
        
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

// MARK: - Extensions

// MARK: - Supporting Types

struct BlockInserterSection: Identifiable {
    var id: String { name }
    let name: String
    let blockTypes: [EditorBlockType]
}

// MARK: - Preview

import Combine

struct BlockInserterView_Previews: PreviewProvider {
    static var previews: some View {
        SheetPreviewContainer()
    }
}

struct SheetPreviewContainer: View {
    @State private var isShowingSheet = true

    var body: some View {
        Button("Show Block Inserter") {
            isShowingSheet = true
        }
        .popover(isPresented: $isShowingSheet) {
            BlockInserterView(
                blockTypes: PreviewData.sampleBlockTypes,
                onBlockSelected: { blockType in
                    print("Selected block: \(blockType.name)")
                }
            )
        }
    }
}
