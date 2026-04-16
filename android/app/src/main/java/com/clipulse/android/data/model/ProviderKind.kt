package com.clipulse.android.data.model

enum class ProviderKind(val displayValue: String) {
    Codex("Codex"),
    Gemini("Gemini"),
    Claude("Claude"),
    Cursor("Cursor"),
    OpenCode("OpenCode"),
    Droid("Droid"),
    Antigravity("Antigravity"),
    Copilot("Copilot"),
    Zai("z.ai"),
    MiniMax("MiniMax"),
    Augment("Augment"),
    JetBrainsAI("JetBrains AI"),
    KimiK2("Kimi K2"),
    Amp("Amp"),
    Synthetic("Synthetic"),
    Warp("Warp"),
    Kilo("Kilo"),
    Ollama("Ollama"),
    OpenRouter("OpenRouter"),
    Alibaba("Alibaba"),
    Kimi("Kimi"),
    Kiro("Kiro"),
    VertexAI("Vertex AI"),
    Perplexity("Perplexity"),
    VolcanoEngine("Volcano Engine"),
    GLM("GLM");

    companion object {
        fun fromString(value: String): ProviderKind? =
            entries.find { it.displayValue == value }
    }
}

enum class SessionStatus(val displayValue: String) {
    Running("Running"),
    Idle("Idle"),
    Failed("Failed"),
    Syncing("Syncing");

    companion object {
        fun fromString(value: String): SessionStatus? =
            entries.find { it.displayValue == value }
    }
}

enum class DeviceStatus(val displayValue: String) {
    Online("Online"),
    Degraded("Degraded"),
    Offline("Offline");

    companion object {
        fun fromString(value: String): DeviceStatus? =
            entries.find { it.displayValue == value }
    }
}

enum class AlertType(val displayValue: String) {
    QuotaLow("Quota Low"),
    UsageSpike("Usage Spike"),
    HelperOffline("Helper Offline"),
    SyncFailed("Sync Failed"),
    AuthExpired("Auth Expired"),
    SessionFailed("Session Failed"),
    SessionTooLong("Session Too Long"),
    ProjectBudgetExceeded("Project Budget Exceeded"),
    CostSpike("Cost Spike"),
    ErrorRateSpike("Error Rate Spike"),
    QuotaCritical("Quota Critical");

    companion object {
        fun fromString(value: String): AlertType? =
            entries.find { it.displayValue == value }
    }
}

enum class AlertSeverity(val displayValue: String) {
    Critical("Critical"),
    Warning("Warning"),
    Info("Info");

    companion object {
        fun fromString(value: String): AlertSeverity? =
            entries.find { it.displayValue == value }
    }
}

enum class CostStatus(val displayValue: String) {
    Exact("Exact"),
    Estimated("Estimated"),
    Unavailable("Unavailable");
}

enum class SourceType(val displayValue: String) {
    Auto("auto"),
    Web("web"),
    Cli("cli"),
    OAuth("oauth"),
    Api("api"),
    Local("local"),
    Merged("merged");
}

enum class ProviderCategory {
    Cloud, Local, Aggregator, Ide
}
