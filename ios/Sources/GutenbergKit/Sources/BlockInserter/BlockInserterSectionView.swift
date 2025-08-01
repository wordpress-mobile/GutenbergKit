import SwiftUI
import PhotosUI

struct BlockInserterSectionView: View {
    let section: BlockInserterSection
    let isSearching: Bool
    let onBlockSelected: (EditorBlockType) -> Void
    let onMediaSelected: ([PhotosPickerItem]) -> Void

    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    init(
        section: BlockInserterSection,
        isSearching: Bool,
        onBlockSelected: @escaping (EditorBlockType) -> Void,
        onMediaSelected: @escaping ([PhotosPickerItem]) -> Void
    ) {
        self.section = section
        self.isSearching = isSearching
        self.onBlockSelected = onBlockSelected
        self.onMediaSelected = onMediaSelected
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            sectionHeader
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay {
                    if !selectedPhotoItems.isEmpty {
                        // Shown as an overlay as we don't want to affect the rest of the lasyout
                        insertButton
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .padding(.horizontal)
                    }
                }
            if #available(iOS 17.0, *) {
                if section.name == "Media" && !isSearching {
                    VStack(spacing: 12) {
                        mediaPickerStrip
                    }
                    .padding(.bottom, 8)
                }
            }

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

    @available(iOS 17, *)
    @ViewBuilder
    private var mediaPickerStrip: some View {
        PhotosPicker(
            "Photos",
            selection: $selectedPhotoItems,
            maxSelectionCount: 10,
            selectionBehavior: .continuousAndOrdered
        )
        .labelsHidden()
        .photosPickerStyle(.compact)
        .photosPickerDisabledCapabilities([.collectionNavigation, .search, .sensitivityAnalysisIntervention, .stagingArea])
        .photosPickerAccessoryVisibility(.hidden)
        .frame(height: 110)
        .padding(.top, pickerInsetTop)
    }

    private var pickerInsetTop: CGFloat {
        if #available(iOS 26, *) {
            // TODO: remove this workaround when iOS 26 fixes this inset
            return -18
        } else {
            return 0
        }
    }

    @ViewBuilder
    private var insertButton: some View {
        Button(action: {
            onMediaSelected(selectedPhotoItems)
            selectedPhotoItems = []
        }) {
            // TODO: (Inserter) Needs localization
            Text("Insert \(selectedPhotoItems.count) \(selectedPhotoItems.count == 1 ? "Item" : "Items")")
                .clipShape(Capsule())
        }
        .buttonStyle(.borderedProminent)

        .controlSize(.small)
        .tint(Color.primary)
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
