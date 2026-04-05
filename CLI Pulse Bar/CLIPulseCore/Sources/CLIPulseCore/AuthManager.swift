import Foundation

internal struct AuthSessionState {
    let userName: String
    let userEmail: String
    let isPaired: Bool
}

internal struct OTPFlowState {
    let otpSent: Bool
    let otpEmail: String
    let lastError: String?
}

internal enum RestoreSessionResult {
    case demoMode
    case restored(AuthSessionState)
    case unavailable
    case failed
}

@MainActor
internal final class AuthManager {
    nonisolated static let refreshTokenKeychainKey = "cli_pulse_refresh_token"

    private let api: APIClient
    private let persistTokens: (String, String?) -> Void

    init(api: APIClient, persistTokens: @escaping (String, String?) -> Void) {
        self.api = api
        self.persistTokens = persistTokens
    }

    func sendOTP(email: String) async throws -> String {
        try await api.sendOTP(email: email)
        return email
    }

    func verifyOTP(email: String, code: String) async throws -> AuthSessionState {
        let response = try await api.verifyOTP(email: email, code: code)
        storeAuthTokens(access: response.access_token, refresh: response.refresh_token)
        return authSessionState(from: response)
    }

    func signInWithApple(identityToken: String, nonce: String?, fullName: String?, email: String?) async throws -> AuthSessionState {
        let response = try await api.signInWithApple(identityToken: identityToken, nonce: nonce, fullName: fullName, email: email)
        storeAuthTokens(access: response.access_token, refresh: response.refresh_token)
        return authSessionState(from: response)
    }

    func signInWithPassword(email: String, password: String) async throws -> AuthSessionState {
        let response = try await api.signInWithPassword(email: email, password: password)
        storeAuthTokens(access: response.access_token, refresh: response.refresh_token)
        return authSessionState(from: response)
    }

    func resetOTP() -> OTPFlowState {
        OTPFlowState(otpSent: false, otpEmail: "", lastError: nil)
    }

    func restoreSession(isDemoMode: Bool, accessToken: String, refreshToken: String?) async -> RestoreSessionResult {
        if isDemoMode {
            return .demoMode
        }

        guard !accessToken.isEmpty else {
            return .unavailable
        }

        await api.updateToken(accessToken)
        await api.updateRefreshToken(refreshToken)

        do {
            let response = try await api.me()
            storeAuthTokens(access: response.access_token, refresh: response.refresh_token)
            return .restored(authSessionState(from: response))
        } catch {
            storeAuthTokens(access: "", refresh: nil)
            await api.updateToken(nil)
            await api.updateRefreshToken(nil)
            return .failed
        }
    }

    func signOut(currentAccessToken: String) async {
        // Attempt server-side token revocation
        await api.signOutServer()
        // Only clear tokens if they haven't been replaced by a new sign-in
        let storedToken = KeychainHelper.load(key: AppState.tokenKeychainKey)
        if storedToken == nil || storedToken == currentAccessToken || storedToken?.isEmpty == true {
            storeAuthTokens(access: "", refresh: nil)
        }
    }

    func deleteAccount() async throws {
        try await api.deleteAccount()
        storeAuthTokens(access: "", refresh: nil)
    }

    func signInWithGoogle(idToken: String, name: String?, email: String?) async throws -> AuthSessionState {
        let response = try await api.signInWithGoogle(idToken: idToken, name: name, email: email)
        storeAuthTokens(access: response.access_token, refresh: response.refresh_token)
        return authSessionState(from: response)
    }

    func exchangeOAuthCode(code: String, codeVerifier: String) async throws -> AuthSessionState {
        let response = try await api.exchangeOAuthCode(code: code, codeVerifier: codeVerifier)
        storeAuthTokens(access: response.access_token, refresh: response.refresh_token)
        return authSessionState(from: response)
    }

    func storeAuthTokens(access: String, refresh: String?) {
        persistTokens(access, refresh)
    }

    private func authSessionState(from response: AuthResponse) -> AuthSessionState {
        AuthSessionState(
            userName: response.user.name,
            userEmail: response.user.email,
            isPaired: response.paired
        )
    }
}

extension AppState {
    public func sendOTP(email: String) async {
        isLoading = true
        lastError = nil
        do {
            otpEmail = try await authManager.sendOTP(email: email)
            otpSent = true
        } catch {
            lastError = error.localizedDescription
        }
        isLoading = false
    }

    public func verifyOTP(code: String) async {
        isLoading = true
        lastError = nil
        do {
            let authState = try await authManager.verifyOTP(email: otpEmail, code: code)
            applyAuthenticatedState(authState)
            otpSent = false
            otpEmail = ""
            startRefreshLoop()
            await refreshAll()
        } catch {
            lastError = error.localizedDescription
        }
        isLoading = false
    }

    public func signInWithPassword(email: String, password: String) async {
        isLoading = true
        lastError = nil
        do {
            let authState = try await authManager.signInWithPassword(email: email, password: password)
            applyAuthenticatedState(authState)
            startRefreshLoop()
            await refreshAll()
        } catch {
            lastError = error.localizedDescription
        }
        isLoading = false
    }

