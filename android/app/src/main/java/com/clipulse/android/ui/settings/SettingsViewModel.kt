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
                _state.value = _state.value.copy(
                    tier = tier,
                    settings = settings,
                    isLoading = false,
                    webhookEnabled = settings?.webhookEnabled ?: false,
                    webhookUrl = settings?.webhookUrl,
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
