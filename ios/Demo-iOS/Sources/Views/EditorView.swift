import SwiftUI
import ImageIO
import OSLog
import UniformTypeIdentifiers
import GutenbergKit
import WordPressAPI
// `PostUpdateParams` is not yet re-exported from `WordPressAPI` in the pinned
// wordpress-rs release. It is reachable via the internal module, which is the
// same workaround WordPress-iOS uses. Remove this import once a tagged release
// including Automattic/wordpress-rs#1270 is adopted.
import WordPressAPIInternal

private extension Logger {
    static let demo = Logger(subsystem: "GutenbergKit-Demo", category: "media-upload")
}

struct EditorView: View {
    private let configuration: EditorConfiguration
    private let dependencies: EditorDependencies?
    private let apiClient: WordPressAPI?
    private let enableNativeMediaUpload: Bool

    @State private var viewModel = EditorViewModel()

    @Environment(\.dismiss) var dismiss

    init(configuration: EditorConfiguration, dependencies: EditorDependencies? = nil, apiClient: WordPressAPI? = nil, enableNativeMediaUpload: Bool = true) {
        self.configuration = configuration
        self.dependencies = dependencies
        self.apiClient = apiClient
        self.enableNativeMediaUpload = enableNativeMediaUpload
    }

    var body: some View {
        _EditorView(
            configuration: configuration,
            dependencies: dependencies,
            apiClient: apiClient,
            enableNativeMediaUpload: enableNativeMediaUpload,
            viewModel: viewModel
        )
            .toolbar { toolbar }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button {
                self.dismiss()
            } label: {
                Image(systemName: "xmark")
            }
            .accessibilityLabel("Close")
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
            Group {
                Button {
                    viewModel.perform(.undo)
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                }
                .disabled(!viewModel.hasUndo)
                .accessibilityLabel("Undo")

                Button {
                    viewModel.perform(.redo)
                } label: {
                    Image(systemName: "arrow.uturn.forward")
                }
                .disabled(!viewModel.hasRedo)
                .accessibilityLabel("Redo")
            }
            .disabled(viewModel.isModalDialogOpen)
        }

        ToolbarItemGroup(placement: .topBarTrailing) {
            moreMenu
                .disabled(viewModel.isModalDialogOpen)
        }

        ToolbarItem(placement: .topBarTrailing) {
            Button {
                viewModel.save()
            } label: {
                Text("Save")
                    .fontWeight(.semibold)
            }
            .disabled(!viewModel.canSave)
            .accessibilityLabel("Save")
        }
    }

    private var moreMenu: some View {
        Menu {
            Button(action: {
                viewModel.isCodeEditorEnabled.toggle()
            }, label: {
                Label(
                    viewModel.isCodeEditorEnabled ? "Visual Editor" : "Code Editor",
                    systemImage: viewModel.isCodeEditorEnabled ? "doc.richtext" : "curlybraces"
                )
            })
        } label: {
            Image(systemName: "ellipsis")
        }
        .accessibilityLabel("More")
    }
}

private struct _EditorView: UIViewControllerRepresentable {
    private let configuration: EditorConfiguration
    private let dependencies: EditorDependencies?
    private let apiClient: WordPressAPI?
    private let enableNativeMediaUpload: Bool
    private let viewModel: EditorViewModel

    init(
        configuration: EditorConfiguration,
        dependencies: EditorDependencies? = nil,
        apiClient: WordPressAPI? = nil,
        enableNativeMediaUpload: Bool = true,
        viewModel: EditorViewModel
    ) {
        self.configuration = configuration
        self.dependencies = dependencies
        self.apiClient = apiClient
        self.enableNativeMediaUpload = enableNativeMediaUpload
        self.viewModel = viewModel
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }

    func makeUIViewController(context: Context) -> EditorViewController {
        let viewController = EditorViewController(configuration: configuration, dependencies: dependencies)
        viewController.delegate = context.coordinator
        if enableNativeMediaUpload {
            viewController.mediaUploadDelegate = context.coordinator
            viewController.experimentalNativeMediaProcessing = true
        }
        viewController.webView.isInspectable = true

        viewModel.perform = { [weak viewController] in
            switch $0 {
            case .redo: viewController?.redo()
            case .undo: viewController?.undo()
            }
        }

        viewModel.hasPostID = configuration.postID != nil

        viewModel.saveHandler = { [weak viewController, weak viewModel] in
            guard let viewController, let viewModel else { return }
            await persistPost(viewController: viewController, viewModel: viewModel)
        }

        return viewController
    }

    func updateUIViewController(_ viewController: EditorViewController, context: Context) {
        viewController.isCodeEditorEnabled = viewModel.isCodeEditorEnabled
    }

