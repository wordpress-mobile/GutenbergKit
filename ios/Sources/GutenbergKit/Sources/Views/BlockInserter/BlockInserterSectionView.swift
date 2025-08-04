import SwiftUI
import PhotosUI

struct BlockInserterSectionView: View {
    let section: BlockInserterSection
    let onBlockSelected: (EditorBlock) -> Void
    let onMediaSelected: ([PhotosPickerItem]) -> Void

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @ScaledMetric(relativeTo: .largeTitle) private var miniumSize = 80

    init(
        section: BlockInserterSection,
        onBlockSelected: @escaping (EditorBlock) -> Void,
        onMediaSelected: @escaping ([PhotosPickerItem]) -> Void
    ) {
        self.section = section
        self.onBlockSelected = onBlockSelected
        self.onMediaSelected = onMediaSelected
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if section.category != "text" {
                Text(section.name)
                    .font(.headline)
                    .foregroundStyle(Color.secondary)
                    .padding(.leading, 20)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            grid
        }
        .padding(.top, section.category != "text" ? 20 : 24)
        .padding(.bottom, 10)
        .cardStyle()
    }

    private var grid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: miniumSize, maximum: miniumSize + 40), spacing: 0)]) {
            ForEach(section.blocks) { block in
                BlockInserterBlockView(block: block) {
                    onBlockSelected(block)
                }
            }
        }
        .padding(.horizontal, 12)
    }
}
