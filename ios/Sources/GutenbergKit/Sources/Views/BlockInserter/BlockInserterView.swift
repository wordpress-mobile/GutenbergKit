import SwiftUI
import PhotosUI
import UIKit

struct BlockInserterView: View {
    let mediaPicker: MediaPickerController?
    let presentationContext: MediaPickerPresentationContext
    let onBlockSelected: (EditorBlock) -> Void
    let onMediaSelected: ([MediaInfo]) -> Void

    @StateObject private var viewModel: BlockInserterViewModel
    @StateObject private var iconCache = BlockIconCache()

    private let maxSelectionCount = 10

    @Environment(\.dismiss) private var dismiss

    init(
        blocks: [EditorBlock],
        mediaPicker: MediaPickerController?,
        presentationContext: MediaPickerPresentationContext,
        onBlockSelected: @escaping (EditorBlock) -> Void,
        onMediaSelected: @escaping ([MediaInfo]) -> Void
    ) {
        self.mediaPicker = mediaPicker
        self.presentationContext = presentationContext
        self.onBlockSelected = onBlockSelected
        self.onMediaSelected = onMediaSelected

        self._viewModel = StateObject(wrappedValue: BlockInserterViewModel(blocks: blocks))
    }

    var body: some View {
        content
            .background(Material.ultraThin)
            .searchable(text: $viewModel.searchText)
            .navigationBarTitleDisplayMode(.inline)
            .environmentObject(iconCache)
            .toolbar {
                toolbar
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
            if let mediaPicker {
                MediaPickerMenu(picker: mediaPicker, context: presentationContext) {
                    dismiss()
                    onMediaSelected($0)
                }
            }
        }
    }

    // MARK: - Actions

    private func insertBlock(_ block: EditorBlock) {
        dismiss()
        onBlockSelected(block)
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    NavigationStack {
        BlockInserterView(
            blocks: EditorBlock.mocks,
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
