import Foundation
import AuthenticationServices
import WordPressAPI

/// Manages WordPress authentication flow
@MainActor
class AuthenticationManager: NSObject, ObservableObject {
    @Published var isAuthenticating = false
    @Published var errorMessage: String?

    private var currentApiRootUrl: String?
    private var authSession: ASWebAuthenticationSession?
    private var currentClient: WordPressLoginClient?
    private var onAuthenticationComplete: ((ConfiguredEditor) -> Void)?

    private static let appName = "GutenbergKit iOS Demo App"
    private static let callbackURLScheme = "gutenbergkit"

    /// Start the authentication flow for a WordPress site
    func startAuthentication(
        siteUrl: String,
        presentationContext: ASWebAuthenticationPresentationContextProviding,
        onComplete: @escaping (ConfiguredEditor) -> Void
    ) {
        isAuthenticating = true
        errorMessage = nil
        onAuthenticationComplete = onComplete

        Task {
            do {
                let client = WordPressLoginClient(urlSession: URLSession(configuration: .ephemeral))
                let details = try await client.details(ofSite: siteUrl)

                let apiRootUrl = details.apiRootUrl.url()
                let appId = try! WpUuid.parse(input: "00000000-0000-4000-9000-000000000000")
                let authUrl = details.loginURL(for: .init(
                    id: appId,
                    name: Self.appName,
                    callbackUrl: "\(Self.callbackURLScheme)://authorized"
                ))

                currentApiRootUrl = apiRootUrl
                currentClient = client

                launchAuthenticationFlow(
                    authenticationUrl: authUrl,
                    presentationContext: presentationContext
                )
            } catch {
                isAuthenticating = false
                errorMessage = "Authentication error: \(error.localizedDescription)"
            }
        }
    }

    /// Launch the web authentication session
    private func launchAuthenticationFlow(
        authenticationUrl: URL,
        presentationContext: ASWebAuthenticationPresentationContextProviding
    ) {
        let session = ASWebAuthenticationSession(
            url: authenticationUrl,
            callbackURLScheme: Self.callbackURLScheme
        ) { [weak self] callbackURL, error in
            guard let self = self else { return }

            Task { @MainActor in
                if let error = error {
                    if (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin {
                        // User cancelled - just reset state
                        self.isAuthenticating = false
                    } else {
                        self.isAuthenticating = false
                        self.errorMessage = "Authentication failed: \(error.localizedDescription)"
                    }
                    return
                }

                if let callbackURL = callbackURL {
                    self.processAuthenticationResult(callbackURL: callbackURL)
                }
            }
        }

        session.presentationContextProvider = presentationContext
        session.prefersEphemeralWebBrowserSession = false

        authSession = session
        session.start()
    }

    /// Process the authentication callback URL
    private func processAuthenticationResult(callbackURL: URL) {
        guard let client = currentClient,
              let apiRootUrl = currentApiRootUrl else {
            isAuthenticating = false
            errorMessage = "Missing authentication parameters"
            return
        }

        do {
            let credentials = try client.credentials(from: callbackURL)

            // Create Basic Auth header
            let authString = "\(credentials.userLogin):\(credentials.password)"
            guard let authData = authString.data(using: .utf8) else {
                isAuthenticating = false
                errorMessage = "Failed to encode credentials"
                return
            }
            let authHeader = "Basic \(authData.base64EncodedString())"

            // Extract site name from URL
            let siteName = URL(string: credentials.siteUrl)?.host ?? credentials.siteUrl

            let configuration = ConfiguredEditor(
                name: siteName,
                siteUrl: credentials.siteUrl,
                siteApiRoot: apiRootUrl,
                authHeader: authHeader
            )

            isAuthenticating = false
            currentApiRootUrl = nil
            currentClient = nil
            onAuthenticationComplete?(configuration)
        } catch {
            isAuthenticating = false
            errorMessage = "Failed to parse credentials: \(error.localizedDescription)"
        }
    }
}
