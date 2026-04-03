package com.clipulse.android.data.repository

import com.clipulse.android.data.model.*
import com.clipulse.android.data.remote.SupabaseClient
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow

class DashboardRepository(
    private val supabase: SupabaseClient,
) {
    private val _dashboard = MutableStateFlow<DashboardSummary?>(null)
    val dashboard: StateFlow<DashboardSummary?> = _dashboard

    private val _providers = MutableStateFlow<List<ProviderUsage>>(emptyList())
    val providers: StateFlow<List<ProviderUsage>> = _providers

    private val _sessions = MutableStateFlow<List<SessionRecord>>(emptyList())
    val sessions: StateFlow<List<SessionRecord>> = _sessions

    private val _devices = MutableStateFlow<List<DeviceRecord>>(emptyList())
    val devices: StateFlow<List<DeviceRecord>> = _devices

    private val _alerts = MutableStateFlow<List<AlertRecord>>(emptyList())
    val alerts: StateFlow<List<AlertRecord>> = _alerts

    suspend fun refreshAll() {
        refreshDashboard()
        refreshProviders()
        refreshSessions()
        refreshAlerts()
    }

    suspend fun refreshDashboard() {
        _dashboard.value = supabase.dashboard()
    }

    suspend fun refreshProviders() {
        _providers.value = supabase.providers()
    }

    suspend fun refreshSessions() {
        _sessions.value = supabase.sessions()
    }

    suspend fun refreshDevices() {
        _devices.value = supabase.devices()
    }

    suspend fun refreshAlerts() {
        _alerts.value = supabase.alerts()
    }

    suspend fun acknowledgeAlert(id: String) {
        supabase.acknowledgeAlert(id)
        refreshAlerts()
    }

    suspend fun resolveAlert(id: String) {
        supabase.resolveAlert(id)
        refreshAlerts()
    }

    suspend fun snoozeAlert(id: String, minutes: Int) {
        supabase.snoozeAlert(id, minutes)
        refreshAlerts()
    }
}
