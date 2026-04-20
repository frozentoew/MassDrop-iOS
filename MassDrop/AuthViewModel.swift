import Foundation
import Combine
import GoogleSignIn
import AuthenticationServices

@MainActor
class AuthViewModel: ObservableObject {
    @Published var isAuthenticated = false
    @Published var isLoading = false
    @Published var error: String?
    
    private var tokens: AuthTokens?
    private let keychainKey = "authTokens"
    private let pkceHelper = PKCEHelper()
    private var pendingState: String?
    
    init() {
        loadSavedTokens()
    }
    
    func signIn() async {
        isLoading = true
        error = nil
        
        guard let presentingViewController = await getRootViewController() else {
            error = "Unable to get view controller"
            isLoading = false
            return
        }
        
        do {
            // Step 1: Generate PKCE verifier — challenge is handled internally by GIDSignIn
            let codeVerifier = try pkceHelper.generateCodeVerifier()

            // Step 2: Fetch a server-issued state token BEFORE starting the OAuth flow.
            // This provides CSRF protection: the backend will reject any exchange
            // request that doesn't present a state it originally issued.
            let state = try await APIManager.shared.getAuthState()
            pendingState = state

            // Get Client IDs from Info.plist safely
            guard let clientID = Bundle.main.object(forInfoDictionaryKey: "GIDClientID") as? String,
                  let serverClientID = Bundle.main.object(forInfoDictionaryKey: "GIDServerClientID") as? String else {
                error = "Missing Google Client IDs in Info.plist"
                isLoading = false
                return
            }

            guard !clientID.hasPrefix("TODO_"), !serverClientID.hasPrefix("TODO_") else {
                error = "Google Client IDs have not been configured. Update Info.plist before use."
                isLoading = false
                return
            }

            // Configure Google Sign-In with PKCE
            GIDSignIn.sharedInstance.configuration = GIDConfiguration(
                clientID: clientID,
                serverClientID: serverClientID
            )

            // Request YouTube scope
            let additionalScopes = ["https://www.googleapis.com/auth/youtube.force-ssl"]

            // Step 3: Complete Google sign-in (returns serverAuthCode directly via SDK)
            let result = try await GIDSignIn.sharedInstance.signIn(
                withPresenting: presentingViewController,
                hint: nil,
                additionalScopes: additionalScopes
            )

            guard let serverAuthCode = result.serverAuthCode else {
                error = "Failed to get authorization code"
                isLoading = false
                return
            }

            // Step 4: Exchange code — server validates the state we obtained in Step 2
            let apiTokens = try await APIManager.shared.exchangeAuthCode(
                serverAuthCode,
                state: state,
                codeVerifier: codeVerifier
            )

            let tokens = AuthTokens(
                appToken: apiTokens.appToken,
                refreshToken: apiTokens.refreshToken,
                expiryDate: apiTokens.expiryDate,
                refreshTokenExpiry: Date().timeIntervalSince1970 + 7 * 24 * 3600
            )

            self.tokens = tokens
            saveTokens(tokens)
            pendingState = nil
            isAuthenticated = true

        } catch let apiError as APIError {
            self.error = apiError.errorDescription
        } catch {
            #if DEBUG
            self.error = "Authentication failed: \(error.localizedDescription)"
            #else
            self.error = "Authentication failed. Please try again."
            #endif
        }
        
        isLoading = false
    }

    
    func signOut() {
        GIDSignIn.sharedInstance.signOut()
        KeychainHelper.shared.clearAll()
        tokens = nil
        isAuthenticated = false
    }
    
    // Get valid app token (handles auto-refresh of JWT)
    func getAppToken() async throws -> String {
        guard var tokens = self.tokens else {
            throw APIError.authenticationFailed
        }

        // Check if app JWT is about to expire
        let expiryTime = Date(timeIntervalSince1970: tokens.expiryDate)
        let now = Date()

        if now >= expiryTime.addingTimeInterval(-60) { // Refresh 1 min before expiry
            let refreshed = try await APIManager.shared.refreshTokens(
                refreshToken: tokens.refreshToken
            )

            tokens = AuthTokens(
                appToken: refreshed.appToken,
                refreshToken: refreshed.refreshToken,
                expiryDate: refreshed.expiryDate,
                refreshTokenExpiry: Date().timeIntervalSince1970 + 7 * 24 * 3600
            )

            self.tokens = tokens
            saveTokens(tokens)
        }

        return tokens.appToken
    }
    
    // The backend host we expect Universal Link callbacks to originate from.
    // Jailbroken devices can bypass OS-level AASA validation, so we enforce
    // the host explicitly here as an additional defence-in-depth check.
    private let expectedCallbackHost = "youtubeunsubscriber-production.up.railway.app"

    // Handle Universal Link callback
    func handleUniversalLink(url: URL) {
        // Verify the callback URL comes from our backend host before touching its contents.
        guard let host = url.host, host == expectedCallbackHost else {
            error = "Invalid callback URL"
            return
        }

        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: true),
              let code = components.queryItems?.first(where: { $0.name == "code" })?.value,
              let state = components.queryItems?.first(where: { $0.name == "state" })?.value else {
            error = "Invalid callback URL"
            return
        }

        // Validate state matches what we sent to prevent CSRF
        guard state == pendingState else {
            error = "Invalid state parameter — possible CSRF attack"
            pendingState = nil
            return
        }

        Task {
            await exchangeCodeForTokens(code: code, state: state)
        }
    }
    
    private func exchangeCodeForTokens(code: String, state: String) async {
        isLoading = true
        
        do {
            let codeVerifier = pkceHelper.getAndClearCodeVerifier()
            
            let apiTokens = try await APIManager.shared.exchangeAuthCode(
                code,
                state: state,
                codeVerifier: codeVerifier
            )

            let tokens = AuthTokens(
                appToken: apiTokens.appToken,
                refreshToken: apiTokens.refreshToken,
                expiryDate: apiTokens.expiryDate,
                refreshTokenExpiry: Date().timeIntervalSince1970 + 7 * 24 * 3600
            )

            self.tokens = tokens
            saveTokens(tokens)
            isAuthenticated = true
            
        } catch {
            #if DEBUG
            self.error = "Token exchange failed: \(error.localizedDescription)"
            #else
            self.error = "Token exchange failed. Please try again."
            #endif
        }
        
        isLoading = false
    }
    
    private func saveTokens(_ tokens: AuthTokens) {
        guard let data = try? JSONEncoder().encode(tokens) else {
            error = "Failed to encode session tokens. Your session may not persist after the app is closed."
            return
        }
        if !KeychainHelper.shared.save(data, forKey: keychainKey) {
            error = "Failed to save session tokens to secure storage. Your session may not persist after the app is closed."
        }
    }
    
    private func loadSavedTokens() {
        guard let data = KeychainHelper.shared.load(forKey: keychainKey),
              let tokens = try? JSONDecoder().decode(AuthTokens.self, from: data) else {
            return
        }

        // Discard tokens if the refresh token has expired.
        // refreshTokenExpiry is the exact Unix timestamp recorded when the token
        // was issued (now + 7d), not an approximation derived from the access token.
        if Date().timeIntervalSince1970 >= tokens.refreshTokenExpiry {
            KeychainHelper.shared.clearAll()
            return
        }

        self.tokens = tokens
        self.isAuthenticated = true
    }
    
    private func getRootViewController() async -> UIViewController? {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootViewController = windowScene.windows.first?.rootViewController else {
            return nil
        }
        return rootViewController
    }
}
