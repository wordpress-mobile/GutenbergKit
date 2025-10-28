import SwiftUI
import PhotosUI
import UIKit

struct BlockInserterView: View {
    let blocks: [BlockType]
    let destinationBlockName: String?
    let mediaPicker: MediaPickerController?
    let presentationContext: MediaPickerPresentationContext
    let onBlockSelected: (BlockType) -> Void
    let onMediaSelected: ([MediaInfo]) -> Void

    @StateObject private var viewModel: BlockInserterViewModel
    @StateObject private var iconCache = BlockIconCache()

    @State private var selectedMediaItems: [PhotosPickerItem] = []

    private let maxSelectionCount = 10

    @Environment(\.dismiss) private var dismiss

    init(
        blocks: [BlockType],
        destinationBlockName: String?,
        mediaPicker: MediaPickerController?,
        presentationContext: MediaPickerPresentationContext,
        onBlockSelected: @escaping (BlockType) -> Void,
        onMediaSelected: @escaping ([MediaInfo]) -> Void
    ) {
        self.blocks = blocks
        self.destinationBlockName = destinationBlockName
        self.mediaPicker = mediaPicker
        self.presentationContext = presentationContext
        self.onBlockSelected = onBlockSelected
        self.onMediaSelected = onMediaSelected

        let viewModel = BlockInserterViewModel(blocks: blocks, destinationBlockName: destinationBlockName)
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
            PhotosPicker(selection: $selectedMediaItems) {
                Image(systemName: "photo.on.rectangle.angled")
            }
            .onChange(of: selectedMediaItems) { _, selection in
                insertMedia(selection)
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

    // MARK: - Actions

    private func insertBlock(_ block: BlockType) {
        dismiss()
        onBlockSelected(block)
    }

    private func insertMedia(_ items: [PhotosPickerItem]) {
        Task {
            await viewModel.processMediaItems(items) { mediaInfo in
                dismiss()
                onMediaSelected(mediaInfo)
            }
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    NavigationStack {
        BlockInserterView(
            blocks: BlockType.mocks,
            destinationBlockName: nil,
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