    public func resetOTP() {
        let state = authManager.resetOTP()
        otpSent = state.otpSent
        otpEmail = state.otpEmail
        lastError = state.lastError
    }

    public func signInWithApple(identityToken: String, nonce: String? = nil, fullName: String?, email: String?) async {
        isLoading = true
        lastError = nil
        do {
            let authState = try await authManager.signInWithApple(
                identityToken: identityToken,
                nonce: nonce,
                fullName: fullName,
                email: email
            )
            applyAuthenticatedState(authState)
            startRefreshLoop()
            await refreshAll()
        } catch {
            lastError = error.localizedDescription
        }
        isLoading = false
    }

    /// Sign in with a Google ID token (from Google Sign-In SDK or Credential Manager).
    public func signInWithGoogle(idToken: String, name: String?, email: String?) async {
        isLoading = true
        lastError = nil
        do {
            let authState = try await authManager.signInWithGoogle(idToken: idToken, name: name, email: email)
            applyAuthenticatedState(authState)
            startRefreshLoop()
            await refreshAll()
        } catch {
            lastError = error.localizedDescription
        }
        isLoading = false
    }

    /// Exchange an OAuth authorization code (from GitHub ASWebAuthenticationSession) for a session.
    public func exchangeOAuthCode(code: String, codeVerifier: String) async {
        isLoading = true
        lastError = nil
        do {
            let authState = try await authManager.exchangeOAuthCode(code: code, codeVerifier: codeVerifier)
            applyAuthenticatedState(authState)
            startRefreshLoop()
            await refreshAll()
        } catch {
            lastError = error.localizedDescription
        }
        isLoading = false
    }

    /// Build an OAuth URL for a given provider (PKCE flow).
    public func oauthURL(provider: String) async -> (URL, String)? {
        let redirectTo = "clipulse://auth/callback"
        return await api.oauthAuthorizeURL(provider: provider, redirectTo: redirectTo)
    }

    public func generatePairingCode() async {
        isLoading = true
        pairingError = nil
        do {
            pairingInfo = try await api.pairingCode()
        } catch {
            pairingError = error.localizedDescription
        }
        isLoading = false
    }

    public func checkPairingStatus() async {
        isLoading = true
        pairingError = nil
        do {
            let response = try await api.me()
            isPaired = response.paired
            if isPaired {
                pairingInfo = nil
                startRefreshLoop()
                await refreshAll()
            } else {
                pairingError = "Helper hasn't connected yet. Run the command above, then try again."
            }
        } catch {
            pairingError = error.localizedDescription
        }
        isLoading = false
    }

    public func signOut() {
        stopRefreshLoop()
        dataRefreshManager.cancelInFlightRefresh()
        // Capture current token so async logout only clears the right session
        let currentToken = storedToken
        Task { await authManager.signOut(currentAccessToken: currentToken) }
        // Clear local state immediately — don't block on network
        isDemoMode = false
        applySignedOutState()
    }

    public func deleteAccount() async {
        isLoading = true
        lastError = nil
        do {
            try await authManager.deleteAccount()
            isLoading = false
            signOut()
        } catch {
            lastError = error.localizedDescription
            isLoading = false
        }
    }

    public func restoreSession() async {
        switch await authManager.restoreSession(
            isDemoMode: isDemoMode,
            accessToken: storedToken,
            refreshToken: storedRefreshToken
        ) {
        case .demoMode:
            enterDemoMode()
        case .restored(let authState):
            isLoading = true
            applyAuthenticatedState(authState)
            serverOnline = true
            isLoading = false
            await subscriptionManager.updateCurrentEntitlements()
            startRefreshLoop()
            await refreshAll()
        case .unavailable:
            break
        case .failed:
            applySignedOutState()
        }
    }

    var storedRefreshToken: String? {
        KeychainHelper.load(key: AuthManager.refreshTokenKeychainKey)
    }

    nonisolated static func persistAuthTokens(access: String, refresh: String?) {
        if access.isEmpty {
            KeychainHelper.delete(key: Self.tokenKeychainKey)
        } else {
            KeychainHelper.save(key: Self.tokenKeychainKey, value: access)
        }

        if let refresh, !refresh.isEmpty {
            KeychainHelper.save(key: AuthManager.refreshTokenKeychainKey, value: refresh)
        } else {
            KeychainHelper.delete(key: AuthManager.refreshTokenKeychainKey)
        }

        UserDefaults.standard.removeObject(forKey: "cli_pulse_token")
    }

    func applyAuthenticatedState(_ authState: AuthSessionState) {
        userName = authState.userName
        userEmail = authState.userEmail
        isPaired = authState.isPaired
        isAuthenticated = true
    }

    func applySignedOutState() {
        isLoading = false
        isAuthenticated = false
        isPaired = false
        isLocalMode = false
        serverOnline = false
        userName = ""
        userEmail = ""
        dashboard = nil
        providers = []
        sessions = []
        devices = []
        alerts = []
        providerDetails = []
        costSummary = CostSummary()
        tierLimitWarning = nil
        lastRefresh = nil
        locallySupplementedProviders = []
        selectedTab = .overview
    }
}
