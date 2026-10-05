import Foundation
import AuthenticationServices
import WordPressAPI

/// Manages WordPress authentication flow for both self-hosted (Application Passwords)
/// and WordPress.com (OAuth2) sites.
@MainActor
class AuthenticationManager {
    private var authSession: ASWebAuthenticationSession?

    private static let appName = "GutenbergKit iOS Demo App"
    private static let appId = try! WpUuid.parse(input: "00000000-0000-4000-9000-000000000000")
    private static let callbackURLScheme = "gutenbergkit"
    private static let wpcomRedirectUri = "gutenbergkit://wpcom-authorized"

    /// Start the authentication flow for a WordPress site.
    ///
    /// Discovers the site's supported authentication mechanism and presents
    /// the appropriate login flow. Returns the authenticated account on success.
    func startAuthentication(
        siteUrl: String,
        presentationContext: ASWebAuthenticationPresentationContextProviding
    ) async throws -> Account {
        let client = WordPressLoginClient(urlSession: URLSession(configuration: .ephemeral))
        let details = try await client.details(ofSite: siteUrl)

        let application = Application(
            id: Self.appId,
            name: Self.appName,
            callbackUrl: "\(Self.callbackURLScheme)://authorized"
        )

        if details.authentication.loginURL(for: application) != nil {
            return try await authenticateWithApplicationPasswords(
                details: details,
                client: client,
                presentationContext: presentationContext
            )
        } else if details.authentication.oauthEndpoints != nil {
            return try await authenticateWithOAuth(
                siteUrl: siteUrl,
                presentationContext: presentationContext
            )
        } else {
            throw AuthenticationError.noSupportedMethod
        }
    }

    // MARK: - Application Passwords (self-hosted)

    private func authenticateWithApplicationPasswords(
        details: AutoDiscoveryAttemptSuccess,
        client: WordPressLoginClient,
        presentationContext: ASWebAuthenticationPresentationContextProviding
    ) async throws -> Account {
        let application = Application(
            id: Self.appId,
            name: Self.appName,
            callbackUrl: "\(Self.callbackURLScheme)://authorized"
        )

        guard let authUrl = details.authentication.loginURL(for: application) else {
            throw AuthenticationError.failedToBuildURL
        }

        let callbackURL = try await launchWebAuthSession(
            url: authUrl,
            presentationContext: presentationContext
        )

        let credentials = try client.credentials(from: callbackURL)
        let apiRootUrl = details.apiRootUrl.url()

        return .selfHostedSite(
            id: 0,
            domain: credentials.siteUrl,
            username: credentials.userLogin,
            password: credentials.password,
            siteApiRoot: apiRootUrl
        )
    }

    // MARK: - OAuth2 (WordPress.com)

    private func authenticateWithOAuth(
        siteUrl: String,
        presentationContext: ASWebAuthenticationPresentationContextProviding
    ) async throws -> Account {
        let credentials = try Self.loadOAuthCredentials()

        let host = URL(string: siteUrl)?.host ?? siteUrl

        let configuration = WPComApiClient.oauthConfiguration(
            clientId: credentials.clientId,
            clientSecret: credentials.clientSecret,
            redirectUri: Self.wpcomRedirectUri,
            scope: [.global]
        )

        let state = UUID().uuidString

        let authUrl = configuration.buildTokenRequestUrl(
            state: state,
            blog: .slug(value: host)
        )

        let callbackURL = try await launchWebAuthSession(
            url: authUrl.asURL(),
            presentationContext: presentationContext
        )

        let tokenResponse = try configuration.parseTokenResponse(
            url: callbackURL.absoluteString,
            expectedState: state
        )

        let client = WPComApiClient(authentication: .none)
        let requestParams = configuration.buildTokenRequestParameters(code: tokenResponse.code)
        let response = try await client.oauth2.requestToken(params: requestParams)
        let tokenData = response.data

        guard let blogId = tokenData.blogId else {
            throw AuthenticationError.missingBlogId
        }
        let siteApiRoot = "https://public-api.wordpress.com/wp/v2/sites/\(blogId)"

        return .wpCom(
            id: 0,
            username: host,
            token: tokenData.accessToken,
            siteApiRoot: siteApiRoot
        )
    }

    // MARK: - Web Auth Session

    private func launchWebAuthSession(
        url: URL,
        presentationContext: ASWebAuthenticationPresentationContextProviding
    ) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: Self.callbackURLScheme
            ) { callbackURL, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let callbackURL {
                    continuation.resume(returning: callbackURL)
                } else {
                    continuation.resume(throwing: AuthenticationError.noCallback)
                }
            }

            session.presentationContextProvider = presentationContext
            session.prefersEphemeralWebBrowserSession = false

            authSession = session
            session.start()
        }
    }

    // MARK: - OAuth Credentials

    private struct OAuthCredentials: Decodable {
        let clientId: UInt64
        let clientSecret: String

        enum CodingKeys: String, CodingKey {
            case clientId = "client_id"
            case clientSecret = "client_secret"
        }
    }

    /// Loads OAuth credentials from the app bundle.
    /// The credentials file is gitignored and only present for developers who have
    /// configured WP.com OAuth — throwing here is the expected path when it's missing.
    private static func loadOAuthCredentials() throws -> OAuthCredentials {
        guard let url = Bundle.main.url(forResource: "wp_com_oauth_credentials", withExtension: "json") else {
            throw AuthenticationError.oauthCredentialsNotConfigured
        }

        let data = try Data(contentsOf: url)
        let credentials = try JSONDecoder().decode(OAuthCredentials.self, from: data)

        guard credentials.clientId != 0, !credentials.clientSecret.isEmpty else {
            throw AuthenticationError.oauthCredentialsMalformed
        }

        return credentials
    }
}

enum AuthenticationError: LocalizedError {
    case noSupportedMethod
    case failedToBuildURL
    case oauthCredentialsNotConfigured
    case oauthCredentialsMalformed
    case missingBlogId
    case noCallback

    var errorDescription: String? {
        switch self {
        case .noSupportedMethod:
            return "No supported authentication method found for this site."
        case .failedToBuildURL:
            return "Failed to build authentication URL."
        case .oauthCredentialsNotConfigured:
            return "WP.com OAuth credentials not configured. Add wp_com_oauth_credentials.json to the app bundle."
        case .oauthCredentialsMalformed:
            return "wp_com_oauth_credentials.json is present but contains invalid or placeholder values."
        case .missingBlogId:
            return "WordPress.com did not return a blog ID. The site may not be associated with the authenticated account."
        case .noCallback:
            return "Authentication session completed without a callback."
        }
    }
}
