package com.clipulse.android.ui.alerts

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.clipulse.android.data.model.AlertRecord
import com.clipulse.android.data.remote.SupabaseClient
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject

data class AlertsUiState(
    val isLoading: Boolean = true,
    val alerts: List<AlertRecord> = emptyList(),
    val error: String? = null,
    val mutationError: String? = null,
)

@HiltViewModel
class AlertsViewModel @Inject constructor(
    private val supabase: SupabaseClient,
) : ViewModel() {

    private val _state = MutableStateFlow(AlertsUiState())
    val state: StateFlow<AlertsUiState> = _state

    init {
        refresh()
    }

    fun refresh() {
        viewModelScope.launch {
            _state.value = _state.value.copy(isLoading = true, error = null)
            try {
                val alerts = supabase.alerts()
                _state.value = _state.value.copy(isLoading = false, alerts = alerts)
            } catch (e: Exception) {
                _state.value = _state.value.copy(isLoading = false, error = e.message)
            }
        }
    }

    fun acknowledge(id: String) {
        viewModelScope.launch {
            _state.value = _state.value.copy(mutationError = null)
            try {
                supabase.acknowledgeAlert(id)
                refresh()
            } catch (e: Exception) {
                _state.value = _state.value.copy(mutationError = "Failed to acknowledge: ${e.message}")
            }
        }
    }

    fun resolve(id: String) {
        viewModelScope.launch {
            _state.value = _state.value.copy(mutationError = null)
            try {
                supabase.resolveAlert(id)
                refresh()
            } catch (e: Exception) {
                _state.value = _state.value.copy(mutationError = "Failed to resolve: ${e.message}")
            }
        }
    }

    fun snooze(id: String, minutes: Int = 60) {
        viewModelScope.launch {
            _state.value = _state.value.copy(mutationError = null)
            try {
                supabase.snoozeAlert(id, minutes)
                refresh()
            } catch (e: Exception) {
                _state.value = _state.value.copy(mutationError = "Failed to snooze: ${e.message}")
            }
        }
    }

    fun clearMutationError() {
        _state.value = _state.value.copy(mutationError = null)
    }
}
