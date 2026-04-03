package com.clipulse.android.ui.overview

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.clipulse.android.data.model.DashboardSummary
import com.clipulse.android.data.remote.SupabaseClient
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject

data class OverviewUiState(
    val isLoading: Boolean = true,
    val dashboard: DashboardSummary? = null,
    val error: String? = null,
)

@HiltViewModel
class OverviewViewModel @Inject constructor(
    private val supabase: SupabaseClient,
) : ViewModel() {

    private val _state = MutableStateFlow(OverviewUiState())
    val state: StateFlow<OverviewUiState> = _state

    init {
        refresh()
        startAutoRefresh()
    }

    fun refresh() {
        viewModelScope.launch {
            _state.value = _state.value.copy(isLoading = true, error = null)
            try {
                val dashboard = supabase.dashboard()
                _state.value = _state.value.copy(isLoading = false, dashboard = dashboard)
            } catch (e: Exception) {
                _state.value = _state.value.copy(isLoading = false, error = e.message)
            }
        }
    }

    private fun startAutoRefresh() {
        viewModelScope.launch {
            while (true) {
                delay(30_000)
                try {
                    val dashboard = supabase.dashboard()
                    _state.value = _state.value.copy(dashboard = dashboard, error = null)
                } catch (_: Exception) { }
            }
        }
    }
}
