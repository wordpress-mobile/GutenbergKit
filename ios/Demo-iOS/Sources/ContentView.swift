import SwiftUI
import GutenbergKit

let editorURL: URL? = ProcessInfo.processInfo.environment["GUTENBERG_EDITOR_URL"].flatMap(URL.init)

@Observable
class EditorListViewModel {

    var manifests: [LocalEditorManifest] = []

    var hasError: Bool = false

    var error: Error? = nil

    func load() async {
        do {
            self.manifests = try await EditorLibrary.shared.listManifests()
        } catch {
            self.error = error
        }
    }

    func remove(atOffsets offsets: IndexSet) {
        Task {
            do {
                for offset in offsets {
                    let manifestToRemove = manifests[offset]
                    try await EditorLibrary.shared.remove(manifest: manifestToRemove)
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

    let bundledManifest = EditorLibrary.shared.bundledManifest

    var body: some View {
        NavigationView {
            List {
                if let error = viewModel.error {
                    Text("Error fetching manifests: \(error.localizedDescription)")
                }

                Section {
                    NavigationLink(value: bundledManifest) {
                        Text("Bundled Gutenberg")
                    }
                }

                if !viewModel.manifests.isEmpty {
                    Section("Downloaded Bundles") {
                        ForEach(viewModel.manifests) { manifest in
                            NavigationLink(value: manifest) {
                                Text(manifest.name)
                            }
                        }.onDelete(perform: deleteManifests)
                    }
                }
            }
        }
        .task {
            await self.viewModel.load()
        }
        .navigationDestination(for: LocalEditorManifest.self) { manifest in
            EditorView(editorManifest: manifest)
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
