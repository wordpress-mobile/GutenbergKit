import SwiftUI
import GutenbergKit
import AuthenticationServices
import WordPressAPI

struct AppRootView: View {

    @EnvironmentObject
    private var configurationStorage: ConfigurationStorage

    @State private var configurations: [ConfigurationItem] = [.bundledEditor]
    @State private var siteUrlInput = ""

    @State private var activeEditorConfiguration: EditorConfiguration? = nil

    @State private var hasError: Bool = false
    @State private var error: AppError? = nil

    @AppStorage("isNativeInserterEnabled") private var isNativeInserterEnabled = false

    var body: some View {
        EditorList()
        .alert(isPresented: $hasError, error: error, actions: {
            Button {
                self.hasError = false
            } label: {
                HStack {
                    Spacer()
                    Text("Dismiss")
                    Spacer()
                }
            }.buttonStyle(.borderedProminent)
        })
    }

}

struct AppError: LocalizedError {
    let errorDescription: String?
}

#Preview {
    AppRootView()
}
