import SwiftUI
import AuthenticationServices
import CryptoKit
import CLIPulseCore
import os

struct iOSLoginView: View {
    @EnvironmentObject var state: AppState
    @State private var email = ""
    @State private var password = ""
    @State private var otpCode = ""
    @State private var currentNonce: String?
    @FocusState private var codeFieldFocused: Bool

    private func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        var randomBytes = [UInt8](repeating: 0, count: length)
        let errorCode = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)
        if errorCode != errSecSuccess { fatalError("Unable to generate nonce.") }
        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        return String(randomBytes.map { charset[Int($0) % charset.count] })
    }

    private func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashed = SHA256.hash(data: inputData)
        return hashed.compactMap { String(format: "%02x", $0) }.joined()
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 32) {
                    // Logo area
                    VStack(spacing: 12) {
                        Image(systemName: "waveform.path.ecg")
                            .font(.system(size: 56, weight: .light))
                            .foregroundStyle(PulseTheme.accent)

                        Text(L10n.auth.title)
                            .font(.system(size: 28, weight: .bold, design: .rounded))

                        Text(L10n.auth.subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 40)

                    // Sign in with Apple
                    SignInWithAppleButton(.signIn) { request in
                        let nonce = randomNonceString()
                        currentNonce = nonce
                        request.requestedScopes = [.fullName, .email]
                        request.nonce = sha256(nonce)
                    } onCompletion: { result in
                        switch result {
                        case .success(let authorization):
                            if let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential,
                               let identityTokenData = appleIDCredential.identityToken,
                               let identityToken = String(data: identityTokenData, encoding: .utf8) {
                                let fullName = [appleIDCredential.fullName?.givenName, appleIDCredential.fullName?.familyName]
                                    .compactMap { $0 }
                                    .joined(separator: " ")
                                Task {
                                    await state.signInWithApple(
                                        identityToken: identityToken,
                                        nonce: currentNonce,
                                        fullName: fullName.isEmpty ? nil : fullName,
                                        email: appleIDCredential.email
                                    )
                                }
                            }
                        case .failure(let error):
                            state.lastError = error.localizedDescription
                        }
                    }
                    .signInWithAppleButtonStyle(.black)
                    .frame(height: 50)
                    .padding(.horizontal)

                    // Sign in with Google (via Supabase OAuth)
                    Button {
                        signInWithProvider("google")
                    } label: {
                        HStack {
                            Image(systemName: "globe")
                            Text("Sign in with Google")
                                .font(.headline)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                    .padding(.horizontal)

                    // Sign in with GitHub
                    Button {
                        signInWithProvider("github")
                    } label: {
                        HStack {
                            Image(systemName: "chevron.left.forwardslash.chevron.right")
                            Text("Sign in with GitHub")
                                .font(.headline)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.primary)
                    .padding(.horizontal)

                    if let error = state.lastError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .padding(.horizontal)
                    }

                    // Divider
                    HStack {
                        Rectangle().frame(height: 1).foregroundStyle(.quaternary)
                        Text(L10n.auth.or)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Rectangle().frame(height: 1).foregroundStyle(.quaternary)
                    }
                    .padding(.horizontal)

                    // OTP Email flow
                    if state.otpSent {
                        // Step 2: Enter verification code
                        otpVerifyView
                    } else {
                        // Step 1: Enter email
                        emailEntryView
                    }

                    // Demo mode
                    Button {
                        state.enterDemoMode()
                    } label: {
                        HStack {
                            Image(systemName: "play.circle.fill")
                            Text(L10n.auth.tryDemo)
                                .font(.headline)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                    }
                    .buttonStyle(.bordered)
                    .tint(.secondary)
                    .padding(.horizontal)
                }
            }
            .navigationTitle(L10n.auth.welcome)
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                email = ""
                password = ""
                otpCode = ""
                state.lastError = nil
            }
            .onChange(of: state.isAuthenticated) { _, isAuth in
                if !isAuth {
                    email = ""
                    password = ""
                    otpCode = ""
                    state.resetOTP()
                }
            }
        }
    }

    // MARK: - OAuth Sign-In (Google / GitHub) via ASWebAuthenticationSession + PKCE

    private func signInWithProvider(_ provider: String) {
        Task {
            guard let (authURL, codeVerifier) = await state.oauthURL(provider: provider) else {
                state.lastError = "Failed to build \(provider) authorization URL"
                return
            }
            let webSession = ASWebAuthenticationSession(
                url: authURL,
                callbackURLScheme: "clipulse"
            ) { callbackURL, error in
                if let error {
                    if (error as NSError).code == ASWebAuthenticationSessionError.canceledLogin.rawValue {
                        return
                    }
                    Task { @MainActor in self.state.lastError = error.localizedDescription }
                    return
                }
                guard let callbackURL,
                      let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
                      let code = components.queryItems?.first(where: { $0.name == "code" })?.value else {
                    Task { @MainActor in self.state.lastError = "OAuth sign-in failed: no authorization code" }
                    return
                }
                Task {
                    await self.state.exchangeOAuthCode(code: code, codeVerifier: codeVerifier)
                }
            }
            webSession.prefersEphemeralWebBrowserSession = false
            webSession.start()
        }
    }

    // MARK: - Step 1: Email Entry

    private var emailEntryView: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.settings.email)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField(L10n.login.emailPlaceholder, text: $email)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.emailAddress)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            }
            .padding(.horizontal)

            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.auth.passwordOptional)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                SecureField(L10n.auth.passwordPlaceholder, text: $password)
                    .textFieldStyle(.roundedBorder)
            }
            .padding(.horizontal)

            Button {
                Task {
                    if !password.isEmpty {
                        await state.signInWithPassword(email: email, password: password)
                    } else {
                        await state.sendOTP(email: email)
                    }
                }
            } label: {
                HStack {
                    if state.isLoading {
                        ProgressView()
                            .tint(.white)
                    }
                    Text(password.isEmpty ? L10n.auth.sendCode : L10n.settings.signIn)
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .tint(PulseTheme.accent)
            .disabled(email.isEmpty || !email.contains("@") || state.isLoading)
            .padding(.horizontal)
        }
    }

    // MARK: - Step 2: OTP Verification

    private var otpVerifyView: some View {
        VStack(spacing: 16) {
            // Success indicator
            VStack(spacing: 8) {
                Image(systemName: "envelope.badge.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(PulseTheme.accent)

                Text(L10n.auth.codeSentTo(state.otpEmail))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.auth.enterCode)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField(L10n.auth.codePlaceholder, text: $otpCode)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.center)
                    .font(.system(size: 24, weight: .semibold, design: .monospaced))
                    .focused($codeFieldFocused)
                    .onAppear { codeFieldFocused = true }
            }
            .padding(.horizontal)

            Button {
                Task { await state.verifyOTP(code: otpCode) }
            } label: {
                HStack {
                    if state.isLoading {
                        ProgressView()
                            .tint(.white)
                    }
                    Text(L10n.auth.verifyCode)
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .tint(PulseTheme.accent)
            .disabled(otpCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || state.isLoading)
            .padding(.horizontal)

            HStack(spacing: 16) {
                Button {
                    otpCode = ""
                    state.resetOTP()
                } label: {
                    Text(L10n.auth.backToEmail)
                        .font(.subheadline)
                }

                Button {
                    otpCode = ""
                    Task { await state.sendOTP(email: state.otpEmail) }
                } label: {
                    Text(L10n.auth.resendCode)
                        .font(.subheadline)
                }
            }
            .foregroundStyle(PulseTheme.accent)
        }
    }
}
