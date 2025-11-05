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
        self.sections = sections

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

    private func updateFilteredSections(searchText: String) {
        if searchText.isEmpty {
            sections = allSections
        } else {
            sections = allSections.compactMap { section in
                let filtered = SearchEngine<BlockType>()
                    .search(query: searchText, in: section.blocks)
                return filtered.isEmpty ? nil : BlockInserterSection(
                    category: section.category,
                    name: section.name,
                    blocks: filtered
                )
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
            await withTaskGroup(of: Void.self) { group in
                for item in items {
                    group.addTask {
                        do {
                            let item = try await self.fileManager.import(item)
                            results.append(item)
                        } catch {
                            anyError = error
                        }
                    }
                }
            }

            guard !Task.isCancelled else {
                return []
            }

            if results.isEmpty {
                // TODO: CMM-874 add localization
                self.error = MediaError(message: anyError?.localizedDescription ?? "Failed to insert media")
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
