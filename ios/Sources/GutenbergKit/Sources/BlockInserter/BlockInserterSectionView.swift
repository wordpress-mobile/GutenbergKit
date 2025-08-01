import SwiftUI
import PhotosUI

struct BlockInserterSectionView: View {
    let section: BlockInserterSection
    let onBlockSelected: (EditorBlockType) -> Void
    let onMediaSelected: ([PhotosPickerItem]) -> Void

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    init(
        section: BlockInserterSection,
        onBlockSelected: @escaping (EditorBlockType) -> Void,
        onMediaSelected: @escaping ([PhotosPickerItem]) -> Void
    ) {
        self.section = section
        self.onBlockSelected = onBlockSelected
        self.onMediaSelected = onMediaSelected
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            sectionHeader
                .frame(maxWidth: .infinity, alignment: .leading)
            blockGrid
        }
        .padding(.top, 20)
        .padding(.bottom, 12)
        .cardStyle()
        .padding(.horizontal)
    }

    private var sectionHeader: some View {
        Text(section.name)
            .font(.headline)
            .foregroundStyle(Color.secondary)
            .padding(.leading, 20)
    }

    private var blockGrid: some View {
        LazyVGrid(columns: gridColumns) {
            ForEach(section.blockTypes) { blockType in
                BlockInserterItemView(blockType: blockType) {
                    onBlockSelected(blockType)
                }
            }
        }
        .padding(.horizontal, 14)
    }
    
    private var gridColumns: [GridItem] {
        return [GridItem(.adaptive(minimum: 80, maximum: 120), spacing: 0)]
    }
}

// MARK: - Media Picker Button

private struct MediaPickerButton: View {
    var body: some View {
        VStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(uiColor: .secondarySystemFill))
                .frame(height: 120)
                .overlay(
                    VStack(spacing: 8) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text("Choose from Photos")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                )
        }
    }
}
