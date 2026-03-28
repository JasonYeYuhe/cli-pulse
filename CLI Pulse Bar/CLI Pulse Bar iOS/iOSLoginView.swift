import SwiftUI
import AuthenticationServices
import CLIPulseCore

struct iOSLoginView: View {
    @EnvironmentObject var state: AppState
    @State private var email = ""
    @State private var name = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 32) {
                    // Logo area
                    VStack(spacing: 12) {
                        Image(systemName: "waveform.path.ecg")
                            .font(.system(size: 56, weight: .light))
                            .foregroundStyle(PulseTheme.accent)

                        Text("CLI Pulse")
                            .font(.system(size: 28, weight: .bold, design: .rounded))

                        Text("Monitor your AI coding tools")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 40)

                    // Sign in with Apple
                    SignInWithAppleButton(.signIn) { request in
                        request.requestedScopes = [.fullName, .email]
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
                                        fullName: fullName.isEmpty ? nil : fullName,
                                        email: appleIDCredential.email
                                    )
                                }
                            }
                        case .failure(let error):
                            state.lastError = error.localizedDescription
                        }
                    }
                    .signInWithAppleButtonStyle(.white)
                    .frame(height: 50)
                    .padding(.horizontal)

                    if let error = state.lastError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .padding(.horizontal)
                    }

                    // Demo mode divider
                    HStack {
                        Rectangle().frame(height: 1).foregroundStyle(.quaternary)
                        Text("or")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Rectangle().frame(height: 1).foregroundStyle(.quaternary)
                    }
                    .padding(.horizontal)

                    // Email sign in (for App Store review demo account)
                    VStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Email")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            TextField("you@example.com", text: $email)
                                .textFieldStyle(.roundedBorder)
                                .keyboardType(.emailAddress)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Name")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            TextField("Your Name", text: $name)
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                    .padding(.horizontal)

                    Button {
                        Task { await state.signIn(email: email, name: name) }
                    } label: {
                        HStack {
                            if state.isLoading {
                                ProgressView()
                                    .tint(.white)
                            }
                            Text("Sign In with Email")
                                .font(.headline)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(PulseTheme.accent)
                    .disabled(email.isEmpty || name.isEmpty || state.isLoading)
                    .padding(.horizontal)

                    Button {
                        state.enterDemoMode()
                    } label: {
                        HStack {
                            Image(systemName: "play.circle.fill")
                            Text("Try Demo")
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
            .navigationTitle("Welcome")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
