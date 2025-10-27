import SwiftUI
import AuthenticationServices
import GutenbergKit

/// View for adding a new remote editor site
struct AddSiteView: View {

    @EnvironmentObject
    private var configurationStorage: ConfigurationStorage

    @EnvironmentObject
    private var authenticationManager: AuthenticationManager

    @Environment(\.dismiss)
    private var dismiss: DismissAction

    @State private var siteUrl: String = ""

    @State private var presentationContextProvider = WebAuthPresentationContextProvider()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Site URL", text: $siteUrl)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .onSubmit {
                            startAuthentication()
                        }
                } header: {
                    Text("WordPress Site")
                } footer: {
                    Text("Enter the URL of your WordPress site (e.g., https://example.com)")
                }

                if let errorMessage = authenticationManager.errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle("Add Remote Editor")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                    }
                    .disabled(authenticationManager.isAuthenticating)
                }

                ToolbarItem(placement: .confirmationAction) {
                    if authenticationManager.isAuthenticating {
                        ProgressView()
                    } else {
                        Button("Add") {
                            startAuthentication()
                        }
                        .disabled(siteUrl.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
        }
    }

    private func startAuthentication() {
        let trimmedUrl = siteUrl.trimmingCharacters(in: .whitespaces)
        guard !trimmedUrl.isEmpty else { return }

        authenticationManager.startAuthentication(
            siteUrl: trimmedUrl,
            presentationContext: presentationContextProvider
        ) { configuration in
            onAdd(configuration)
        }
    }

    private func onAdd(_ configuration: RemoteEditorConfiguration) {
        configurationStorage.addConfiguration(.remoteEditor(configuration))
        self.siteUrl = ""
        self.dismiss()
    }

    private func onCancel() {
        self.siteUrl = ""
        self.dismiss()
    }
}

/// Provides the presentation context for web authentication
class WebAuthPresentationContextProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        // Return the first window that can be used as a presentation anchor
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first {
            return window
        }
        // Fallback to a new window (shouldn't normally happen)
        return ASPresentationAnchor()
    }
}
