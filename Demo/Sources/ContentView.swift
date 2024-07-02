import SwiftUI
import GutenbergKit

struct ContentView: View {
    var body: some View {
        NavigationView {
            EditorView()
        }
        .navigationTitle("Editor Demo")
    }
}

#Preview {
    ContentView()
}
