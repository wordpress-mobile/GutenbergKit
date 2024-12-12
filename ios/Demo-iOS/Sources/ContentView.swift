import SwiftUI
import GutenbergKit

let editorURL: URL? = ProcessInfo.processInfo.environment["GUTENBERG_EDITOR_URL"].flatMap(URL.init)

struct ContentView: View {
    var body: some View {
        NavigationView {
            EditorView(editorURL: editorURL)
        }
    }
}

#Preview {
    ContentView()
}
