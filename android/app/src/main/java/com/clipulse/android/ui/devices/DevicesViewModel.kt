package com.clipulse.android.ui.devices

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.clipulse.android.data.model.DeviceRecord
import com.clipulse.android.data.remote.SupabaseClient
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject

data class DevicesUiState(
    val isLoading: Boolean = true,
    val devices: List<DeviceRecord> = emptyList(),
    val error: String? = null,
)

@HiltViewModel
class DevicesViewModel @Inject constructor(
    private val supabase: SupabaseClient,
) : ViewModel() {

    private val _state = MutableStateFlow(DevicesUiState())
    val state: StateFlow<DevicesUiState> = _state

    init {
        refresh()
        startAutoRefresh()
    }

    private fun startAutoRefresh() {
        viewModelScope.launch {
            while (true) {
                delay(30_000)
                try {
                    val devices = supabase.devices()
                    _state.value = _state.value.copy(devices = devices, error = null)
                } catch (_: Exception) { }
            }
        }
    }

    fun refresh() {
        viewModelScope.launch {
            _state.value = _state.value.copy(isLoading = true, error = null)
            try {
                val devices = supabase.devices()
                _state.value = _state.value.copy(isLoading = false, devices = devices)
            } catch (e: Exception) {
                _state.value = _state.value.copy(isLoading = false, error = e.message)
            }
        }
    }
}
