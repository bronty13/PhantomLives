// SpotifyAuthService.swift
// Implements Spotify OAuth 2.0 Authorization Code with PKCE flow.
//
// Flow summary:
//  1. startLogin() generates a code verifier + SHA-256 challenge, opens the
//     Spotify authorization page via ASWebAuthenticationSession.
//  2. Spotify redirects to musicjournal://callback?code=...
//  3. exchangeCode() POSTs the code + verifier to get access/refresh tokens.
//  4. Tokens are stored in the macOS Keychain under com.bronty.MusicJournal.
//  5. validAccessToken auto-refreshes via refreshAccessToken() when expired.
//
// The custom URL scheme musicjournal:// is registered in Info.plist and
// the app's entitlements. ASWebAuthenticationSession intercepts it automatically
// so handleCallback() is currently a no-op (kept for fallback compatibility).

import Foundation
import Security
import CryptoKit
import AppKit
import AuthenticationServices

extension Notification.Name {
    /// Posted after a successful token exchange so observers can react to login.
    static let spotifyAuthChanged = Notification.Name("spotifyAuthChanged")
}

/// Manages Spotify OAuth tokens, PKCE login flow, and Keychain persistence.
@MainActor
final class SpotifyAuthService: NSObject, ObservableObject, ASWebAuthenticationPresentationContextProviding {

    // MARK: - Published state

    @Published var isAuthenticated = false
    @Published var displayName: String?
    @Published var loginError: String?

    // MARK: - Configuration

    private let clientId = "8c6eafa2c28d4493b47b9b95178ec52b"
    private let redirectURI = "musicjournal://callback"
    /// Scopes required for reading private/collaborative playlists and user profile.
    private let scopes = "playlist-read-private playlist-read-collaborative user-read-private user-read-email"

    // MARK: - Token storage (in-memory; persisted to Keychain)

    private var accessToken: String?
    private var refreshToken: String?
    /// Expiry is stored 60 s early to avoid using a token in its last seconds.
    private var tokenExpiry: Date?

    override init() {
        super.init()
        loadTokensFromKeychain()
    }

    // MARK: - Token access

    /// Returns a valid access token, refreshing automatically if expired.
    var validAccessToken: String? {
        get async {
            if let token = accessToken, let expiry = tokenExpiry, expiry > Date() {
                return token
            }
            return await refreshAccessToken()
        }
    }

    // MARK: - Login

    /// Opens the Spotify OAuth authorization page in a system web session.
    func startLogin() {
        let verifier = generateCodeVerifier()
        let challenge = generateCodeChallenge(from: verifier)
        let state = UUID().uuidString

        var components = URLComponents(string: "https://accounts.spotify.com/authorize")!
        components.queryItems = [
            .init(name: "client_id", value: clientId),
            .init(name: "response_type", value: "code"),
            .init(name: "redirect_uri", value: redirectURI),
            .init(name: "scope", value: scopes),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "code_challenge", value: challenge),
            .init(name: "state", value: state),
            // show_dialog=true always prompts the account picker, useful during dev.
            .init(name: "show_dialog", value: "true"),
        ]
        guard let authURL = components.url else { return }

