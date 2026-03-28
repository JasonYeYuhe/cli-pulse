import SwiftUI

enum WidgetTheme {
    static let accent = Color(red: 0.36, green: 0.51, blue: 1.0)

    static func providerColor(_ name: String) -> Color {
        switch name {
        case "Codex": return Color(red: 0.36, green: 0.51, blue: 1.0)
        case "Gemini": return Color(red: 0.58, green: 0.39, blue: 0.98)
        case "Claude": return Color(red: 0.90, green: 0.55, blue: 0.20)
        case "Cursor": return Color(red: 0.40, green: 0.80, blue: 0.40)
        case "OpenCode": return Color(red: 0.50, green: 0.50, blue: 0.80)
        case "Droid": return Color(red: 0.70, green: 0.40, blue: 0.70)
        case "Antigravity": return Color(red: 0.85, green: 0.35, blue: 0.55)
        case "Copilot": return Color(red: 0.25, green: 0.60, blue: 0.95)
        case "z.ai": return Color(red: 0.95, green: 0.75, blue: 0.20)
        case "MiniMax": return Color(red: 0.45, green: 0.85, blue: 0.70)
        case "Augment": return Color(red: 0.80, green: 0.30, blue: 0.30)
        case "JetBrains AI": return Color(red: 0.95, green: 0.45, blue: 0.20)
        case "Kimi K2": return Color(red: 0.30, green: 0.70, blue: 0.90)
        case "Amp": return Color(red: 0.60, green: 0.20, blue: 0.90)
        case "Synthetic": return Color(red: 0.75, green: 0.55, blue: 0.95)
        case "Warp": return Color(red: 0.20, green: 0.80, blue: 0.60)
        case "Kilo": return Color(red: 0.50, green: 0.70, blue: 0.40)
        case "Ollama": return Color(red: 0.30, green: 0.80, blue: 0.65)
        case "OpenRouter": return Color(red: 0.20, green: 0.70, blue: 0.80)
        case "Alibaba": return Color(red: 0.95, green: 0.50, blue: 0.15)
        default: return Color.gray
        }
    }

    static func providerGradient(_ name: String) -> LinearGradient {
        let base = providerColor(name)
        return LinearGradient(
            colors: [base, base.opacity(0.7)],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}
