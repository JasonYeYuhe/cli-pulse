package com.clipulse.android.ui.theme

import androidx.compose.ui.graphics.Color
import com.clipulse.android.data.model.ProviderKind

// Brand colors
val PulsePrimary = Color(0xFF6366F1)      // Indigo
val PulseSecondary = Color(0xFF8B5CF6)    // Violet
val PulseBackground = Color(0xFFF8FAFC)
val PulseSurface = Color(0xFFFFFFFF)
val PulseError = Color(0xFFEF4444)
val PulseSuccess = Color(0xFF22C55E)
val PulseWarning = Color(0xFFF59E0B)

// Dark mode
val PulsePrimaryDark = Color(0xFF818CF8)
val PulseBackgroundDark = Color(0xFF0F172A)
val PulseSurfaceDark = Color(0xFF1E293B)

// Provider brand colors
fun providerColor(kind: ProviderKind): Color = when (kind) {
    ProviderKind.Claude -> Color(0xFFD97757)
    ProviderKind.Codex -> Color(0xFF10A37F)
    ProviderKind.Gemini -> Color(0xFF4285F4)
    ProviderKind.Cursor -> Color(0xFF000000)
    ProviderKind.Copilot -> Color(0xFF000000)
    ProviderKind.OpenRouter -> Color(0xFF6366F1)
    ProviderKind.Ollama -> Color(0xFF000000)
    ProviderKind.Warp -> Color(0xFF00D4FF)
    ProviderKind.Kilo -> Color(0xFFFF6B35)
    ProviderKind.Zai -> Color(0xFF4F46E5)
    ProviderKind.MiniMax -> Color(0xFF2563EB)
    ProviderKind.Augment -> Color(0xFF7C3AED)
    ProviderKind.JetBrainsAI -> Color(0xFFFC801D)
    ProviderKind.KimiK2 -> Color(0xFF1D4ED8)
    ProviderKind.Kimi -> Color(0xFF1D4ED8)
    ProviderKind.Amp -> Color(0xFFFBBF24)
    ProviderKind.Alibaba -> Color(0xFFFF6A00)
    ProviderKind.Kiro -> Color(0xFFFF9900)
    ProviderKind.VertexAI -> Color(0xFF4285F4)
    ProviderKind.Perplexity -> Color(0xFF20B2AA)
    ProviderKind.VolcanoEngine -> Color(0xFFFF4500)
    ProviderKind.OpenCode -> Color(0xFF6B7280)
    ProviderKind.Droid -> Color(0xFF6B7280)
    ProviderKind.Antigravity -> Color(0xFF6B7280)
    ProviderKind.Synthetic -> Color(0xFF6B7280)
    ProviderKind.GLM -> Color(0xFF1A73E8)
}

// Severity colors
val SeverityCritical = Color(0xFFEF4444)
val SeverityWarning = Color(0xFFF59E0B)
val SeverityInfo = Color(0xFF3B82F6)
