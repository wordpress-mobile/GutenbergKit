import SwiftUI

@main
struct GutenbergApp: App {
    var body: some Scene {
        WindowGroup {
            NavigationStack {
                AppRootView()
            }
        }
        .environmentObject(ConfigurationStorage())
        .environmentObject(AuthenticationManager())
    }
}
