import SwiftUI
import GutenbergKit

struct ContentView: View {
    var body: some View {
        #if os(macOS)
        EditorView()
        #else
        NavigationView {
            EditorView()
        }
        #endif
    }
}

#Preview {
    ContentView()
}
