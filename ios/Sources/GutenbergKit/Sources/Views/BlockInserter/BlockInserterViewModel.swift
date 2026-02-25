#if canImport(UIKit)
import SwiftUI
import PhotosUI
import Combine

@MainActor
class BlockInserterViewModel: ObservableObject {
    @Published var searchText = ""
    @Published var error: MediaError?
    @Published private(set) var sections: [BlockInserterSection] = []
    @Published private(set) var isProcessingMedia = false

    private let allSections: [BlockInserterSection]
    private let fileManager: MediaFileManager = .shared
    private var processingTask: Task<[MediaInfo], Never>?
    private var cancellables = Set<AnyCancellable>()

    struct MediaError: Identifiable, Error {
        let id = UUID()
        let message: String
    }

    init(sections: [BlockInserterSection]) {
        self.allSections = sections
        self.sections = sections.filter { $0.category != "gbk-search-only" }

        setupSearchObserver()
    }

    private func setupSearchObserver() {
        $searchText
            .debounce(for: .milliseconds(200), scheduler: RunLoop.main)
            .sink { [weak self] searchText in
                self?.updateFilteredSections(searchText: searchText)
            }
            .store(in: &cancellables)
    }

    /// Sections visible when browsing (excludes search-only sections).
    private var browsableSections: [BlockInserterSection] {
        allSections.filter { $0.category != "gbk-search-only" }
    }

    private func updateFilteredSections(searchText: String) {
        if searchText.isEmpty {
            sections = browsableSections
        } else {
            // Flatten all blocks (including search-only) into a single
            // ranked list so search results aren't split across sections.
            // Deduplicate by ID first since the same block can appear in
            // multiple sections (e.g. most-used and its category section).
            var seenIDs = Set<String>()
            let allBlocks = allSections.flatMap { $0.blocks }.filter { seenIDs.insert($0.id).inserted }
            let results = SearchEngine<BlockType>()
                .search(query: searchText, in: allBlocks)
            if results.isEmpty {
                sections = []
            } else {
                sections = [BlockInserterSection(
                    category: "gbk-search-results",
                    name: nil,
                    blocks: results
                )]
            }
        }
    }

    // MARK: - Media Processing

    func processSelectedPhotosPickerItems(_ items: [PhotosPickerItem]) async -> [MediaInfo] {
        isProcessingMedia = true
        defer { isProcessingMedia = false }

        let task = Task<[MediaInfo], Never> { @MainActor in
            var results: [MediaInfo] = []
            var anyError: Error?

            do {
                for item in items {
                    let item = try await self.fileManager.import(item)
                    results.append(item)
                }
            } catch {
                anyError = error
            }

            guard !Task.isCancelled else {
                return []
            }

            if results.isEmpty {
                self.error = MediaError(message: anyError?.localizedDescription ?? EditorLocalization[.failedToInsertMedia])
            }

            return results
        }
        processingTask = task
        return await task.value
    }


    func processCameraMedia(_ media: CameraMedia) async -> [MediaInfo] {
        isProcessingMedia = true
        defer { isProcessingMedia = false }

        let task = Task<[MediaInfo], Never> { @MainActor in
            do {
                let mediaInfo: MediaInfo

                switch media {
                case .photo(let image):
                    guard let imageData = image.jpegData(compressionQuality: 0.8) else {
                        throw MediaError(message: "Failed to convert image to JPEG")
                    }

                    let fileURL = try await fileManager.writeData(imageData, withExtension: "jpg")
                    mediaInfo = MediaInfo(url: fileURL.absoluteString, type: "image/jpeg")

                case .video(let videoURL):
                    let videoData = try Data(contentsOf: videoURL)
                    let fileExtension = videoURL.pathExtension.isEmpty ? "mp4" : videoURL.pathExtension
                    let fileURL = try await fileManager.writeData(videoData, withExtension: fileExtension)
                    mediaInfo = MediaInfo(url: fileURL.absoluteString, type: "video/\(fileExtension)")
                }

                guard !Task.isCancelled else {
                    return []
                }

                return [mediaInfo]

            } catch {
                self.error = MediaError(message: error.localizedDescription)
                return []
            }
        }
        processingTask = task
        return await task.value
    }

    func cancelProcessing() {
         processingTask?.cancel()
         processingTask = nil
         isProcessingMedia = false
     }
}
#endif
