package com.clipulse.android.data.model

data class ProviderConfig(
    val kind: ProviderKind,
    var isEnabled: Boolean = true,
    var sortOrder: Int = 0,
    var sourceMode: SourceType = SourceType.Auto,
    var accountLabel: String? = null,
    // Secrets loaded at runtime from EncryptedSharedPreferences
    var apiKey: String? = null,
) {
    val id: String get() = kind.displayValue

    val hasCredentials: Boolean
        get() = !apiKey.isNullOrBlank()

    companion object {
        fun defaults(): List<ProviderConfig> =
            ProviderKind.entries.mapIndexed { index, kind ->
                ProviderConfig(kind = kind, sortOrder = index)
            }
    }
}

data class Subscription(
    val tier: String = "free", // free, pro, team
    val status: String = "active",
)
