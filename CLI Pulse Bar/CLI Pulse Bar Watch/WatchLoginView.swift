import SwiftUI
import CLIPulseCore

struct WatchLoginView: View {
    @EnvironmentObject var state: WatchAppState
    @ObservedObject private var sessionManager = WatchSessionManager.shared
    @State private var email = ""
    @State private var otpCode = ""
    @State private var showManualLogin = false

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                Image(systemName: "waveform.path.ecg")
                    .font(.title2)
                    .foregroundStyle(PulseTheme.accent)

                Text(L10n.auth.title)
                    .font(.headline)

                // Primary: Sign in from iPhone
                if !showManualLogin {
                    VStack(spacing: 8) {
                        if sessionManager.isPhoneReachable {
                            Image(systemName: "iphone.badge.checkmark")
                                .font(.title3)
                                .foregroundStyle(.green)
                            Text("Open CLI Pulse on your iPhone to sign in")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        } else {
                            Image(systemName: "iphone.slash")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                            Text("iPhone not reachable. Make sure CLI Pulse is open on your iPhone, or sign in manually below.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }

                        if let token = sessionManager.pendingAuthToken {
                            Button {
                                state.applyWatchAuth(
                                    token: token,
                                    refreshToken: sessionManager.pendingRefreshToken,
                                    email: sessionManager.pendingAuthEmail ?? "",
                                    name: sessionManager.pendingAuthName ?? ""
                                )
                            } label: {
                                Text("Complete Sign In")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(PulseTheme.accent)
                        }

                        Button {
                            showManualLogin = true
                        } label: {
                            Text("Sign in with email instead")
                                .font(.caption2)
                        }
                    }
                    .padding(.bottom, 4)
                }

                // Fallback: email + OTP
                if showManualLogin {
                    Text(L10n.auth.watchHint)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                if showManualLogin && state.otpSent {
                    // Step 2: Enter code
                    Text(L10n.auth.codeSent)
                        .font(.caption2)
                        .foregroundStyle(.green)

                    TextField(L10n.auth.codePlaceholder, text: $otpCode)
                        #if os(watchOS)
                        .textInputAutocapitalization(.never)
                        #endif

                    Button {
                        Task { await state.verifyOTP(code: otpCode) }
                    } label: {
                        Text(L10n.auth.verifyCode)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(PulseTheme.accent)
                    .disabled(otpCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Button {
                        otpCode = ""
                        state.resetOTP()
                    } label: {
                        Text(L10n.auth.backToEmail)
                            .font(.caption2)
                    }
                } else if showManualLogin {
                    // Step 1: Enter email
                    TextField(L10n.settings.email, text: $email)
                        .textContentType(.emailAddress)
                        #if os(watchOS)
                        .textInputAutocapitalization(.never)
                        #endif

                    Button {
                        Task { await state.sendOTP(email: email) }
                    } label: {
                        Text(L10n.auth.sendCode)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(PulseTheme.accent)
                    .disabled(email.isEmpty || !email.contains("@"))
                }

                if let error = state.lastError {
                    Text(error)
                        .font(.caption2)
                        .foregroundStyle(.red)
                }
            }
            .padding()
        }
    }
}
