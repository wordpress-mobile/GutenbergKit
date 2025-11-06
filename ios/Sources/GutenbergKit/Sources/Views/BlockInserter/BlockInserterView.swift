import SwiftUI
import PhotosUI
import UIKit
import WebKit

enum BlockInserterSelection {
    case block(BlockType)
    case pattern(Pattern)
    case media([MediaInfo])
}

struct BlockInserterView: View {
    let sections: [BlockInserterSection]
    let patterns: [Pattern]
    let mediaPicker: MediaPickerController?
    let presentationContext: MediaPickerPresentationContext
    let onSelection: (BlockInserterSelection) -> Void

    @StateObject private var viewModel: BlockInserterViewModel
    @StateObject private var iconCache = BlockIconCache()

    @State private var selectedMediaItems: [PhotosPickerItem] = []
    @State private var inlineSelectedMediaItems: [PhotosPickerItem] = []
    @State private var isShowingCamera = false
    @State private var availableWidth: CGFloat = 0

    @ScaledMetric(relativeTo: .largeTitle) private var inlinePickerHeight = 116

    @Environment(\.dismiss) private var dismiss
    @State private var showingPatterns = false

    private var isLargeWidth: Bool {
        availableWidth >= 500
    }

    init(
        sections: [BlockInserterSection],
        patterns: [Pattern],
        mediaPicker: MediaPickerController?,
        presentationContext: MediaPickerPresentationContext,
        onSelection: @escaping (BlockInserterSelection) -> Void
    ) {
        self.sections = sections
        self.patterns = patterns
        self.mediaPicker = mediaPicker
        self.presentationContext = presentationContext
        self.onSelection = onSelection

        let viewModel = BlockInserterViewModel(sections: sections)
        self._viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        content
            .background(Material.ultraThin)
            .conditionallySearchable(text: $viewModel.searchText, isEnabled: !isLargeWidth)
            .navigationBarTitleDisplayMode(.inline)
            .disabled(viewModel.isProcessingMedia)
            .environmentObject(iconCache)
            .toolbar {
                toolbar
            }
            .sheet(isPresented: $isShowingCamera) {
                CameraView { media in
                    insertCameraMedia(media)
                }
                .ignoresSafeArea()
            }
            .animation(.smooth(duration: 2), value: viewModel.isProcessingMedia)
            .animation(.snappy, value: inlineSelectedMediaItems.count)
            .onDisappear {
                if viewModel.isProcessingMedia {
                    viewModel.cancelProcessing()
                }
            }
            .sheet(isPresented: $showingPatterns) {
                NavigationStack {
                    PatternsView(
                        patterns: patterns,
                        onPatternSelected: { pattern in
                            showingPatterns = false
                            insertPattern(pattern)
                        }
                    )
                }
            }
            .background(
                GeometryReader { geometry in
                    Color.clear
                        .onAppear {
                            availableWidth = geometry.size.width
                        }
                        .onChange(of: geometry.size.width) { _, newWidth in
                            if availableWidth != newWidth, newWidth > 0.0 {
                                availableWidth = newWidth
                            }
                        }
                }
            )
    }

    private var content: some View {
        ScrollView {
            if viewModel.sections.isEmpty {
                ContentUnavailableView.search(text: viewModel.searchText)
            } else {
                VStack(alignment: .leading, spacing: 24) {
                    ForEach(viewModel.sections, content: makeSection)
                }
                .padding(.vertical, 6)
                .dynamicTypeSize(...(.accessibility3))
            }
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
            if isLargeWidth {
                customSearchField
            }

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

            Button {
                isShowingCamera = true
            } label: {
                Image(systemName: "camera")
            }

            Button {
                showingPatterns = true
            } label: {
                Image(systemName: "square.grid.2x2")
            }
            .tint(Color.primary)

            if let mediaPicker {
                MediaPickerMenu(picker: mediaPicker, context: presentationContext) {
                    dismiss()
                    onSelection(.media($0))
                }
            }
        }

        ToolbarItemGroup(placement: .confirmationAction) {
            if !inlineSelectedMediaItems.isEmpty {
                buttonInsertInlineMedia
            }
        }
    }

    /// We use a custom search field on iPad to reduce the amount of vertical space used.
    /// The standard `.searchable` behavaior with ` .toolbar` placement doesn't
    /// achieve that. It defaults to a showing a full-screen search bar in a list
    /// regardless of the popover size.
    @ViewBuilder
    private var customSearchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .padding(.leading, 6)
            TextField(EditorLocalization[.search], text: $viewModel.searchText)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
            if !viewModel.searchText.isEmpty {
                Button {
                    viewModel.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: 260)
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
        .frame(height: inlinePickerHeight - (isLargeWidth ? 20 : 0))
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
        onSelection(.block(block))
    }

    private func insertPattern(_ pattern: Pattern) {
        dismiss()
        onSelection(.pattern(pattern))
    }

    private func insertInlineMedia() {
        insertMedia(inlineSelectedMediaItems)
    }

    private func insertMedia(_ items: [PhotosPickerItem]) {
        Task {
            let items = await viewModel.processSelectedPhotosPickerItems(items)
            if !items.isEmpty {
                dismiss()
                onSelection(.media(items))
            }
        }
    }

    private func insertCameraMedia(_ media: CameraMedia) {
        Task {
            let items = await viewModel.processCameraMedia(media)
            if !items.isEmpty {
                dismiss()
                onSelection(.media(items))
            }
        }
    }
}

// MARK: - Helpers

private extension View {
    @ViewBuilder
    func conditionallySearchable(text: Binding<String>, isEnabled: Bool) -> some View {
        if isEnabled {
            self.searchable(text: text)
        } else {
            self
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
            patterns: [],
            mediaPicker: MockMediaPickerController(),
            presentationContext: MediaPickerPresentationContext(),
            onSelection: { selection in
                print("on selected: \(selection)")
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
