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

    @ScaledMetric(relativeTo: .largeTitle) private var inlinePickerHeight = 116

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
            .environmentObject(iconCache)
            .toolbar {
                toolbar
            }
            .animation(.smooth(duration: 2), value: viewModel.isProcessingMedia)
            .animation(.snappy, value: inlineSelectedMediaItems.count)
            .onDisappear {
                if viewModel.isProcessingMedia {
                    viewModel.cancelProcessing()
                }
            }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                ForEach(viewModel.sections, content: makeSection)
            }
            .padding(.vertical, 6)
            .dynamicTypeSize(...(.accessibility3))
        }
        .scrollContentBackground(.hidden)
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
    }

    @ViewBuilder
    private func makeSection(with section: BlockInserterSection) -> some View {
        VStack(spacing: inlinePickerSpacing) {
            BlockInserterSectionView(section: section, onBlockSelected: insertBlock)
                .padding(.bottom, 6)

            if viewModel.searchText.isEmpty && section.category == "gbk-most-used" {
                inlinePhotosPicker
            }
        }
        .cardStyle()
        .padding(.horizontal)
    }

    private var inlinePickerSpacing: CGFloat {
        if #available(iOS 26, *) { -6.0 } else { 16.0 }
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
            PhotosPicker(
                selection: $selectedMediaItems,
                preferredItemEncoding: .compatible
            ) {
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

        ToolbarItemGroup(placement: .confirmationAction) {
            if !inlineSelectedMediaItems.isEmpty {
                buttonInsertInlineMedia
            }
        }
    }

    // MARK: - Inline PhotosPicker (.inline)

    @ViewBuilder
    private var inlinePhotosPicker: some View {
        PhotosPicker(
            "",
            selection: $inlineSelectedMediaItems,
            selectionBehavior: .continuousAndOrdered,
            preferredItemEncoding: .compatible
        )
        .photosPickerStyle(.compact)
        .photosPickerAccessoryVisibility(.hidden)
        .frame(height: inlinePickerHeight)
    }

    @ViewBuilder
    private var buttonInsertInlineMedia: some View {
        let label = Text("+\(max(1, inlineSelectedMediaItems.count))")
            .font(.headline.monospacedDigit())
            .contentTransition(.numericText())

        if #available(iOS 26, *) {
            Button(role: .confirm) {
                insertInlineMedia()
            } label: {
                label
            }
        } else {
            Button {
                insertInlineMedia()
            } label: {
                label
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
        }
    }

    // MARK: - Actions

    private func insertBlock(_ block: BlockType) {
        dismiss()
        onBlockSelected(block)
    }

    private func insertInlineMedia() {
        insertMedia(inlineSelectedMediaItems)
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
                BlockInserterSection(category: "gbk-most-used", name: nil, blocks: Array(BlockType.mocks.prefix(12))),
                BlockInserterSection(category: "text", name: "Text", blocks: Array(BlockType.mocks.prefix(12)))
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
