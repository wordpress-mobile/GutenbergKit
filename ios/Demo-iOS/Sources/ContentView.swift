import SwiftUI
import GutenbergKit

let editorURL: URL? = ProcessInfo.processInfo.environment["GUTENBERG_EDITOR_URL"].flatMap(URL.init)

@Observable
class EditorListViewModel {

    var manifests: [LocalEditorManifest] = []

    var hasError: Bool = false

    var error: Error? = nil

    let library: EditorLibrary = EditorLibrary()

    func load() async {
        do {
            self.manifests = try await library.listManifests()
        } catch {
            self.error = error
        }
    }

    func remove(atOffsets offsets: IndexSet) {
        Task {
            do {
                for offset in offsets {
                    let manifestToRemove = manifests[offset]
                    try await library.remove(manifest: manifestToRemove)
                }
            } catch {
                self.error = error
            }

            await self.load()
        }
    }
}

struct ContentView: View {
    @State
    private var viewModel = EditorListViewModel()

    var body: some View {
        NavigationView {
            List {
                if let error = viewModel.error {
                    Text("Error fetching manifests: \(error.localizedDescription)")
                }

                ForEach(viewModel.manifests) { manifest in
                    NavigationLink(value: manifest) {
                        Text(manifest.name)
                    }
                }.onDelete(perform: deleteManifests)
            }
        }
        .task {
            await self.viewModel.load()
        }
        .navigationDestination(for: LocalEditorManifest.self) { manifest in
            EditorView(
                editorManifest: manifest,
                editorLibrary: viewModel.library
            )
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                NavigationLink("Add Editor") {
                    EditorDownloadView()
                }
            }
        }
    }

    func deleteManifests(_ offsets: IndexSet) {
        viewModel.remove(atOffsets: offsets)
    }
}

extension LocalEditorManifest: @retroactive Identifiable {
    public var id: String {
        self.rootDirectory.path
    }

    var name: String {
        self.rootDirectory.deletingPathExtension().lastPathComponent
    }
}

#Preview {
    ContentView()
}