    /// Persists the post via the REST API.
    private func persistPost(viewController: EditorViewController, viewModel: EditorViewModel) async {
        guard let apiClient, let postID = configuration.postID else { return }
        do {
            let titleAndContent = try await viewController.getTitleAndContent()
            let params = PostUpdateParams(title: .some(titleAndContent.title), content: .some(titleAndContent.content), meta: nil)
            let endpointType: PostEndpointType
            switch configuration.postType.postType {
            case "post":
                endpointType = .posts
            case "page":
                endpointType = .pages
            default:
                endpointType = .custom(configuration.postType.restBase)
            }
            _ = try await apiClient.posts.updateCancellation(
                postEndpointType: endpointType,
                postId: Int64(postID),
                params: params,
                context: nil
            )
            print("Post \(postID) persisted via REST API")
        } catch {
            print("Failed to persist post \(postID): \(error)")
        }
    }

    @MainActor
    class Coordinator: NSObject, EditorViewControllerDelegate, MediaUploadDelegate {
        let viewModel: EditorViewModel

        init(viewModel: EditorViewModel) {
            self.viewModel = viewModel
        }

        // MARK: - EditorViewControllerDelegate

        func editorDidLoad(_ viewContoller: EditorViewController) {
            viewModel.isEditorReady = true
        }

        func editor(_ viewContoller: EditorViewController, didDisplayInitialContent content: String) {
            // No-op for demo
        }

        func editor(_ viewContoller: EditorViewController, didEncounterCriticalError error: Error) {
            // No-op for demo
        }

        func editor(_ viewController: EditorViewController, didUpdateContentWithState state: EditorState) {
            // No-op for demo
        }

        func editor(_ viewController: EditorViewController, didUpdateHistoryState state: EditorState) {
            viewModel.hasUndo = state.hasUndo
            viewModel.hasRedo = state.hasRedo
        }

        func editor(_ viewController: EditorViewController, didUpdateFeaturedImage mediaID: Int) {
            // No-op for demo
        }

        func editor(_ viewController: EditorViewController, didLogException error: GutenbergJSException) {
            // No-op for demo
        }

        func editor(_ viewController: EditorViewController, didRequestMediaFromSiteMediaLibrary config: OpenMediaLibraryAction) {
            // No-op for demo
        }

        func editor(_ viewController: EditorViewController, didTriggerAutocompleter type: String) {
            let suggestions: [String]
            switch type {
            case "at-symbol":
                suggestions = ["alice", "bob", "charlie"]
            case "plus-symbol":
                suggestions = ["photoblog", "traveldiaries", "dailydev"]
            default:
                return
            }

            let alert = UIAlertController(title: "Select a suggestion", message: nil, preferredStyle: .actionSheet)
            for suggestion in suggestions {
                alert.addAction(UIAlertAction(title: suggestion, style: .default) { _ in
                    viewController.appendTextAtCursor(suggestion + " ")
                })
            }
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
            viewController.present(alert, animated: true)
        }

        func editor(_ viewController: EditorViewController, didOpenModalDialog dialogType: String) {
            viewModel.isModalDialogOpen = true
        }

        func editor(_ viewController: EditorViewController, didCloseModalDialog dialogType: String) {
            viewModel.isModalDialogOpen = false
        }

        func editor(_ viewController: EditorViewController, didLogNetworkRequest request: RecordedNetworkRequest) {
            print("🌐 Network Request: \(request.method) \(request.url)")
            print("   Status: \(request.status) \(request.statusText), Duration: \(request.duration)ms")

            // Log request headers
            if !request.requestHeaders.isEmpty {
                print("   Request Headers:")
                for (key, value) in request.requestHeaders.sorted(by: { $0.key < $1.key }) {
                    print("      \(key): \(value)")
                }
            }

            if let requestBody = request.requestBody {
                print("   Request Body: \(requestBody.prefix(200))...")
            }

            // Log response headers
            if !request.responseHeaders.isEmpty {
                print("   Response Headers:")
                for (key, value) in request.responseHeaders.sorted(by: { $0.key < $1.key }) {
                    print("      \(key): \(value)")
                }
            }

            if let responseBody = request.responseBody {
                print("   Response Body: \(responseBody.prefix(200))...")
            }
        }

        func editorDidRequestLatestContent(_ controller: EditorViewController) -> (title: String, content: String)? {
            // Demo app has no persistence layer, so return nil.
            // In a real app, return the persisted title and content from autosave.
            return nil
        }

        // MARK: - MediaUploadDelegate

        /// Only non-GIF images are ever resized (see `processFile`), so decline
        /// everything else by metadata — the server then skips copying a file
        /// this delegate would only pass through.
        nonisolated func handlesFile(ofType mimeType: String, named _: String) -> Bool {
            mimeType.hasPrefix("image/") && mimeType != "image/gif"
        }

