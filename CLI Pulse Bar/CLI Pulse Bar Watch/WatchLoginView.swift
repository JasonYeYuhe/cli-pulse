import SwiftUI
import CLIPulseCore

struct WatchLoginView: View {
    @EnvironmentObject var state: AppState
    @State private var email = ""
    @State private var otpCode = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                Image(systemName: "waveform.path.ecg")
                    .font(.title2)
                    .foregroundStyle(PulseTheme.accent)

                Text(L10n.auth.title)
                    .font(.headline)

                Text(L10n.auth.watchHint)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                if state.otpSent {
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
                    .disabled(otpCode.count < 6)

                    Button {
                        otpCode = ""
                        state.resetOTP()
                    } label: {
                        Text(L10n.auth.backToEmail)
                            .font(.caption2)
                    }
                } else {
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
