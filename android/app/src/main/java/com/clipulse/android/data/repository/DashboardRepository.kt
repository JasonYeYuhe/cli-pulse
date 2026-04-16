package com.clipulse.android.data.repository

import com.clipulse.android.data.DemoDataProvider
import com.clipulse.android.data.local.*
import com.clipulse.android.data.model.*
import com.clipulse.android.data.remote.SupabaseClient
import com.clipulse.android.data.remote.TokenStore
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch
import org.json.JSONArray
import org.json.JSONObject

class DashboardRepository(
    private val supabase: SupabaseClient,
    private val cache: CacheDao,
    private val tokenStore: TokenStore? = null,
) {
    val isDemoMode: Boolean get() = tokenStore?.isDemoMode == true
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

    private val _dailyUsage = MutableStateFlow<List<DailyUsage>>(emptyList())
    val dailyUsage: StateFlow<List<DailyUsage>> = _dailyUsage

    /** Load cached data into StateFlows (call on startup). */
    suspend fun loadFromCache() {
        cache.getDashboard()?.let { cached ->
            parseDashboard(cached.json)?.let { _dashboard.value = it }
        }
        val cachedProviders = cache.getProviders().mapNotNull { parseProvider(it.json) }
        if (cachedProviders.isNotEmpty()) _providers.value = cachedProviders

        val cachedSessions = cache.getSessions().mapNotNull { parseSession(it.json) }
        if (cachedSessions.isNotEmpty()) _sessions.value = cachedSessions

        val cachedAlerts = cache.getAlerts().mapNotNull { parseAlert(it.json) }
        if (cachedAlerts.isNotEmpty()) _alerts.value = cachedAlerts

        val cachedDevices = cache.getDevices().mapNotNull { parseDevice(it.json) }
        if (cachedDevices.isNotEmpty()) _devices.value = cachedDevices

        val cachedDailyUsage = cache.getDailyUsage().mapNotNull { parseDailyUsage(it.json) }
        if (cachedDailyUsage.isNotEmpty()) _dailyUsage.value = cachedDailyUsage
    }

    /** Load demo data into StateFlows when in demo mode. */
    fun loadDemoData() {
        _dashboard.value = DemoDataProvider.dashboard()
        _providers.value = DemoDataProvider.providers()
        _sessions.value = DemoDataProvider.sessions()
        _devices.value = DemoDataProvider.devices()
        _alerts.value = DemoDataProvider.alerts()
    }

    /** Clear demo mode and all demo data. */
    fun exitDemoMode() {
        tokenStore?.isDemoMode = false
        _dashboard.value = null
        _providers.value = emptyList()
        _sessions.value = emptyList()
        _devices.value = emptyList()
        _alerts.value = emptyList()
        _dailyUsage.value = emptyList()
    }

    suspend fun refreshAll() = coroutineScope {
        if (isDemoMode) {
            loadDemoData()
            return@coroutineScope
        }
        // Run all fetches in parallel (like iOS async let pattern)
        launch { refreshDashboard() }
        launch { refreshProviders() }
        launch { refreshSessions() }
        launch { refreshAlerts() }
        launch { refreshDevices() }
        launch { refreshDailyUsage() }
    }

    suspend fun refreshDashboard() {
        val data = supabase.dashboard()
        _dashboard.value = data
        cache.saveDashboard(CachedDashboard(json = serializeDashboard(data)))
    }

    suspend fun refreshProviders() {
        val data = supabase.providers()
        _providers.value = data
        cache.replaceProviders(data.map { CachedProvider(provider = it.provider, json = serializeProvider(it)) })
    }

    suspend fun refreshSessions() {
        val data = supabase.sessions()
        _sessions.value = data
        cache.replaceSessions(data.map { CachedSession(id = it.id, json = serializeSession(it)) })
    }

    suspend fun refreshDevices() {
        val data = supabase.devices()
        _devices.value = data
        cache.replaceDevices(data.map { CachedDevice(id = it.id, json = serializeDevice(it)) })
    }

    suspend fun refreshAlerts() {
        val data = supabase.alerts()
        _alerts.value = data
        cache.replaceAlerts(data.map { CachedAlert(id = it.id, json = serializeAlert(it)) })
    }

    suspend fun refreshDailyUsage(days: Int = 30) {
        val data = supabase.dailyUsage(days)
        _dailyUsage.value = data
        cache.replaceDailyUsage(data.map {
            CachedDailyUsage(id = "${it.date}-${it.provider}-${it.model}", json = serializeDailyUsage(it))
        })
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

    /** Clear all cached data (e.g., on sign-out). */
    suspend fun clearCache() {
        cache.clearDashboard()
        cache.clearProviders()
        cache.clearSessions()
        cache.clearAlerts()
        cache.clearDevices()
        cache.clearDailyUsage()
    }

    // ── Serialization (lightweight JSON) ──

    private fun serializeDashboard(d: DashboardSummary): String = JSONObject().apply {
        put("totalUsageToday", d.totalUsageToday)
        put("totalEstimatedCostToday", d.totalEstimatedCostToday)
        put("totalRequestsToday", d.totalRequestsToday)
        put("activeSessions", d.activeSessions)
        put("onlineDevices", d.onlineDevices)
        put("unresolvedAlerts", d.unresolvedAlerts)
    }.toString()

    private fun parseDashboard(json: String): DashboardSummary? = try {
        val j = JSONObject(json)
        DashboardSummary(
            totalUsageToday = j.optInt("totalUsageToday"),
            totalEstimatedCostToday = j.optDouble("totalEstimatedCostToday", 0.0),
            totalRequestsToday = j.optInt("totalRequestsToday"),
            activeSessions = j.optInt("activeSessions"),
            onlineDevices = j.optInt("onlineDevices"),
            unresolvedAlerts = j.optInt("unresolvedAlerts"),
            alertSummary = AlertSummaryDTO(info = j.optInt("unresolvedAlerts")),
        )
    } catch (_: Exception) { null }

    private fun serializeProvider(p: ProviderUsage): String = JSONObject().apply {
        put("provider", p.provider)
        put("todayUsage", p.todayUsage)
        put("weekUsage", p.weekUsage)
        put("estimatedCostWeek", p.estimatedCostWeek)
        if (p.quota != null) put("quota", p.quota)
        if (p.remaining != null) put("remaining", p.remaining)
        if (p.planType != null) put("planType", p.planType)
        if (p.resetTime != null) put("resetTime", p.resetTime)
        put("statusText", p.statusText)
        put("tiers", JSONArray().apply {
            p.tiers.forEach { t ->
                put(JSONObject().apply {
                    put("name", t.name)
                    put("quota", t.quota)
                    put("remaining", t.remaining)
                    if (t.resetTime != null) put("resetTime", t.resetTime)
                })
            }
        })
    }.toString()

    private fun parseProvider(json: String): ProviderUsage? = try {
        val j = JSONObject(json)
        val tiersArr = j.optJSONArray("tiers")
        val tiers = if (tiersArr != null) (0 until tiersArr.length()).map { i ->
            val t = tiersArr.getJSONObject(i)
            TierDTO(t.optString("name"), t.optInt("quota"), t.optInt("remaining"),
                t.optString("resetTime").takeIf { it.isNotBlank() })
        } else emptyList()
        ProviderUsage(
            provider = j.optString("provider"),
            todayUsage = j.optInt("todayUsage"),
            weekUsage = j.optInt("weekUsage"),
            estimatedCostWeek = j.optDouble("estimatedCostWeek", 0.0),
            quota = if (j.has("quota")) j.optInt("quota") else null,
            remaining = if (j.has("remaining")) j.optInt("remaining") else null,
            planType = j.optString("planType").takeIf { it.isNotBlank() },
            resetTime = j.optString("resetTime").takeIf { it.isNotBlank() },
            statusText = j.optString("statusText", "Operational"),
            tiers = tiers,
        )
    } catch (_: Exception) { null }

    private fun serializeSession(s: SessionRecord): String = JSONObject().apply {
        put("id", s.id); put("name", s.name); put("provider", s.provider)
        put("project", s.project); put("deviceName", s.deviceName)
        put("startedAt", s.startedAt); put("lastActiveAt", s.lastActiveAt)
        put("status", s.status); put("totalUsage", s.totalUsage)
        put("estimatedCost", s.estimatedCost); put("requests", s.requests)
        put("errorCount", s.errorCount)
    }.toString()

    private fun parseSession(json: String): SessionRecord? = try {
        val j = JSONObject(json)
        SessionRecord(
            id = j.optString("id"), name = j.optString("name"),
            provider = j.optString("provider"), project = j.optString("project"),
            deviceName = j.optString("deviceName"), startedAt = j.optString("startedAt"),
            lastActiveAt = j.optString("lastActiveAt"), status = j.optString("status", "Running"),
            totalUsage = j.optInt("totalUsage"), estimatedCost = j.optDouble("estimatedCost", 0.0),
            costStatus = "Estimated", requests = j.optInt("requests"),
            errorCount = j.optInt("errorCount"),
        )
    } catch (_: Exception) { null }

    private fun serializeAlert(a: AlertRecord): String = JSONObject().apply {
        put("id", a.id); put("type", a.type); put("severity", a.severity)
        put("title", a.title); put("message", a.message)
        put("createdAt", a.createdAt); put("isRead", a.isRead)
        put("isResolved", a.isResolved)
    }.toString()

    private fun parseAlert(json: String): AlertRecord? = try {
        val j = JSONObject(json)
        AlertRecord(
            id = j.optString("id"), type = j.optString("type"),
            severity = j.optString("severity", "Info"), title = j.optString("title"),
            message = j.optString("message"), createdAt = j.optString("createdAt"),
            isRead = j.optBoolean("isRead"), isResolved = j.optBoolean("isResolved"),
        )
    } catch (_: Exception) { null }

    private fun serializeDevice(d: DeviceRecord): String = JSONObject().apply {
        put("id", d.id); put("name", d.name); put("type", d.type)
        put("system", d.system); put("status", d.status)
        if (d.lastSyncAt != null) put("lastSyncAt", d.lastSyncAt)
        put("helperVersion", d.helperVersion)
    }.toString()

    private fun parseDevice(json: String): DeviceRecord? = try {
        val j = JSONObject(json)
        DeviceRecord(
            id = j.optString("id"), name = j.optString("name"),
            type = j.optString("type", "macOS"), system = j.optString("system"),
            status = j.optString("status", "Offline"),
            lastSyncAt = j.optString("lastSyncAt").takeIf { it.isNotBlank() },
            helperVersion = j.optString("helperVersion"),
            currentSessionCount = 0,
        )
    } catch (_: Exception) { null }

    private fun serializeDailyUsage(d: DailyUsage): String = JSONObject().apply {
        put("date", d.date); put("provider", d.provider); put("model", d.model)
        put("inputTokens", d.inputTokens); put("cachedTokens", d.cachedTokens)
        put("outputTokens", d.outputTokens); put("cost", d.cost)
    }.toString()

    private fun parseDailyUsage(json: String): DailyUsage? = try {
        val j = JSONObject(json)
        DailyUsage(
            date = j.optString("date"),
            provider = j.optString("provider"),
            model = j.optString("model"),
            inputTokens = j.optInt("inputTokens"),
            cachedTokens = j.optInt("cachedTokens"),
            outputTokens = j.optInt("outputTokens"),
            cost = j.optDouble("cost", 0.0),
        )
    } catch (_: Exception) { null }
}