        /// Adds a visible marker after the demo's existing image processing.
        nonisolated func processFile(at url: URL, mimeType: String, filename: String) async throws -> ProcessedProxyFile {
            let result = try await resizeFile(at: url, mimeType: mimeType, filename: filename)
            guard handlesFile(ofType: mimeType, named: filename) else {
                return result
            }

            let imageURL: URL
            switch result {
            case .original: imageURL = url
            case let .processed(processedURL, _, _): imageURL = processedURL
            }
            guard let labeledURL = addProcessingLabel(to: imageURL) else {
                return result
            }
            if imageURL != url {
                try? FileManager.default.removeItem(at: imageURL)
            }
            return .processed(labeledURL, mimeType: mimeType, filename: filename)
        }

        /// Resizes images to a maximum dimension of 2000px before upload.
        private nonisolated func resizeFile(at url: URL, mimeType: String, filename: String) async throws -> ProcessedProxyFile {
            guard mimeType.hasPrefix("image/"), mimeType != "image/gif" else {
                return .original
            }

            let maxDimension: CGFloat = 2000

            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                  let width = properties[kCGImagePropertyPixelWidth] as? CGFloat,
                  let height = properties[kCGImagePropertyPixelHeight] as? CGFloat else {
                return .original
            }

            let longestSide = max(width, height)
            guard longestSide > maxDimension else {
                return .original
            }

            let options: [CFString: Any] = [
                kCGImageSourceThumbnailMaxPixelSize: maxDimension,
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true
            ]

            guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
                return .original
            }

            let outputURL = url.deletingLastPathComponent()
                .appending(component: "resized-\(url.lastPathComponent)")

            let sourceType = CGImageSourceGetType(source) ?? (UTType.png.identifier as CFString)
            guard let destination = CGImageDestinationCreateWithURL(
                outputURL as CFURL,
                sourceType,
                1,
                nil
            ) else {
                return .original
            }

            CGImageDestinationAddImage(destination, thumbnail, nil)
            guard CGImageDestinationFinalize(destination) else {
                return .original
            }

            Logger.demo.info("Resized image from \(Int(width))x\(Int(height)) to fit \(Int(maxDimension))px")
            // Same format, so the original mimeType/filename carry over.
            return .processed(outputURL, mimeType: mimeType, filename: filename)
        }

        private nonisolated func addProcessingLabel(to url: URL) -> URL? {
            guard let image = UIImage(contentsOfFile: url.path),
                  let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let sourceType = CGImageSourceGetType(source) else {
                return nil
            }

            let size = image.size
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            let markedImage = UIGraphicsImageRenderer(size: size, format: format).image { context in
                image.draw(at: .zero)

                let fontSize = min(size.width * 0.045, size.height * 0.12)
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.boldSystemFont(ofSize: fontSize),
                    .foregroundColor: UIColor.red
                ]
                let label = "Processed natively" as NSString
                let textSize = label.size(withAttributes: attributes)
                let padding = fontSize * 0.3
                let textRect = CGRect(
                    x: (size.width - textSize.width) / 2,
                    y: padding * 2,
                    width: textSize.width,
                    height: textSize.height
                )
                context.cgContext.setFillColor(UIColor.white.cgColor)
                context.cgContext.fill(textRect.insetBy(dx: -padding, dy: -padding))
                label.draw(in: textRect, withAttributes: attributes)
            }
            guard let processedImage = markedImage.cgImage else {
                return nil
            }

            let outputURL = url.deletingLastPathComponent()
                .appending(component: "labeled-\(url.lastPathComponent)")
            guard let destination = CGImageDestinationCreateWithURL(outputURL as CFURL, sourceType, 1, nil) else {
                return nil
            }
            CGImageDestinationAddImage(destination, processedImage, nil)
            guard CGImageDestinationFinalize(destination) else {
                try? FileManager.default.removeItem(at: outputURL)
                return nil
            }
            return outputURL
        }
    }
}

@Observable
private final class EditorViewModel {
    var isModalDialogOpen = false
    var hasUndo = false
    var hasRedo = false
    var isCodeEditorEnabled = false
    var isSaving = false
    var isEditorReady = false

    var hasPostID = false

    var canSave: Bool {
        isEditorReady && !isSaving && hasPostID
    }

    enum Action {
        case undo
        case redo
    }

    var perform: (_ action: Action) -> Void = { _ in assertionFailure() }
    var saveHandler: () async -> Void = {}

    func save() {
        guard canSave else { return }
        isSaving = true
        Task {
            await saveHandler()
            isSaving = false
        }
    }
}

#Preview {
    NavigationStack {
        EditorView(configuration: .bundled)
    }
}

extension EditorConfiguration {
    static let bundled = EditorConfigurationBuilder(
        postType: .post,
        siteURL: URL(string: "https://example.com")!,
        siteApiRoot: URL(string: "https://example.com/wp-json")!
    )
    .setShouldUsePlugins(false)
    .setAuthHeader("")
    .setIsOfflineModeEnabled(true)
    .build()
}
