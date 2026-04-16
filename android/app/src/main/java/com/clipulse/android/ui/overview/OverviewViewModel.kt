package com.clipulse.android.ui.overview

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.clipulse.android.data.model.*
import com.clipulse.android.data.remote.ApiError
import com.clipulse.android.data.repository.DashboardRepository
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject

data class OverviewUiState(
    val isLoading: Boolean = true,
    val dashboard: DashboardSummary? = null,
    val costForecast: CostForecast? = null,
    val error: String? = null,
)

@HiltViewModel
class OverviewViewModel @Inject constructor(
    private val repository: DashboardRepository,
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
                repository.refreshDashboard()
                repository.refreshDailyUsage(30)
                val forecast = CostForecastEngine.forecast(repository.dailyUsage.value)
                _state.value = _state.value.copy(
                    isLoading = false,
                    dashboard = repository.dashboard.value,
                    costForecast = forecast,
                )
            } catch (e: Exception) {
                _state.value = _state.value.copy(isLoading = false, error = e.message)
            }
        }
    }

    fun getSessions(): List<SessionRecord> = repository.sessions.value
    fun getProviders(): List<ProviderUsage> = repository.providers.value
    fun getAlerts(): List<AlertRecord> = repository.alerts.value
    fun getDailyUsage(): List<DailyUsage> = repository.dailyUsage.value

    private fun startAutoRefresh() {
        viewModelScope.launch {
            while (true) {
                delay(60_000) // Match iOS 60s minimum
                try {
                    repository.refreshDashboard()
                    _state.value = _state.value.copy(dashboard = repository.dashboard.value, error = null)
                } catch (e: ApiError.TokenExpired) {
                    _state.value = _state.value.copy(error = "Session expired. Please sign in again.")
                    break // Stop auto-refresh on auth failure
                } catch (_: Exception) { }
            }
        }
    }
}
