#if os(macOS)
import AuthenticationServices
import CryptoKit
import Foundation

// MARK: - Errors

public enum GeminiOAuthError: LocalizedError {
    case noCallback
    case sessionStartFailed
    case noAuthCode
    case stateMismatch
    case tokenExchangeFailed(Int)
    case tokenRefreshFailed(Int)
    case invalidTokenResponse
    case noRefreshToken
    case clientNotConfigured
    case alreadyInProgress
    case randomGenerationFailed

    public var errorDescription: String? {
        switch self {
        case .noCallback:            return "OAuth callback not received"
        case .sessionStartFailed:    return "Failed to start authentication session"
        case .noAuthCode:            return "No authorization code in callback"
        case .stateMismatch:         return "OAuth state parameter mismatch"
        case .tokenExchangeFailed(let s): return "Token exchange failed (HTTP \(s))"
        case .tokenRefreshFailed(let s):  return "Token refresh failed (HTTP \(s))"
        case .invalidTokenResponse:  return "Invalid token response from Google"
        case .noRefreshToken:        return "No refresh token available"
        case .clientNotConfigured:   return "OAuth client ID not configured — see docs/GEMINI_OAUTH_SETUP.md"
        case .alreadyInProgress:     return "OAuth flow already in progress"
        case .randomGenerationFailed: return "Secure random generation failed"
        }
    }
}

// MARK: - Stored token container

public struct GeminiStoredTokens: Sendable {
    public let accessToken: String
    public let refreshToken: String?
    public let expiry: Date?

    public var isExpired: Bool {
        guard let exp = expiry else { return true }
        return exp < Date()
    }
}

// MARK: - Manager

/// Manages CLI Pulse's own Google OAuth2 flow for Gemini quota access.
///
/// Flow: ASWebAuthenticationSession + PKCE (public client, no client_secret).
/// Tokens: Keychain (primary) + `~/.config/clipulse/gemini_tokens.json` (Python helper,
///   access_token only — refresh_token stays in Keychain).
public final class GeminiOAuthManager: NSObject, @unchecked Sendable {

    // ── Configuration ────────────────────────────────────────────────
    // Replace after creating an iOS-type OAuth client in Google Cloud Console.
    // See docs/GEMINI_OAUTH_SETUP.md for instructions.
    public static let clientID = "REPLACE_WITH_YOUR_CLIENT_ID.apps.googleusercontent.com"

    public static var callbackScheme: String {
        clientID.split(separator: ".").reversed().joined(separator: ".")
    }
    public static var redirectURI: String {
        "\(callbackScheme):/oauthredirect"
    }

    private static let scope = "https://www.googleapis.com/auth/cloud-platform"
    private static let authEndpoint = "https://accounts.google.com/o/oauth2/v2/auth"
    private static let tokenEndpoint = "https://oauth2.googleapis.com/token"

    // ── Keychain keys ────────────────────────────────────────────────
    private static let accessGroup = "group.yyh.CLI-Pulse"
    static let keyAccessToken  = "gemini.oauth.access_token"
    static let keyRefreshToken = "gemini.oauth.refresh_token"
    static let keyExpiry       = "gemini.oauth.expiry"

    // ── Shared file for Python helper ────────────────────────────────
    private static var sharedDir: String {
        (NSHomeDirectory() as NSString).appendingPathComponent(".config/clipulse")
    }
    static var sharedTokenFilePath: String {
        (sharedDir as NSString).appendingPathComponent("gemini_tokens.json")
    }

    // ── Singleton ────────────────────────────────────────────────────
    public static let shared = GeminiOAuthManager()

    private var authSession: ASWebAuthenticationSession?
    private override init() { super.init() }

    // MARK: - Public API

    /// Whether CLI Pulse has its own Gemini OAuth tokens in Keychain.
    public var isConnected: Bool { loadTokens() != nil }

