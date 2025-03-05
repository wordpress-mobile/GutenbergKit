import SwiftUI
import GutenbergKit

@main
struct GutenbergApp: App {
    var body: some Scene {
        WindowGroup {
            NavigationStack {
                ContentView()
            }
        }
    }
}

// We don't really care about dependency injection for our demo app, so we'll just make a bunch of singletons
extension EditorLibrary {
    static let shared = EditorLibrary()
}
