package com.clipulse.android.ui.components

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.AltRoute
import androidx.compose.material.icons.automirrored.filled.ArrowForward
import androidx.compose.material.icons.filled.*
import androidx.compose.ui.graphics.vector.ImageVector
import com.clipulse.android.data.model.ProviderKind

/**
 * UI-layer icon mapping for providers. Keeps ProviderKind free of Compose dependencies.
 */
val ProviderKind.icon: ImageVector
    get() = when (this) {
        ProviderKind.Codex -> Icons.Default.Terminal
        ProviderKind.Gemini -> Icons.Default.AutoAwesome
        ProviderKind.Claude -> Icons.Default.Psychology
        ProviderKind.Cursor -> Icons.Default.NearMe
        ProviderKind.OpenCode -> Icons.Default.Code
        ProviderKind.Droid -> Icons.Default.Memory
        ProviderKind.Antigravity -> Icons.Default.ArrowUpward
        ProviderKind.Copilot -> Icons.Default.Flight
        ProviderKind.Zai -> Icons.Default.Circle
        ProviderKind.MiniMax -> Icons.Default.BarChart
        ProviderKind.Augment -> Icons.Default.ZoomIn
        ProviderKind.JetBrainsAI -> Icons.Default.Build
        ProviderKind.KimiK2 -> Icons.Default.Circle
        ProviderKind.Amp -> Icons.Default.Bolt
        ProviderKind.Synthetic -> Icons.Default.AutoFixHigh
        ProviderKind.Warp -> Icons.AutoMirrored.Filled.ArrowForward
        ProviderKind.Kilo -> Icons.Default.Scale
        ProviderKind.Ollama -> Icons.Default.Computer
        ProviderKind.OpenRouter -> Icons.AutoMirrored.Filled.AltRoute
        ProviderKind.Alibaba -> Icons.Default.Cloud
        ProviderKind.Kimi -> Icons.Default.Circle
        ProviderKind.Kiro -> Icons.Default.Diamond
        ProviderKind.VertexAI -> Icons.Default.Circle
        ProviderKind.Perplexity -> Icons.Default.Search
        ProviderKind.VolcanoEngine -> Icons.Default.LocalFireDepartment
        ProviderKind.GLM -> Icons.Default.Chat
    }
