import SwiftUI
import AuthenticationServices
import GutenbergKit
import WordPressAPI

/// View for adding a new editor configuration with site integration
struct AddSiteView: View {

    @EnvironmentObject
    private var configurationStorage: ConfigurationStorage

    @Environment(\.dismiss)
    private var dismiss: DismissAction

    @State private var siteUrl: String = ""
    @State private var errorMessage: String?
    @State private var isAuthenticating = false
    @State private var authTask: Task<Void, Never>?

    private let authenticationManager = AuthenticationManager()

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
                    Text("Enter the URL of your WordPress site (e.g., https://example.com).")
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle("Add WordPress Site")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                    }
                    .disabled(isAuthenticating)
                }

                ToolbarItem(placement: .confirmationAction) {
                    if isAuthenticating {
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
        .onDisappear {
            authTask?.cancel()
        }
    }

    private func startAuthentication() {
        let trimmedUrl = siteUrl.trimmingCharacters(in: .whitespaces)
        guard !trimmedUrl.isEmpty, !isAuthenticating else { return }

        errorMessage = nil
        isAuthenticating = true
        authTask = Task {
            defer { isAuthenticating = false }
            do {
                let account = try await authenticationManager.startAuthentication(
                    siteUrl: trimmedUrl,
                    presentationContext: presentationContextProvider
                )
                try onAdd(account)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func onAdd(_ account: Account) throws {
        try configurationStorage.addAccount(account)
        self.siteUrl = ""
        self.dismiss()
    }

    private func onCancel() {
        authTask?.cancel()
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
