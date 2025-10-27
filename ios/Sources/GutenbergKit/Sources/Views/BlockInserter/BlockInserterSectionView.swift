import SwiftUI

struct BlockInserterSection: Identifiable {
    var id: String { category }
    let category: String
    let name: String?
    let blocks: [EditorBlock]
}

struct BlockInserterSectionView: View {
    let section: BlockInserterSection
    let onBlockSelected: (EditorBlock) -> Void

    @ScaledMetric(relativeTo: .largeTitle) private var miniumSize = 80
    @ScaledMetric(relativeTo: .largeTitle) private var padding = 20

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if let name = section.name {
                Text(name)
                    .font(.headline)
                    .foregroundStyle(Color.secondary)
                    .padding(.leading, padding)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            grid
        }
        .padding(.top, section.name != nil ? 20 : 24)
        .padding(.bottom, 10)
        .cardStyle()
    }

    private var grid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: miniumSize, maximum: miniumSize * 1.5), spacing: 0)]) {
            ForEach(section.blocks) { block in
                BlockInserterBlockView(block: block) {
                    onBlockSelected(block)
                }
            }
        }
        .padding(.horizontal, 12)
    }
}
