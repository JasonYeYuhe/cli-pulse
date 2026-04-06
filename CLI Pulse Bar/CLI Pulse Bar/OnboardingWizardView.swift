import SwiftUI
import CLIPulseCore

/// Multi-step onboarding wizard shown to new macOS users before authentication.
/// Steps: Welcome → Features → Sign In → Pair Device (optional)
struct OnboardingWizardView: View {
    @EnvironmentObject var state: AppState
    @AppStorage("cli_pulse_onboarding_completed") private var onboardingCompleted = false
    @State private var step = 0
    @State private var email = ""
    @State private var otpCode = ""

    var body: some View {
        VStack(spacing: 0) {
            // Step indicator
            HStack(spacing: 6) {
                ForEach(0..<4) { i in
                    Circle()
                        .fill(i <= step ? PulseTheme.accent : Color.gray.opacity(0.3))
                        .frame(width: 6, height: 6)
                }
            }
            .padding(.top, 12)
            .padding(.bottom, 8)

            // Content
            Group {
                switch step {
                case 0: welcomeStep
                case 1: featuresStep
                case 2: signInStep
                case 3: pairStep
                default: welcomeStep
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.easeInOut(duration: 0.25), value: step)
        }
        .onChange(of: state.isAuthenticated) { isAuth in
            if isAuth && step == 2 {
                step = 3
            }
        }
    }

    // MARK: - Step 0: Welcome

    private var welcomeStep: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 40))
                .foregroundStyle(PulseTheme.accent)

            Text("Welcome to CLI Pulse")
                .font(.title2.weight(.semibold))

            Text("Monitor your AI coding tool usage,\ncosts, and quotas in one place.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Spacer()

            Button {
                step = 1
            } label: {
                Text("Get Started")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(PulseTheme.accent)
            .controlSize(.large)
            .padding(.horizontal, 40)
            .padding(.bottom, 20)
        }
        .padding()
    }

    // MARK: - Step 1: Features

    private var featuresStep: some View {
        VStack(spacing: 12) {
            Text("What CLI Pulse does")
                .font(.headline)
                .padding(.top, 12)

            ScrollView {
                VStack(spacing: 10) {
                    featureCard(icon: "chart.bar.fill", title: "Usage Tracking",
                                desc: "Real-time token usage across Claude, Codex, Gemini, and 14+ providers.")
                    featureCard(icon: "bell.badge.fill", title: "Smart Alerts",
                                desc: "Get notified when quotas run low, costs spike, or sessions fail.")
                    featureCard(icon: "desktopcomputer", title: "Multi-Device",
                                desc: "Monitor all your dev machines from the menu bar.")
                    featureCard(icon: "dollarsign.circle.fill", title: "Cost Estimates",
                                desc: "Track daily and weekly spend per provider.")
                }
                .padding(.horizontal, 16)
            }

            Spacer()

            HStack(spacing: 12) {
                Button("Back") { step = 0 }
                    .buttonStyle(.bordered)

                Button {
                    step = 2
                } label: {
                    Text("Continue")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(PulseTheme.accent)
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 20)
        }
    }

    // MARK: - Step 2: Sign In

    private var signInStep: some View {
        VStack(spacing: 12) {
            Text("Sign In")
                .font(.headline)
                .padding(.top, 12)

            Text("Create an account or sign in to sync your data.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Spacer()

            if state.otpSent {
                Text("Code sent to \(state.otpEmail)")
                    .font(.caption)
                    .foregroundStyle(.green)

                TextField("6-digit code", text: $otpCode)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 200)

                Button {
                    Task { await state.verifyOTP(code: otpCode) }
                } label: {
                    Text("Verify")
                        .frame(width: 200)
                }
                .buttonStyle(.borderedProminent)
                .tint(PulseTheme.accent)
                .disabled(otpCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button("Back to email") {
                    otpCode = ""
                    state.resetOTP()
                }
                .font(.caption)
            } else {
                TextField("Email", text: $email)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 260)

                Button {
                    Task { await state.sendOTP(email: email) }
                } label: {
                    Text("Send Code")
                        .frame(width: 200)
                }
                .buttonStyle(.borderedProminent)
                .tint(PulseTheme.accent)
                .disabled(email.isEmpty || !email.contains("@"))
            }

            if let error = state.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if state.isLoading {
                ProgressView()
                    .controlSize(.small)
            }

            Spacer()

            Button("Back") { step = 1 }
                .buttonStyle(.bordered)
                .padding(.bottom, 20)
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Step 3: Pair Device

    private var pairStep: some View {
        VStack(spacing: 12) {
            Text("Pair Your First Device")
                .font(.headline)
                .padding(.top, 12)

            Image(systemName: "link.badge.plus")
                .font(.system(size: 30))
                .foregroundStyle(PulseTheme.accent)

            Text("Install the CLI Pulse Helper on your development machine to start collecting usage data.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)

            VStack(alignment: .leading, spacing: 8) {
                setupStep(1, "Install: pip install cli-pulse-helper")
                setupStep(2, "Run: cli-pulse-helper pair <your-code>")
                setupStep(3, "Start: cli-pulse-helper daemon")
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)

            Spacer()

            HStack(spacing: 12) {
                Button("Skip for now") {
                    onboardingCompleted = true
                }
                .buttonStyle(.bordered)

                Button {
                    onboardingCompleted = true
                } label: {
                    Text("Done")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(PulseTheme.accent)
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 20)
        }
    }

    // MARK: - Helpers

    private func featureCard(icon: String, title: String, desc: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(PulseTheme.accent)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(desc)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }

    private func setupStep(_ number: Int, _ text: String) -> some View {
        HStack(spacing: 8) {
            Text("\(number)")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 18, height: 18)
                .background(PulseTheme.accent)
                .clipShape(Circle())

            Text(text)
                .font(.caption)
                .foregroundStyle(.primary)
        }
    }
}
