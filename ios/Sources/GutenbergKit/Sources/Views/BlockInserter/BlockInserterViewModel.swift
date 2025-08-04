import SwiftUI
import PhotosUI
import Combine

@MainActor
class BlockInserterViewModel: ObservableObject {
    @Published var searchText = ""
    @Published var error: MediaError?
    @Published private(set) var sections: [BlockInserterSection] = []
    @Published private(set) var isProcessingMedia = false

    private let blocks: [EditorBlock]
    private let allSections: [BlockInserterSection]
    private let fileManager: EditorFileManager
    private var processingTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    struct MediaError: Identifiable {
        let id = UUID()
        let message: String
    }

    init(blocks: [EditorBlock], fileManager: EditorFileManager = .shared) {
        let blocks = blocks.filter { $0.name != "core/missing" }

        self.blocks = blocks
        self.fileManager = fileManager

        self.allSections = BlockInserterViewModel.createSections(from: blocks)
        self.sections = allSections

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
                let filtered = filterBlocks(in: section, searchText: searchText)
                return filtered.isEmpty ? nil : BlockInserterSection(
                    category: section.category,
                    name: section.name,
                    blocks: filtered
                )
            }
        }
    }
    
    private func filterBlocks(in section: BlockInserterSection, searchText: String) -> [EditorBlock] {
        let searchEngine = SearchEngine<EditorBlock>()
        let filtered = searchEngine.search(query: searchText, in: section.blocks)
        
        // Maintain paragraph first in text category when showing all blocks
        if searchText.isEmpty && section.name == "Text" && filtered.count > 1 {
            return sortTextBlocks(filtered)
        }
        
        return filtered
    }
    
    private func sortTextBlocks(_ blocks: [EditorBlock]) -> [EditorBlock] {
        let paragraphBlocks = blocks.filter { $0.name == "core/paragraph" }
        let otherBlocks = blocks.filter { $0.name != "core/paragraph" }
        return paragraphBlocks + otherBlocks
    }
    
    private static func createSections(from blockTypes: [EditorBlock]) -> [BlockInserterSection] {
        let categoryOrder = BlockInserterConstants.categoryOrder
        var grouped = Dictionary(grouping: blockTypes) { $0.category?.lowercased() ?? "common" }
        
        // Move core/embed from embed category to media category
        if let embedBlocks = grouped["embed"],
           let embedBlock = embedBlocks.first(where: { $0.name == "core/embed" }) {
            // Add to media category
            if var mediaBlocks = grouped["media"] {
                mediaBlocks.append(embedBlock)
                grouped["media"] = mediaBlocks
            } else {
                grouped["media"] = [embedBlock]
            }
            
            // Remove from embed category
            grouped["embed"] = embedBlocks.filter { $0.name != "core/embed" }
            if grouped["embed"]?.isEmpty == true {
                grouped.removeValue(forKey: "embed")
            }
        }
        
        var sections: [BlockInserterSection] = []
        
        // Add sections in WordPress standard order
        for (categoryKey, displayName) in categoryOrder {
            if let blocks = grouped[categoryKey] {
                let sortedBlocks = sortBlocks(blocks, category: categoryKey)
                sections.append(BlockInserterSection(category: categoryKey, name: displayName, blocks: sortedBlocks))
            }
        }
        
        // Add any remaining categories
        for (category, blocks) in grouped {
            let isStandardCategory = categoryOrder.contains { $0.key == category }
            if !isStandardCategory {
                sections.append(BlockInserterSection(category: category, name: category.capitalized, blocks: blocks))
            }
        }
        
        return sections
    }
    
    private static func sortBlocks(_ blocks: [EditorBlock], category: String) -> [EditorBlock] {
        switch category {
        case "text":
            return sortWithOrder(blocks, order: BlockInserterConstants.textBlockOrder)
        case "media":
            return sortWithOrder(blocks, order: BlockInserterConstants.mediaBlockOrder)
        case "design":
            return sortWithOrder(blocks, order: BlockInserterConstants.designBlockOrder)
        default:
            return blocks
        }
    }
    
    private static func sortWithOrder(_ blocks: [EditorBlock], order: [String]) -> [EditorBlock] {
        var orderedBlocks: [EditorBlock] = []
        
        // Add blocks in defined order
        for blockName in order {
            if let block = blocks.first(where: { $0.name == blockName }) {
                orderedBlocks.append(block)
            }
        }
        
        // Add remaining blocks in their original order
        let remainingBlocks = blocks.filter { block in
            !order.contains(block.name)
        }
        
        return orderedBlocks + remainingBlocks
    }
    
    // MARK: - Media Processing
    
    func processMediaItems(_ items: [PhotosPickerItem], completion: @escaping ([MediaInfo]) -> Void) async {
        isProcessingMedia = true
        defer { isProcessingMedia = false }

        var lastError: Error?
        
        // Store the task so it can be cancelled
        processingTask = Task { @MainActor in
            // Process all items in parallel
            let results = await withTaskGroup(of: MediaInfo?.self) { group in
                for item in items {
                    group.addTask {
                        // Check for cancellation
                        if Task.isCancelled { return nil }
                        
                        // Load the media data
                        guard let data = try? await item.loadTransferable(type: Data.self) else {
                            return nil
                        }
                        
                        // Determine file extension
                        let contentType = item.supportedContentTypes.first
                        let fileExtension = contentType?.preferredFilenameExtension ?? "jpg"
                        
                        do {
                            // Save to uploads directory - returns relative URL
                            let fileURL = try await self.fileManager.saveMediaData(data, withExtension: fileExtension)
                            
                            // Determine media type based on content type
                            let mediaType: String
                            if contentType?.conforms(to: .image) == true {
                                mediaType = "image"
                            } else if contentType?.conforms(to: .movie) == true {
                                mediaType = "video"
                            } else if contentType?.conforms(to: .audio) == true {
                                mediaType = "audio"
                            } else {
                                mediaType = "file"
                            }
                            
                            // Create MediaInfo object
                            return MediaInfo(url: fileURL.absoluteString, type: mediaType)
                        } catch {
                            print("Failed to save media file: \(error)")
                            lastError = error
                            return nil
                        }
                    }
                }
                
                var output: [MediaInfo] = []
                for await result in group {
                    if let mediaInfo = result {
                        output.append(mediaInfo)
                    }
                }
                return output
            }
            
            // Only call completion if not cancelled
            if !Task.isCancelled {
                // Show error if we encountered any errors and got no successful results
                if let error = lastError, results.isEmpty {
                    self.error = MediaError(message: error.localizedDescription)
                }
                
                // Still return successfully processed items
                completion(results)
            }
        }
        
        await processingTask?.value
    }
    
    func processCameraMedia(_ media: CameraMedia, completion: @escaping ([MediaInfo]) -> Void) async {
        isProcessingMedia = true
        defer { isProcessingMedia = false }

        processingTask = Task { @MainActor in
            do {
                // Check for cancellation
                if Task.isCancelled { return }
                
                let mediaInfo: MediaInfo
            
                switch media {
                case .photo(let image):
                    guard let imageData = image.jpegData(compressionQuality: 0.8) else {
                        return // Should never happen
                    }

                    // Save to uploads directory - returns relative URL
                    let fileURL = try await fileManager.saveMediaData(imageData, withExtension: "jpg")

                    // Create MediaInfo for the captured image
                    mediaInfo = MediaInfo(url: fileURL.absoluteString, type: "image")

                case .video(let videoURL):
                    // Copy video to uploads directory
                    let videoData = try Data(contentsOf: videoURL)
                    let fileExtension = videoURL.pathExtension.isEmpty ? "mp4" : videoURL.pathExtension

                    // Save to uploads directory - returns relative URL
                    let fileURL = try await fileManager.saveMediaData(videoData, withExtension: fileExtension)

                    // Create MediaInfo for the captured video
                    mediaInfo = MediaInfo(url: fileURL.absoluteString, type: "video")
                }

                // Only call completion if not cancelled
                if !Task.isCancelled {
                    completion([mediaInfo])
                }

            } catch {
                self.error = MediaError(message: error.localizedDescription)
            }
        }
        
        await processingTask?.value
    }
    
    func cancelProcessing() {
        processingTask?.cancel()
        processingTask = nil
        isProcessingMedia = false
    }
}

// MARK: - Constants

enum BlockInserterConstants {
    static let categoryOrder: [(key: String, displayName: String)] = [
        ("text", "Text"),
        ("media", "Media"),
        ("design", "Design"),
        ("widgets", "Widgets"),
        ("theme", "Theme"),
        ("embed", "Embeds")
    ]
    
    static let textBlockOrder = [
        "core/paragraph",
        "core/heading",
        "core/list",
        "core/list-item",
        "core/quote",
        "core/code",
        "core/preformatted",
        "core/verse",
        "core/table"
    ]
    
    static let mediaBlockOrder = [
        "core/image",
        "core/video",
        "core/gallery",
        "core/embed",
        "core/audio",
        "core/file"
    ]
    
    static let designBlockOrder = [
        "core/separator",
        "core/spacer",
        "core/columns",
        "core/column"
    ]
}

// MARK: - Supporting Types

struct BlockInserterSection: Identifiable {
    var id: String { category }
    let category: String
    let name: String
    let blocks: [EditorBlock]
}
