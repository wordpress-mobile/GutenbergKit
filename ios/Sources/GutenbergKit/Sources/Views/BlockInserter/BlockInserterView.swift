import SwiftUI
import PhotosUI
import UIKit

struct BlockInserterView: View {
    let mediaPicker: MediaPickerController?
    weak var presentingViewController: UIViewController?
    let onBlockSelected: (EditorBlock) -> Void
    let onMediaSelected: ([MediaInfo]) -> Void

    @StateObject private var viewModel: BlockInserterViewModel

    @State private var selectedMediaItems: [PhotosPickerItem] = []
    @State private var inlineSelectedMediaItems: [PhotosPickerItem] = []
    @State private var isShowingCamera = false

    @ScaledMetric(relativeTo: .largeTitle) private var inlinePickerHeight = 86

    private let maxSelectionCount = 10

    @Environment(\.dismiss) private var dismiss
    
    init(
        blocks: [EditorBlock],
        mediaPicker: MediaPickerController?,
        presentingViewController: UIViewController? = nil,
        onBlockSelected: @escaping (EditorBlock) -> Void,
        onMediaSelected: @escaping ([MediaInfo]) -> Void
    ) {
        self.mediaPicker = mediaPicker
        self.presentingViewController = presentingViewController
        self.onBlockSelected = onBlockSelected
        self.onMediaSelected = onMediaSelected

        self._viewModel = StateObject(wrappedValue: BlockInserterViewModel(blocks: blocks))
    }
    
    var body: some View {
        content
            .background(Material.ultraThin)
            .searchable(text: $viewModel.searchText)
            .navigationBarTitleDisplayMode(.inline)
            .disabled(viewModel.isProcessingMedia)
            // In most cases, processing is nearly instant – we don't want any jarring changes
            .animation(.smooth(duration: 2), value: viewModel.isProcessingMedia)
            .toolbar { toolbarContent }
            .fullScreenCover(isPresented: $isShowingCamera) {
                CameraView { insertMedia($0) }
                    .ignoresSafeArea()
            }
            .alert(item: $viewModel.error) { error in
                Alert(title: Text(error.message))
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
                if #available(iOS 17, *) {
                    if viewModel.searchText.isEmpty {
                        inlinePhotosPickerSection
                    }
                }
                ForEach(viewModel.sections) { section in
                    BlockInserterSectionView(
                        section: section,
                        onBlockSelected: insertBlock,
                        onMediaSelected: insertMedia
                    )
                    .padding(.horizontal)
                }
            }
            .padding(.vertical, 8)
            .dynamicTypeSize(...(.accessibility3))
        }
        .scrollContentBackground(.hidden)
        .animation(.snappy, value: inlineSelectedMediaItems.count)
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
        ToolbarItemGroup(placement: .automatic) {
            mediaToolbarButtons
                .tint(Color.primary)
                .disabled(viewModel.isProcessingMedia)
        }
    }
    
    @ViewBuilder
    private var mediaToolbarButtons: some View {
        PhotosPicker(selection: $selectedMediaItems) {
            Image(systemName: "photo.on.rectangle.angled")
        }
        .onChange(of: selectedMediaItems) {
            insertMedia($0)
            selectedMediaItems = []
        }
        
        Button(action: {
            isShowingCamera = true
        }) {
            Image(systemName: "camera")
        }

        if let groups = mediaPicker?.actions, !groups.isEmpty {
            Menu {
                ForEach(groups.indices, id: \.self) { groupIndex in
                    Section {
                        ForEach(groups[groupIndex]) { picker in
                            Button(action: {
                                if let presentingViewController {
                                    picker.perform(presentingViewController) { mediaInfo in
                                        self.onMediaSelected(mediaInfo)
                                        self.dismiss()
                                    }
                                }
                            }) {
                                Label {
                                    Text(picker.title)
                                } icon: {
                                    Image(uiImage: picker.image)
                                }
                            }
                        }
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
            }
        }
    }

    // MARK: - Inline PhotosPicker (.compact)

    @available(iOS 17, *)
    @ViewBuilder
    private var inlinePhotosPickerSection: some View {
        PhotosPicker(
            "",
            selection: $inlineSelectedMediaItems,
            maxSelectionCount: maxSelectionCount,
            selectionBehavior: .continuousAndOrdered
        )
        .photosPickerStyle(.compact)
        .photosPickerDisabledCapabilities([.collectionNavigation, .search, .sensitivityAnalysisIntervention, .stagingArea])
        .photosPickerAccessoryVisibility(.hidden)
        .frame(height: inlinePickerHeight)
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 22, bottomLeadingRadius: 22, bottomTrailingRadius: 0, topTrailingRadius: 0))
        .padding(.leading)
        .opacity(viewModel.isProcessingMedia ? 0.5 : 1.0)
        .transition(.asymmetric(
            insertion: .scale(scale: 0.95, anchor: .leading).combined(with: .opacity),
            removal: .scale(scale: 0.95, anchor: .leading).combined(with: .opacity)
        ))
        .animation(.spring(response: 0.5, dampingFraction: 0.7), value: viewModel.searchText.isEmpty)

        if !inlineSelectedMediaItems.isEmpty {
            Button {
                insertMedia(inlineSelectedMediaItems)
                inlineSelectedMediaItems = []
            } label: {
                // Making the best of it without using any localizable strings
                Image(systemName: "plus")
                // Setting max 1 to to prevent it from animating to 0 on disappear
                Text("\(max(1, inlineSelectedMediaItems.count))")
                    .contentTransition(.numericText())
            }
            .font(.system(.headline, design: .rounded))
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .tint(.primary)
            // It animates as if it was hidden behind the next section
            .transition(.offset(y: 28).combined(with: .scale(scale: 0.85)))
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    // MARK: - Actions

    private func insertBlock(_ blockType: EditorBlock) {
        dismiss()
        onBlockSelected(blockType)
    }
    
    private func insertMedia(_ items: [PhotosPickerItem]) {
        Task {
            await viewModel.processMediaItems(items) { mediaInfo in
                dismiss()
                onMediaSelected(mediaInfo)
            }
        }
    }

    private func insertMedia(_ media: CameraMedia) {
        Task {
            await viewModel.processCameraMedia(media) { mediaInfo in
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
            blocks: PreviewData.sampleBlockTypes,
            mediaPicker: MockMediaPickerController(),
            onBlockSelected: { blockType in
                print("Selected block: \(blockType.name)")
            },
            onMediaSelected: { mediaInfo in
                print("Selected \(mediaInfo.count) media items")
            }
        )
    }
}

struct MockMediaPickerController: MediaPickerController {
    let actions: [[MediaPickerAction]] = [[
        MediaPickerAction(id: "files", title: "Files", image: UIImage(systemName: "folder")!) { _, completion in
            print("Files tapped")
            completion([])
        }
    ]]
}
#endif