        let session = ASWebAuthenticationSession(
            url: authURL,
            callbackURLScheme: "musicjournal"
        ) { [weak self] callbackURL, error in
            guard let self else { return }
            if let error {
                Task { @MainActor in
                    self.loginError = error.localizedDescription
                }
                return
            }
            guard let callbackURL,
                  let code = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?
                    .queryItems?.first(where: { $0.name == "code" })?.value
            else {
                Task { @MainActor in self.loginError = "No code in callback URL" }
                return
            }
            Task { await self.exchangeCode(code, verifier: verifier) }
        }
        session.presentationContextProvider = self
        // prefersEphemeralWebBrowserSession = false lets the user stay logged in
        // to Spotify across app launches.
        session.prefersEphemeralWebBrowserSession = false
        session.start()
    }

    /// URL scheme callback handler — kept for fallback; ASWebAuthenticationSession
    /// intercepts the redirect automatically and does not call this in practice.
    func handleCallback(url: URL) {}

    // MARK: - Logout

    func logout() {
        accessToken = nil
        refreshToken = nil
        tokenExpiry = nil
        displayName = nil
        isAuthenticated = false
        loginError = nil
        clearKeychain()
    }

    // MARK: - ASWebAuthenticationPresentationContextProviding

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            NSApp.windows.first ?? ASPresentationAnchor()
        }
    }

    // MARK: - Token exchange

    private func exchangeCode(_ code: String, verifier: String) async {
        var request = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = [
            "grant_type=authorization_code",
            "code=\(code)",
            "redirect_uri=\(redirectURI)",
            "client_id=\(clientId)",
            "code_verifier=\(verifier)",
        ].joined(separator: "&")
        request.httpBody = body.data(using: .utf8)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                let body = String(data: data, encoding: .utf8) ?? "no body"
                loginError = "Token exchange failed (\(http.statusCode)): \(body)"
                return
            }
            let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)
            storeTokens(tokenResponse)
            await fetchUserProfile()
            NotificationCenter.default.post(name: .spotifyAuthChanged, object: nil)
        } catch {
            loginError = "Token exchange error: \(error.localizedDescription)"
        }
    }

    private func refreshAccessToken() async -> String? {
        guard let refresh = refreshToken else { return nil }
        var request = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = "grant_type=refresh_token&refresh_token=\(refresh)&client_id=\(clientId)"
        request.httpBody = body.data(using: .utf8)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                logout()
                return nil
            }
            let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)
            storeTokens(tokenResponse)
            return accessToken
        } catch {
            logout()
            return nil
        }
    }

    private func fetchUserProfile() async {
        guard let token = await validAccessToken else { return }
        var request = URLRequest(url: URL(string: "https://api.spotify.com/v1/me")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let profile = try JSONDecoder().decode(UserProfile.self, from: data)
            displayName = profile.displayName
            isAuthenticated = true
        } catch {}
    }

    private func storeTokens(_ response: TokenResponse) {
        accessToken = response.accessToken
        // Subtract 60 s so we refresh before actual expiry.
        tokenExpiry = Date().addingTimeInterval(TimeInterval(response.expiresIn - 60))
        if let refresh = response.refreshToken {
            refreshToken = refresh
        }
        saveTokensToKeychain()
    }

    // MARK: - Keychain

    private let keychainService = "com.bronty.MusicJournal"

    private func saveTokensToKeychain() {
        save(key: "accessToken", value: accessToken)
        save(key: "refreshToken", value: refreshToken)
        save(key: "tokenExpiry", value: tokenExpiry.map { String($0.timeIntervalSince1970) })
    }

    private func loadTokensFromKeychain() {
        accessToken = load(key: "accessToken")
        refreshToken = load(key: "refreshToken")
        if let expiryStr = load(key: "tokenExpiry"), let ts = Double(expiryStr) {
            tokenExpiry = Date(timeIntervalSince1970: ts)
        }
        // Treat presence of refresh token as "authenticated" so the UI
        // skips the welcome screen on relaunch even if the access token expired.
        isAuthenticated = refreshToken != nil
    }

    private func clearKeychain() {
        delete(key: "accessToken")
        delete(key: "refreshToken")
        delete(key: "tokenExpiry")
    }

    private func save(key: String, value: String?) {
        guard let value, let data = value.data(using: .utf8) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
        var attrs = query
        attrs[kSecValueData as String] = data
        SecItemAdd(attrs as CFDictionary, nil)
    }

    private func load(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
    }

    // MARK: - PKCE helpers

    /// Generates a cryptographically random 64-byte code verifier (RFC 7636).
    private func generateCodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 64)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// Derives the S256 code challenge from a verifier (Base64url(SHA-256(verifier))).
    private func generateCodeChallenge(from verifier: String) -> String {
        let data = Data(verifier.utf8)
        let hash = SHA256.hash(data: data)
        return Data(hash).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

// MARK: - Private response models

private struct TokenResponse: Decodable {
    let accessToken: String
    let tokenType: String
    let expiresIn: Int
    let refreshToken: String?
    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case expiresIn = "expires_in"
        case refreshToken = "refresh_token"
    }
}

private struct UserProfile: Decodable {
    let displayName: String?
    enum CodingKeys: String, CodingKey { case displayName = "display_name" }
}
