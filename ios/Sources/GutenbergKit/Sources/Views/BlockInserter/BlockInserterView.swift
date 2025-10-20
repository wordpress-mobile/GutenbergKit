import SwiftUI
import PhotosUI
import UIKit

struct BlockInserterView: View {
    let onBlockSelected: (EditorBlock) -> Void

    @StateObject private var viewModel: BlockInserterViewModel
    @StateObject private var iconCache = BlockIconCache()

    private let maxSelectionCount = 10

    @Environment(\.dismiss) private var dismiss
    
    init(
        blocks: [EditorBlock],
        onBlockSelected: @escaping (EditorBlock) -> Void,
    ) {
        self.onBlockSelected = onBlockSelected
        let viewModel = BlockInserterViewModel(blocks: blocks)
        self._viewModel = StateObject(wrappedValue: viewModel)
    }
    
    var body: some View {
        content
            .background(Material.ultraThin)
            .searchable(text: $viewModel.searchText)
            .navigationBarTitleDisplayMode(.inline)
            .environmentObject(iconCache)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
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
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
            }
            .tint(Color.primary)
        }
    }

    // MARK: - Actions

    private func insertBlock(_ blockType: EditorBlock) {
        dismiss()
        onBlockSelected(blockType)
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    NavigationStack {
        BlockInserterView(
            blocks: EditorBlock.mocks,
            onBlockSelected: {
                print("block selected: \($0.name)")
            }
        )
    }
}
#endif
