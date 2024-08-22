import SwiftUI
import GutenbergKit

struct ContentView: View {
    var body: some View {
        NavigationView {
            EditorView(editorURL: URL(string: "http://localhost:5173/")!)
        }
    }
}

#Preview {
    ContentView()
}
