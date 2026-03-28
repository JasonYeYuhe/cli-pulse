import SwiftUI
import CLIPulseCore

struct WatchLoginView: View {
    @EnvironmentObject var state: AppState
    @State private var email = ""
    @State private var name = ""
    @State private var showNameField = false

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

                TextField(L10n.settings.email, text: $email)
                    .textContentType(.emailAddress)
                    #if os(watchOS)
                    .textInputAutocapitalization(.never)
                    #endif

                if showNameField {
                    TextField(L10n.settings.name, text: $name)
                }

                Button {
                    if !showNameField {
                        showNameField = true
                    } else {
                        Task {
                            await state.signIn(email: email, name: name)
                        }
                    }
                } label: {
                    Text(showNameField ? L10n.settings.signIn : L10n.settings.signInHint)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(PulseTheme.accent)
                .disabled(email.isEmpty || (showNameField && name.isEmpty))
            }
            .padding()
        }
    }
}
