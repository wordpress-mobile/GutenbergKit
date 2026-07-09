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
        Coordinator(viewModel: viewModel, configuration: configuration)
    }

    func makeUIViewController(context: Context) -> EditorViewController {
        let viewController = EditorViewController(configuration: configuration, dependencies: dependencies)
        viewController.delegate = context.coordinator
        if enableNativeMediaUpload {
            viewController.mediaUploadDelegate = context.coordinator
        }
        viewController.webView.isInspectable = true
        context.coordinator.editorViewController = viewController

        // Debug automation: if the editor never reports ready (which can
        // happen under Lockdown Mode), run the upload probe anyway after a
        // grace period.
        if ProcessInfo.processInfo.environment["GUTENBERG_UPLOAD_PROBE"] == "1" {
            Task { @MainActor [weak coordinator = context.coordinator] in
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                coordinator?.runUploadProbeIfRequested(trigger: "timeout")
            }
        }

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
        let configuration: EditorConfiguration
        weak var editorViewController: EditorViewController?
        private var didRunUploadProbe = false

        init(viewModel: EditorViewModel, configuration: EditorConfiguration) {
            self.viewModel = viewModel
            self.configuration = configuration
        }

        // MARK: - Lockdown Mode Upload Probe (debug automation)

        /// Runs a JS capability + upload probe inside the editor web view and
        /// prints the results to stdout. Enabled with GUTENBERG_UPLOAD_PROBE=1.
        func runUploadProbeIfRequested(trigger: String) {
            guard ProcessInfo.processInfo.environment["GUTENBERG_UPLOAD_PROBE"] == "1",
                  !didRunUploadProbe,
                  let editorViewController else { return }
            didRunUploadProbe = true

            let webView = editorViewController.webView
            let lockdown = webView.configuration.defaultWebpagePreferences.isLockdownModeEnabled
            print("LOCKDOWN_PROBE_START trigger=\(trigger) isLockdownModeEnabled=\(lockdown)")

            let probeJS = """
            const out = {};
            const S = (e) => (e && e.name ? (e.name + ': ' + e.message) : String(e));
            const T = (ms) => AbortSignal.timeout(ms || 10000);
            const race = (p, ms) => Promise.race([p, new Promise((_, rej) => setTimeout(() => rej({name: 'ProbeTimeout', message: (ms || 30000) + 'ms elapsed'}), ms || 30000))]);
            const makeFile = () => {
                const bytes = Uint8Array.from(atob('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=='), c => c.charCodeAt(0));
                return new File([bytes], 'lockdown-probe.png', {type: 'image/png'});
            };
            out.href = location.href.split('?')[0];
            out.origin = location.origin;
            out.typeof_FileReader = typeof FileReader;
            out.typeof_WebAssembly = typeof WebAssembly;
            out.typeof_apiFetch = typeof (window.wp && window.wp.apiFetch);
            out.gbk_nativeUploadPort = !!(window.GBKit && window.GBKit.nativeUploadPort);
            out.gbk_networkProxy = !!(window.GBKit && window.GBKit.networkProxy);
            const ECHO = 'http://192.168.0.57:8890';
            try { const r = await fetch(ECHO + '/star/get', {signal: T()}); out.echo_star_get = r.status; } catch (e) { out.echo_star_get = 'REJECT ' + S(e); }
            try { const fdE = new FormData(); fdE.append('probe', 'x'); const r = await fetch(ECHO + '/star/fd', {method: 'POST', body: fdE, signal: T()}); out.echo_star_post_formdata = r.status; } catch (e) { out.echo_star_post_formdata = 'REJECT ' + S(e); }
            try { const r = await fetch(apiRoot, {method: 'GET', signal: T()}); out.site_get_direct = r.status; } catch (e) { out.site_get_direct = 'REJECT ' + S(e); }
            try {
                const fd1 = new FormData();
                fd1.append('file', makeFile());
                const r = await fetch(apiRoot + 'wp/v2/media', {method: 'POST', headers: {Authorization: authHeader}, body: fd1, signal: T()});
                out.site_post_media_direct = r.status;
            } catch (e) { out.site_post_media_direct = 'REJECT ' + S(e); }
            try {
                const fd = new FormData();
                fd.append('file', makeFile());
                const res = await race(window.wp.apiFetch({ path: '/wp/v2/media', method: 'POST', body: fd }), 45000);
                out.apiFetch_post_media = 'ok id=' + res.id;
            } catch (e) { out.apiFetch_post_media = 'FAIL ' + S(e) + ' code=' + (e && e.code); }
            try {
                const res = await race(window.wp.apiFetch({ path: '/wp/v2/categories?per_page=1' }), 30000);
                out.apiFetch_get_categories = 'ok count=' + res.length;
            } catch (e) { out.apiFetch_get_categories = 'FAIL ' + S(e) + ' code=' + (e && e.code); }
            return JSON.stringify(out, null, 1);
            """

            Task { @MainActor in
                do {
                    let result = try await webView.callAsyncJavaScript(
                        probeJS,
                        arguments: [
                            "apiRoot": configuration.siteApiRoot.absoluteString,
                            "authHeader": configuration.authHeader
                        ],
                        contentWorld: .page
                    )
                    print("LOCKDOWN_PROBE_RESULT \(result ?? "nil")")
                } catch {
                    print("LOCKDOWN_PROBE_ERROR \(error)")
                }
            }
        }

        // MARK: - EditorViewControllerDelegate

        func editorDidLoad(_ viewContoller: EditorViewController) {
            viewModel.isEditorReady = true
            runUploadProbeIfRequested(trigger: "editorDidLoad")
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

        /// Resizes images to a maximum dimension of 2000px before upload.
        nonisolated func processFile(at url: URL, mimeType: String, filename: String) async throws -> ProcessedProxyFile {
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
