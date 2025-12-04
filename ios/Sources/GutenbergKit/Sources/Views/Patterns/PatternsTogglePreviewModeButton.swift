#if canImport(UIKit)
import SwiftUI

/// A toolbar button that toggles between mobile and desktop preview modes for patterns
struct PatternsTogglePreviewModeButton: View {
    @AppStorage("GBKPatternsPreviewMode") private var previewMode: PreviewMode = .desktop

    var body: some View {
        Button {
            previewMode.toggle()
        } label: {
            Image(systemName: previewMode == .mobile ? "iphone" : "desktopcomputer")
        }
        .tint(Color.primary)
    }
}
#endif
