package com.clipulse.android.ui.settings

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.clipulse.android.data.model.SettingsSnapshot
import com.clipulse.android.data.local.CacheDao
import com.clipulse.android.data.remote.SupabaseClient
import com.clipulse.android.data.remote.TokenStore
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject

data class SettingsUiState(
    val userName: String? = null,
    val userEmail: String? = null,
    val tier: String = "free",
    val settings: SettingsSnapshot? = null,
    val isLoading: Boolean = true,
    val deleteError: String? = null,
    val deleteSuccess: Boolean = false,
    val webhookEnabled: Boolean = false,
    val webhookUrl: String? = null,
    val webhookFilterSeverities: List<String> = emptyList(),
    val webhookFilterTypes: List<String> = emptyList(),
    val isDemoMode: Boolean = false,
)

@HiltViewModel
class SettingsViewModel @Inject constructor(
    private val supabase: SupabaseClient,
    private val tokenStore: TokenStore,
    private val cache: CacheDao,
) : ViewModel() {

    private val _state = MutableStateFlow(
        SettingsUiState(
            userName = if (tokenStore.isDemoMode) "Demo User" else tokenStore.userName,
            userEmail = if (tokenStore.isDemoMode) "demo@clipulse.app" else tokenStore.userEmail,
            isDemoMode = tokenStore.isDemoMode,
        )
    )
    val state: StateFlow<SettingsUiState> = _state

    init {
        loadSettings()
    }

    private fun loadSettings() {
        viewModelScope.launch {
            try {
                val tier = supabase.serverTier()
                val settings = supabase.settings()
                val filter = settings?.webhookEventFilter
                _state.value = _state.value.copy(
                    tier = tier,
                    settings = settings,
                    isLoading = false,
                    webhookEnabled = settings?.webhookEnabled ?: false,
                    webhookUrl = settings?.webhookUrl,
                    webhookFilterSeverities = filter?.severities ?: emptyList(),
                    webhookFilterTypes = filter?.types ?: emptyList(),
                )
            } catch (_: Exception) {
                _state.value = _state.value.copy(isLoading = false)
            }
        }
    }

    fun updateSetting(key: String, value: Any) {
        viewModelScope.launch {
            try {
                val patch = org.json.JSONObject().apply { put(key, value) }
                supabase.updateSettings(patch)
                // Reload to reflect server state
                loadSettings()
            } catch (_: Exception) {
                // Silently fail — setting will revert on next load
            }
        }
    }

    fun exitDemoMode() {
        tokenStore.isDemoMode = false
        tokenStore.clear()
    }

    fun testWebhook() {
        viewModelScope.launch {
            try {
                supabase.testWebhook()
            } catch (_: Exception) {
                // Best-effort test
            }
        }
    }

    fun toggleWebhookFilterSeverity(severity: String) {
        val current = _state.value.webhookFilterSeverities.toMutableList()
        if (current.contains(severity)) current.remove(severity) else current.add(severity)
        _state.value = _state.value.copy(webhookFilterSeverities = current)
        pushWebhookFilter(current, _state.value.webhookFilterTypes)
    }

    fun toggleWebhookFilterType(type: String) {
        val current = _state.value.webhookFilterTypes.toMutableList()
        if (current.contains(type)) current.remove(type) else current.add(type)
        _state.value = _state.value.copy(webhookFilterTypes = current)
        pushWebhookFilter(_state.value.webhookFilterSeverities, current)
    }

    private fun pushWebhookFilter(severities: List<String>, types: List<String>) {
        viewModelScope.launch {
            try {
                val filterJson = org.json.JSONObject().apply {
                    if (severities.isNotEmpty()) put("severities", org.json.JSONArray(severities))
                    if (types.isNotEmpty()) put("types", org.json.JSONArray(types))
                }
                val patch = org.json.JSONObject().apply {
                    put("webhook_event_filter", if (severities.isEmpty() && types.isEmpty()) org.json.JSONObject.NULL else filterJson)
                }
                supabase.updateSettings(patch)
            } catch (_: Exception) { }
        }
    }

    fun signOut() {
        viewModelScope.launch {
            try {
                supabase.signOut()
            } catch (_: Exception) {
            } finally {
                // Always clear local cache — prevent data leakage to next user
                cache.clearDashboard()
                cache.clearProviders()
                cache.clearSessions()
                cache.clearAlerts()
                cache.clearDevices()
            }
        }
    }

    fun deleteAccount(onSuccess: () -> Unit) {
        viewModelScope.launch {
            _state.value = _state.value.copy(isLoading = true, deleteError = null)
            try {
                supabase.deleteAccount()
                _state.value = _state.value.copy(isLoading = false, deleteSuccess = true)
                onSuccess()
            } catch (e: Exception) {
                _state.value = _state.value.copy(
                    isLoading = false,
                    deleteError = "Failed to delete account: ${e.message}",
                )
            }
        }
    }
}
