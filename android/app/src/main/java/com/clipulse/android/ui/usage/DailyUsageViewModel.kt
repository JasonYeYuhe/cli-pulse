package com.clipulse.android.ui.usage

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.clipulse.android.data.model.DailyUsage
import com.clipulse.android.data.repository.DashboardRepository
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject

data class DailyUsageUiState(
    val isLoading: Boolean = true,
    val dailyUsage: List<DailyUsage> = emptyList(),
    val error: String? = null,
)

@HiltViewModel
class DailyUsageViewModel @Inject constructor(
    private val repository: DashboardRepository,
) : ViewModel() {

    private val _state = MutableStateFlow(DailyUsageUiState())
    val state: StateFlow<DailyUsageUiState> = _state

    init {
        refresh()
    }

    fun refresh(days: Int = 30) {
        viewModelScope.launch {
            _state.value = _state.value.copy(isLoading = true, error = null)
            try {
                repository.refreshDailyUsage(days)
                _state.value = _state.value.copy(
                    isLoading = false,
                    dailyUsage = repository.dailyUsage.value,
                )
            } catch (e: Exception) {
                _state.value = _state.value.copy(
                    isLoading = false,
                    error = e.message,
                )
            }
        }
    }

    /** Aggregate cost by date (sum across all providers/models). */
    fun costByDate(): Map<String, Double> =
        _state.value.dailyUsage
            .groupBy { it.date }
            .mapValues { (_, items) -> items.sumOf { it.cost } }
            .toSortedMap()

    /** Aggregate cost by provider (sum across all dates). */
    fun costByProvider(): Map<String, Double> =
        _state.value.dailyUsage
            .groupBy { it.provider }
            .mapValues { (_, items) -> items.sumOf { it.cost } }

    /** Aggregate cost by model (sum across all dates). */
    fun costByModel(): Map<String, Double> =
        _state.value.dailyUsage
            .groupBy { it.model }
            .mapValues { (_, items) -> items.sumOf { it.cost } }
}
