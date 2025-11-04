import SwiftUI
import PhotosUI
import UIKit

struct BlockInserterView: View {
    let sections: [BlockInserterSection]
    let mediaPicker: MediaPickerController?
    let presentationContext: MediaPickerPresentationContext
    let onBlockSelected: (BlockType) -> Void
    let onMediaSelected: ([MediaInfo]) -> Void

    @StateObject private var viewModel: BlockInserterViewModel
    @StateObject private var iconCache = BlockIconCache()

    @State private var selectedMediaItems: [PhotosPickerItem] = []
    @State private var inlineSelectedMediaItems: [PhotosPickerItem] = []

    @ScaledMetric(relativeTo: .largeTitle) private var inlinePickerHeight = 86

    private let maxSelectionCount = 10

    @Environment(\.dismiss) private var dismiss

    init(
        sections: [BlockInserterSection],
        mediaPicker: MediaPickerController?,
        presentationContext: MediaPickerPresentationContext,
        onBlockSelected: @escaping (BlockType) -> Void,
        onMediaSelected: @escaping ([MediaInfo]) -> Void
    ) {
        self.sections = sections
        self.mediaPicker = mediaPicker
        self.presentationContext = presentationContext
        self.onBlockSelected = onBlockSelected
        self.onMediaSelected = onMediaSelected

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
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ForEach(viewModel.sections) { section in


                    BlockInserterSectionView(section: section, onBlockSelected: insertBlock)
                        .padding(.horizontal)


                    // Show inline photos picker after the "most common" section
                    if viewModel.searchText.isEmpty && section.category == "gbk-most-used" {
                        inlinePhotosPickerSection
                    }
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

            if let mediaPicker {
                MediaPickerMenu(picker: mediaPicker, context: presentationContext) {
                    dismiss()
                    onMediaSelected($0)
                }
            }
        }
    }

    // MARK: - Inline PhotosPicker (.inline)

    @available(iOS 17, *)
    @ViewBuilder
    private var inlinePhotosPickerSection: some View {
        PhotosPicker(
            "",
            selection: $inlineSelectedMediaItems,
            maxSelectionCount: maxSelectionCount,
            selectionBehavior: .continuousAndOrdered,
            preferredItemEncoding: .compatible
        )
        .photosPickerStyle(.compact)
        .photosPickerDisabledCapabilities([.collectionNavigation, .search, .sensitivityAnalysisIntervention, .stagingArea])
        .photosPickerAccessoryVisibility(.hidden)
        .padding(.top, -16)
        .frame(height: inlinePickerHeight ) // * 4) // Show a few rows
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)

        .opacity(viewModel.isProcessingMedia ? 0.5 : 1.0)
        .transition(.asymmetric(
            insertion: .scale(scale: 0.95).combined(with: .opacity),
            removal: .scale(scale: 0.95).combined(with: .opacity)
        ))
        .animation(.spring(response: 0.5, dampingFraction: 0.7), value: viewModel.searchText.isEmpty)

        if !inlineSelectedMediaItems.isEmpty {
            Button {
                insertMedia(inlineSelectedMediaItems)
                inlineSelectedMediaItems = []
            } label: {
                // Making the best of it without using any localizable strings
                Image(systemName: "plus")
                // Setting max 1 to to prevent it from animating to 0 on disappear
                Text("\(max(1, inlineSelectedMediaItems.count))")
                    .contentTransition(.numericText())
            }
            .font(.system(.headline, design: .rounded))
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .tint(.primary)
            // It animates as if it was hidden behind the next section
            .transition(.offset(y: 28).combined(with: .scale(scale: 0.85)))
            .frame(maxWidth: .infinity, alignment: .center)
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
}

// MARK: - Preview

#if DEBUG
#Preview {
    NavigationStack {
        BlockInserterView(
            sections: [
                BlockInserterSection(category: "gbk-most-used", name: nil, blocks: Array(BlockType.mocks.prefix(12)))
            ],
            mediaPicker: MockMediaPickerController(),
            presentationContext: MediaPickerPresentationContext(),
            onBlockSelected: {
                print("block selected: \($0.name)")
            },
            onMediaSelected: {
                print("media selected: \($0)")
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
