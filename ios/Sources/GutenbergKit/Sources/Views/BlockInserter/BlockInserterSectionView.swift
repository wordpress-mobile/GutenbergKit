import SwiftUI

struct BlockInserterSection: Identifiable, Decodable {
    var id: String { category }
    let category: String
    let name: String?
    let blocks: [BlockType]
}

struct BlockInserterSectionView: View {
    let section: BlockInserterSection
    let onBlockSelected: (BlockType) -> Void

    @ScaledMetric(relativeTo: .largeTitle) private var miniumSize = 80
    @ScaledMetric(relativeTo: .largeTitle) private var padding = 20
    @State private var isExpanded = false

    private let initialDisplayCount = 16

    private var displayedBlocks: [BlockType] {
        if !isExpanded && section.blocks.count > initialDisplayCount {
            return Array(section.blocks.prefix(initialDisplayCount))
        }
        return section.blocks
    }

    private var hasMoreBlocks: Bool {
        section.blocks.count > initialDisplayCount
    }

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
            if hasMoreBlocks {
                toggleButton
            }
        }
        .padding(.top, section.name != nil ? 20 : 24)
        .padding(.bottom, 10)
        .cardStyle()
    }

    private var grid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: miniumSize, maximum: miniumSize * 1.5), spacing: 0)]) {
            ForEach(displayedBlocks) { block in
                BlockInserterBlockView(block: block) {
                    onBlockSelected(block)
                }
            }
        }
        .padding(.horizontal, 12)
    }

    private var toggleButton: some View {
        Button {
            withAnimation {
                isExpanded.toggle()
            }
        } label: {
            HStack {
                // TODO: CMM-874 add localization
                Text(isExpanded ? "Show Less" : "Show More")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.caption)
            }
            .foregroundStyle(Color.primary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
    }
}
