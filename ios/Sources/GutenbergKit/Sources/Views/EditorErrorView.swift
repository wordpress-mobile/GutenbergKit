import SwiftUI

struct EditorErrorView: View {

    class ErrorProvider: ObservableObject {
        @Published var error: Error?

        func setError(_ error: Error?) {
            self.objectWillChange.send()
            self.error = error
        }
    }

    @State
    var errorProvider: ErrorProvider = ErrorProvider()

    init(error: Error? = nil) {
        self.errorProvider = ErrorProvider()
        if let error {
            self.errorProvider.setError(error)
        }
    }

    var body: some View {
        if let error = errorProvider.error {
            ContentUnavailableView(
                "Editor Error",
                systemImage: "exclamationmark.circle",
                description: Text(error.localizedDescription)
            )
        }
    }
}

#if canImport(UIKit)
import UIKit

class EditorErrorViewController: UIHostingController<EditorErrorView> {

    var error: Error? {
        get {
            self.rootView.errorProvider.error
        }
        set {
            self.rootView.errorProvider.setError(newValue)
        }
    }

    init(error: Error? = nil) {
        super.init(rootView: EditorErrorView(error: error))
    }

    @MainActor @preconcurrency required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
#endif

#Preview {
    EditorErrorView(error: CocoaError(.fileNoSuchFile))
}