    /// Start the full OAuth2 authorization flow (opens browser sheet).
    /// Must be called on the main actor.
    @MainActor
    public func authorize() async throws -> (accessToken: String, refreshToken: String) {
        guard Self.clientID != "REPLACE_WITH_YOUR_CLIENT_ID.apps.googleusercontent.com" else {
            throw GeminiOAuthError.clientNotConfigured
        }
        // Prevent concurrent auth sessions
        guard authSession == nil else {
            throw GeminiOAuthError.alreadyInProgress
        }

        let verifier  = try Self.generateCodeVerifier()
        let challenge = Self.generateCodeChallenge(from: verifier)
        let state     = UUID().uuidString

        var comps = URLComponents(string: Self.authEndpoint)!
        comps.queryItems = [
            .init(name: "client_id",             value: Self.clientID),
            .init(name: "redirect_uri",          value: Self.redirectURI),
            .init(name: "response_type",         value: "code"),
            .init(name: "scope",                 value: Self.scope),
            .init(name: "state",                 value: state),
            .init(name: "code_challenge",        value: challenge),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "access_type",           value: "offline"),
            .init(name: "prompt",                value: "consent"),
        ]

        let authURL = comps.url!

        defer { self.authSession = nil }

        let callbackURL: URL = try await withCheckedThrowingContinuation { cont in
            let session = ASWebAuthenticationSession(
                url: authURL,
                callbackURLScheme: Self.callbackScheme
            ) { url, error in
                if let error { cont.resume(throwing: error) }
                else if let url { cont.resume(returning: url) }
                else { cont.resume(throwing: GeminiOAuthError.noCallback) }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            self.authSession = session
            if !session.start() {
                self.authSession = nil
                cont.resume(throwing: GeminiOAuthError.sessionStartFailed)
            }
        }

        // Parse callback
        guard let items = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?.queryItems,
              let code = items.first(where: { $0.name == "code" })?.value else {
            throw GeminiOAuthError.noAuthCode
        }
        guard items.first(where: { $0.name == "state" })?.value == state else {
            throw GeminiOAuthError.stateMismatch
        }

        // Exchange code → tokens
        let tokens = try await exchangeCode(code, codeVerifier: verifier)

        // Require a refresh token on initial connect
        let rt = tokens.refresh.isEmpty
            ? KeychainHelper.load(key: Self.keyRefreshToken, accessGroup: Self.accessGroup) ?? ""
            : tokens.refresh
        storeTokens(access: tokens.access, refresh: rt, expiresIn: tokens.expiresIn)
        return (tokens.access, rt)
    }

