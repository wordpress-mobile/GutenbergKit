import SwiftUI
import PhotosUI
import UIKit
import WebKit

struct BlockInserterView: View {
    let sections: [BlockInserterSection]
    let mediaPicker: MediaPickerController?
    let presentationContext: MediaPickerPresentationContext
    let onBlockSelected: (BlockType) -> Void
    let onPatternSelected: (String) -> Void
    let onMediaSelected: ([MediaInfo]) -> Void
    let loadPatterns: () async throws -> [PatternType]

    @StateObject private var viewModel: BlockInserterViewModel
    @StateObject private var iconCache = BlockIconCache()

    @State private var selectedMediaItems: [PhotosPickerItem] = []

    private let maxSelectionCount = 10

    @Environment(\.dismiss) private var dismiss
    @State private var showingPatterns = false

    init(
        sections: [BlockInserterSection],
        mediaPicker: MediaPickerController?,
        presentationContext: MediaPickerPresentationContext,
        onBlockSelected: @escaping (BlockType) -> Void,
        onPatternSelected: @escaping (String) -> Void,
        onMediaSelected: @escaping ([MediaInfo]) -> Void,
        loadPatterns: @escaping () async throws -> [PatternType]
    ) {
        self.sections = sections
        self.mediaPicker = mediaPicker
        self.presentationContext = presentationContext
        self.onBlockSelected = onBlockSelected
        self.onPatternSelected = onPatternSelected
        self.onMediaSelected = onMediaSelected
        self.loadPatterns = loadPatterns

        let viewModel = BlockInserterViewModel(sections: sections)
        self._viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        content
            .background(Material.ultraThin)
            .searchable(text: $viewModel.searchText)
            .navigationBarTitleDisplayMode(.inline)
            .disabled(viewModel.isProcessingMedia)
            .animation(.smooth(duration: 2), value: viewModel.isProcessingMedia)
            .environmentObject(iconCache)
            .toolbar {
                toolbar
            }
            .onDisappear {
                if viewModel.isProcessingMedia {
                    viewModel.cancelProcessing()
                }
            }
            .sheet(isPresented: $showingPatterns) {
                NavigationStack {
                    PatternsView(
                        loadPatterns: loadPatterns,
                        onPatternSelected: { patternName in
                            showingPatterns = false
                            insertPattern(patternName)
                        }
                    )
                }
            }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ForEach(viewModel.sections) { section in
                    BlockInserterSectionView(section: section, onBlockSelected: insertBlock)
                        .padding(.horizontal)
                }
            }
            .padding(.vertical, 8)
            .dynamicTypeSize(...(.accessibility3))
        }
        .scrollContentBackground(.hidden)
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
            }
            .tint(Color.primary)
        }

        ToolbarItemGroup(placement: .topBarTrailing) {
            PhotosPicker(selection: $selectedMediaItems, preferredItemEncoding: .compatible) {
                Image(systemName: "photo.on.rectangle.angled")
            }
            .onChange(of: selectedMediaItems) { _, selection in
                if !selection.isEmpty {
                    insertMedia(selection)
                }
                selectedMediaItems = []
            }
            Button {
                showingPatterns = true
            } label: {
                Image(systemName: "square.grid.2x2")
            }
            .tint(Color.primary)

            if let mediaPicker {
                MediaPickerMenu(picker: mediaPicker, context: presentationContext) {
                    dismiss()
                    onMediaSelected($0)
                }
            }
        }
    }

    // MARK: - Actions

    private func insertBlock(_ block: BlockType) {
        dismiss()
        onBlockSelected(block)
    }

    private func insertMedia(_ items: [PhotosPickerItem]) {
        Task {
            let items = await viewModel.processSelectedPhotosPickerItems(items)
            if !items.isEmpty {
                dismiss()
                onMediaSelected(items)
            }
        }
    }

    private func insertPattern(_ patternName: String) {
        dismiss()
        onPatternSelected(patternName)
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    NavigationStack {
        BlockInserterView(
            sections: [
                BlockInserterSection(category: "text", name: "Text", blocks: BlockType.mocks)
            ],
            mediaPicker: MockMediaPickerController(),
            presentationContext: MediaPickerPresentationContext(),
            onBlockSelected: {
                print("block selected: \($0.name)")
            },
            onPatternSelected: {
                print("pattern selected: \($0)")
            },
            onMediaSelected: {
                print("media selected: \($0)")
            },
            loadPatterns: {
                return []
            }
        )
    }
}

struct MockMediaPickerController: MediaPickerController {
    func getActions(for parameters: MediaPickerParameters) -> [MediaPickerActionGroup] {
        let group = MediaPickerActionGroup(id: "extra", actions: [
            MediaPickerAction(id: "files", title: "Files", image: UIImage(systemName: "folder")!)
        ])
        return [group]
    }

    func perform(_ action: MediaPickerAction, parameters: MediaPickerParameters, from presentingViewController: UIViewController) async -> [MediaInfo] {
        print("action selected:", action)
        return []
    }
}
#endif