    /// Refresh the stored access token using the refresh token.
    public func refreshAccessToken() async throws -> String {
        guard let rt = KeychainHelper.load(key: Self.keyRefreshToken, accessGroup: Self.accessGroup),
              !rt.isEmpty else {
            throw GeminiOAuthError.noRefreshToken
        }

        let body = Self.formEncode([
            "client_id":     Self.clientID,
            "grant_type":    "refresh_token",
            "refresh_token": rt,
        ])

        var req = URLRequest(url: URL(string: Self.tokenEndpoint)!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 15
        req.httpBody = body.data(using: .utf8)

        let (data, resp) = try await URLSession.shared.data(for: req)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200...299).contains(status) else {
            // Clear tokens on permanent auth errors so isConnected reflects reality
            if (400...401).contains(status) {
                clearTokens()
            }
            throw GeminiOAuthError.tokenRefreshFailed(status)
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let at = json["access_token"] as? String else {
            throw GeminiOAuthError.invalidTokenResponse
        }

        let expiresIn = (json["expires_in"] as? NSNumber)?.doubleValue ?? 3600
        let newRT = json["refresh_token"] as? String ?? rt

        storeTokens(access: at, refresh: newRT, expiresIn: expiresIn)
        return at
    }

    /// Load current tokens from Keychain. Returns nil if not present.
    public func loadTokens() -> GeminiStoredTokens? {
        guard let at = KeychainHelper.load(key: Self.keyAccessToken, accessGroup: Self.accessGroup),
              !at.isEmpty else { return nil }
        let rt = KeychainHelper.load(key: Self.keyRefreshToken, accessGroup: Self.accessGroup)
        var expiry: Date?
        if let s = KeychainHelper.load(key: Self.keyExpiry, accessGroup: Self.accessGroup),
           let ts = Double(s) {
            expiry = Date(timeIntervalSince1970: ts)
        }
        return GeminiStoredTokens(accessToken: at, refreshToken: rt, expiry: expiry)
    }

    /// Remove all stored tokens (Keychain + shared file).
    public func clearTokens() {
        KeychainHelper.delete(key: Self.keyAccessToken,  accessGroup: Self.accessGroup)
        KeychainHelper.delete(key: Self.keyRefreshToken, accessGroup: Self.accessGroup)
        KeychainHelper.delete(key: Self.keyExpiry,       accessGroup: Self.accessGroup)
        try? FileManager.default.removeItem(atPath: Self.sharedTokenFilePath)
    }

    // MARK: - Private helpers

    private struct TokenBundle {
        let access: String
        let refresh: String
        let expiresIn: TimeInterval
    }

    private func exchangeCode(_ code: String, codeVerifier: String) async throws -> TokenBundle {
        let body = Self.formEncode([
            "client_id":     Self.clientID,
            "code":          code,
            "code_verifier": codeVerifier,
            "grant_type":    "authorization_code",
            "redirect_uri":  Self.redirectURI,
        ])

        var req = URLRequest(url: URL(string: Self.tokenEndpoint)!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 15
        req.httpBody = body.data(using: .utf8)

        let (data, resp) = try await URLSession.shared.data(for: req)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200...299).contains(status) else {
            throw GeminiOAuthError.tokenExchangeFailed(status)
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let at = json["access_token"] as? String else {
            throw GeminiOAuthError.invalidTokenResponse
        }

        return TokenBundle(
            access:    at,
            refresh:   json["refresh_token"] as? String ?? "",
            expiresIn: (json["expires_in"] as? NSNumber)?.doubleValue ?? 3600
        )
    }

    private func storeTokens(access: String, refresh: String, expiresIn: TimeInterval) {
        let group = Self.accessGroup
        KeychainHelper.save(key: Self.keyAccessToken,  value: access,  accessGroup: group)
        if !refresh.isEmpty {
            KeychainHelper.save(key: Self.keyRefreshToken, value: refresh, accessGroup: group)
        }
        let exp = String(Date().addingTimeInterval(expiresIn).timeIntervalSince1970)
        KeychainHelper.save(key: Self.keyExpiry, value: exp, accessGroup: group)

        persistSharedFile(access: access, expiresIn: expiresIn)
    }

    /// Write access_token + client_id to a JSON file the Python helper can read.
    /// Refresh token is NOT written here — it stays in Keychain only.
    private func persistSharedFile(access: String, expiresIn: TimeInterval) {
        try? FileManager.default.createDirectory(atPath: Self.sharedDir,
                                                  withIntermediateDirectories: true)
        let expMs = Int64((Date().timeIntervalSince1970 + expiresIn) * 1000)
        let dict: [String: Any] = [
            "access_token":  access,
            "expiry_date":   expMs,
            "client_id":     Self.clientID,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: dict, options: .prettyPrinted) else { return }
        let url = URL(fileURLWithPath: Self.sharedTokenFilePath)
        try? data.write(to: url, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    // MARK: - PKCE

    private static func generateCodeVerifier() throws -> String {
        var buf = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, buf.count, &buf)
        guard status == errSecSuccess else {
            throw GeminiOAuthError.randomGenerationFailed
        }
        return Data(buf).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func generateCodeChallenge(from verifier: String) -> String {
        let hash = SHA256.hash(data: Data(verifier.utf8))
        return Data(hash).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    // MARK: - URL encoding

    private static func formEncode(_ params: [String: String]) -> String {
        params.map { k, v in
            let ek = k.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? k
            let ev = v.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? v
            return "\(ek)=\(ev)"
        }.joined(separator: "&")
    }
}

// MARK: - Presentation context

extension GeminiOAuthManager: ASWebAuthenticationPresentationContextProviding {
    @MainActor
    public func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        NSApplication.shared.windows.first(where: \.isKeyWindow)
            ?? NSApplication.shared.windows.first
            ?? ASPresentationAnchor()
    }
}
#endif
