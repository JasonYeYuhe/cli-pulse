package com.clipulse.android.data.remote

import com.clipulse.android.BuildConfig
import com.clipulse.android.data.model.*
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONArray
import org.json.JSONObject
import java.net.URLEncoder
import java.time.Instant
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
class SupabaseClient(
    private val tokenStore: TokenStore,
) {
    private val supabaseUrl: String = BuildConfig.SUPABASE_URL
    private val supabaseAnonKey: String = BuildConfig.SUPABASE_ANON_KEY
    private val jsonMedia = "application/json; charset=utf-8".toMediaType()

    private val refreshMutex = Mutex()

    private val client = OkHttpClient.Builder()
        .connectTimeout(15, TimeUnit.SECONDS)
        .readTimeout(15, TimeUnit.SECONDS)
        .writeTimeout(15, TimeUnit.SECONDS)
        .build()

    // ── Auth ──────────────────────────────────────────────

    suspend fun signInWithGoogle(idToken: String, name: String?, email: String?): AuthResponse =
        withContext(Dispatchers.IO) {
            val body = JSONObject().apply {
                put("provider", "google")
                put("id_token", idToken)
                if (name != null) put("name", name)
            }
            val json = post("$supabaseUrl/auth/v1/token?grant_type=id_token", body, auth = false)
            handleAuthResponse(json, email)
        }

    suspend fun sendOTP(email: String): Unit = withContext(Dispatchers.IO) {
        val body = JSONObject().apply {
            put("email", email)
            put("create_user", true)
        }
        post("$supabaseUrl/auth/v1/otp", body, auth = false)
    }

    suspend fun verifyOTP(email: String, code: String): AuthResponse =
        withContext(Dispatchers.IO) {
            val body = JSONObject().apply {
                put("email", email)
                put("token", code)
                put("type", "email")
            }
            val json = post("$supabaseUrl/auth/v1/verify", body, auth = false)
            handleAuthResponse(json, email)
        }

    suspend fun signInWithPassword(email: String, password: String): AuthResponse =
        withContext(Dispatchers.IO) {
            val body = JSONObject().apply {
                put("email", email)
                put("password", password)
            }
            val json = post("$supabaseUrl/auth/v1/token?grant_type=password", body, auth = false)
            handleAuthResponse(json, email)
        }

    suspend fun me(): AuthResponse = withContext(Dispatchers.IO) {
        val json = get("$supabaseUrl/auth/v1/user")
        val userId = json.optString("id")
        tokenStore.userId = userId
        val metadata = json.optJSONObject("user_metadata") ?: JSONObject()

        val profile = restGetArray("/rest/v1/profiles?id=eq.${enc(userId)}&select=paired,name,email")
        val p = profile.optJSONObject(0) ?: JSONObject()

        AuthResponse(
            access_token = tokenStore.accessToken ?: "",
            refresh_token = tokenStore.refreshToken,
            user = UserDTO(
                id = userId,
                name = p.optString("name", metadata.optString("name", "")),
                email = p.optString("email", json.optString("email", "")),
            ),
            paired = p.optBoolean("paired", false),
        )
    }

    suspend fun refreshAccessToken(staleToken: String? = null): Pair<String, String> = refreshMutex.withLock {
        withContext(Dispatchers.IO) {
            // If another coroutine already refreshed while we waited for the lock, skip
            if (staleToken != null && tokenStore.accessToken != staleToken) {
                return@withContext (tokenStore.accessToken ?: "") to (tokenStore.refreshToken ?: "")
            }
            val rt = tokenStore.refreshToken ?: throw ApiError.TokenExpired
            val body = JSONObject().apply { put("refresh_token", rt) }
            val json = post("$supabaseUrl/auth/v1/token?grant_type=refresh_token", body, auth = false)
            if (json.has("error")) {
                val errorMsg = json.optString("error_description", json.optString("error", "Token refresh failed"))
                throw ApiError.Http(401, errorMsg)
            }
            val newAccess = json.optString("access_token")
            if (newAccess.isNullOrBlank()) {
                throw ApiError.Http(401, "Empty access_token in refresh response")
            }
            val newRefresh = json.optString("refresh_token", rt)
            tokenStore.accessToken = newAccess
            tokenStore.refreshToken = newRefresh
            newAccess to newRefresh
        }
    }

    suspend fun signOut(): Unit = withContext(Dispatchers.IO) {
        val token = tokenStore.accessToken
        tokenStore.clear()
        if (token != null) {
            try {
                val req = Request.Builder()
                    .url("$supabaseUrl/auth/v1/logout")
                    .post("{}".toRequestBody(jsonMedia))
                    .addHeader("apikey", supabaseAnonKey)
                    .addHeader("Authorization", "Bearer $token")
                    .build()
                client.newCall(req).execute().close()
            } catch (_: Exception) { }
        }
    }

    // ── Dashboard ────────────────────────────────────────

    suspend fun dashboard(): DashboardSummary = withContext(Dispatchers.IO) {
        val json = rpc("dashboard_summary")
        DashboardSummary(
            totalUsageToday = json.optInt("today_usage"),
            totalEstimatedCostToday = json.optDouble("today_cost", 0.0),
            costStatus = "Estimated",
            totalRequestsToday = json.optInt("today_sessions"),
            activeSessions = json.optInt("active_sessions"),
            onlineDevices = json.optInt("online_devices"),
            unresolvedAlerts = json.optInt("unresolved_alerts"),
            alertSummary = AlertSummaryDTO(info = json.optInt("unresolved_alerts")),
        )
    }

    // ── Providers ────────────────────────────────────────

    suspend fun providers(): List<ProviderUsage> = withContext(Dispatchers.IO) {
        val arr = rpcArray("provider_summary")
        (0 until arr.length()).map { i ->
            val p = arr.getJSONObject(i)
            val tiersArr = p.optJSONArray("tiers")
            val tiers = if (tiersArr != null) {
                (0 until tiersArr.length()).map { j ->
                    val t = tiersArr.getJSONObject(j)
                    TierDTO(
                        name = t.optString("name", "Default"),
                        quota = t.optInt("quota"),
                        remaining = t.optInt("remaining"),
                        resetTime = t.optString("reset_time").takeIf { it.isNotBlank() },
                    )
                }
            } else emptyList()

            ProviderUsage(
                provider = p.optString("provider"),
                todayUsage = p.optInt("today_usage"),
                weekUsage = p.optInt("total_usage"),
                estimatedCostWeek = p.optDouble("estimated_cost", 0.0),
                quota = p.optIntOrNull("quota"),
                remaining = p.optIntOrNull("remaining"),
                planType = p.optString("plan_type").takeIf { it.isNotBlank() },
                resetTime = p.optString("reset_time").takeIf { it.isNotBlank() },
                tiers = tiers,
            )
        }
    }

    // ── Sessions ─────────────────────────────────────────

    suspend fun sessions(): List<SessionRecord> = withContext(Dispatchers.IO) {
        val userId = enc(tokenStore.userId ?: "")
        val arr = restGetArray(
            "/rest/v1/sessions?user_id=eq.$userId&select=*,devices(name)&order=last_active_at.desc&limit=50"
        )
        (0 until arr.length()).map { i ->
            val r = arr.getJSONObject(i)
            val device = r.optJSONObject("devices")
            SessionRecord(
                id = r.optString("id"),
                name = r.optString("name"),
                provider = r.optString("provider"),
                project = r.optString("project"),
                deviceName = device?.optString("name") ?: "",
                startedAt = r.optString("started_at"),
                lastActiveAt = r.optString("last_active_at"),
                status = r.optString("status", "Running"),
                totalUsage = r.optInt("total_usage"),
                estimatedCost = r.optDouble("estimated_cost", 0.0),
                costStatus = "Estimated",
                requests = r.optInt("requests"),
                errorCount = r.optInt("error_count"),
                collectionConfidence = r.optString("collection_confidence").takeIf { it.isNotBlank() },
            )
        }
    }

    // ── Devices ──────────────────────────────────────────

    suspend fun devices(): List<DeviceRecord> = withContext(Dispatchers.IO) {
        val userId = enc(tokenStore.userId ?: "")
        val arr = restGetArray(
            "/rest/v1/devices?user_id=eq.$userId&select=*&order=last_seen_at.desc"
        )
        (0 until arr.length()).map { i ->
            val r = arr.getJSONObject(i)
            DeviceRecord(
                id = r.optString("id"),
                name = r.optString("name"),
                type = r.optString("type", "macOS"),
                system = r.optString("system"),
                status = r.optString("status", "Offline"),
                lastSyncAt = r.optString("last_seen_at").takeIf { it.isNotBlank() },
                helperVersion = r.optString("helper_version"),
                currentSessionCount = 0,
                cpuUsage = r.optIntOrNull("cpu_usage"),
                memoryUsage = r.optIntOrNull("memory_usage"),
            )
        }
    }

    // ── Alerts ───────────────────────────────────────────

    suspend fun alerts(): List<AlertRecord> = withContext(Dispatchers.IO) {
        val userId = enc(tokenStore.userId ?: "")
        val arr = restGetArray(
            "/rest/v1/alerts?user_id=eq.$userId&select=*&order=created_at.desc&limit=50"
        )
        (0 until arr.length()).map { i ->
            val r = arr.getJSONObject(i)
            AlertRecord(
                id = r.optString("id"),
                type = r.optString("type"),
                severity = r.optString("severity", "Info"),
                title = r.optString("title"),
                message = r.optString("message"),
                createdAt = r.optString("created_at"),
                isRead = r.optBoolean("is_read"),
                isResolved = r.optBoolean("is_resolved"),
                acknowledgedAt = r.optString("acknowledged_at").takeIf { it.isNotBlank() },
                snoozedUntil = r.optString("snoozed_until").takeIf { it.isNotBlank() },
                relatedProjectId = r.optString("related_project_id").takeIf { it.isNotBlank() },
                relatedProjectName = r.optString("related_project_name").takeIf { it.isNotBlank() },
                relatedSessionId = r.optString("related_session_id").takeIf { it.isNotBlank() },
                relatedSessionName = r.optString("related_session_name").takeIf { it.isNotBlank() },
                relatedProvider = r.optString("related_provider").takeIf { it.isNotBlank() },
                relatedDeviceName = r.optString("related_device_name").takeIf { it.isNotBlank() },
                sourceKind = r.optString("source_kind").takeIf { it.isNotBlank() },
                sourceId = r.optString("source_id").takeIf { it.isNotBlank() },
                groupingKey = r.optString("grouping_key").takeIf { it.isNotBlank() },
                suppressionKey = r.optString("suppression_key").takeIf { it.isNotBlank() },
            )
        }
    }

    suspend fun acknowledgeAlert(id: String) = withContext(Dispatchers.IO) {
        val userId = enc(tokenStore.userId ?: "")
        restPatch(
            "/rest/v1/alerts?id=eq.${enc(id)}&user_id=eq.$userId",
            JSONObject().apply {
                put("acknowledged_at", isoNow())
                put("is_read", true)
            },
        )
    }

    suspend fun resolveAlert(id: String) = withContext(Dispatchers.IO) {
        val userId = enc(tokenStore.userId ?: "")
        restPatch(
            "/rest/v1/alerts?id=eq.${enc(id)}&user_id=eq.$userId",
            JSONObject().apply { put("is_resolved", true) },
        )
    }

    suspend fun snoozeAlert(id: String, minutes: Int) = withContext(Dispatchers.IO) {
        val userId = enc(tokenStore.userId ?: "")
        val until = isoAt(System.currentTimeMillis() + minutes * 60_000L)
        restPatch(
            "/rest/v1/alerts?id=eq.${enc(id)}&user_id=eq.$userId",
            JSONObject().apply { put("snoozed_until", until) },
        )
    }

    // ── Settings ─────────────────────────────────────────

    suspend fun settings(): SettingsSnapshot = withContext(Dispatchers.IO) {
        val userId = enc(tokenStore.userId ?: "")
        val arr = restGetArray("/rest/v1/user_settings?user_id=eq.$userId&select=*")
        val s = arr.optJSONObject(0) ?: JSONObject()
        SettingsSnapshot(
            notificationsEnabled = s.optBoolean("notifications_enabled", true),
            pushPolicy = s.optString("push_policy", "Warnings + Critical"),
            digestEnabled = s.optBoolean("digest_notifications_enabled", true),
            digestIntervalHours = maxOf(1, s.optInt("digest_interval_minutes", 60) / 60),
            usageSpikeThreshold = s.optInt("usage_spike_threshold", 500),
            projectBudgetThresholdUsd = s.optDouble("project_budget_threshold_usd", 0.25),
            sessionTooLongThresholdMinutes = s.optInt("session_too_long_threshold_minutes", 180),
            offlineGracePeriodMinutes = s.optInt("offline_grace_period_minutes", 5),
            repeatedFailureThreshold = s.optInt("repeated_failure_threshold", 3),
            alertCooldownMinutes = s.optInt("alert_cooldown_minutes", 30),
            dataRetentionDays = s.optInt("data_retention_days", 7),
            webhookUrl = s.optString("webhook_url").takeIf { it.isNotBlank() },
            webhookEnabled = s.optBoolean("webhook_enabled", false),
        )
    }

    suspend fun updateSettings(patch: JSONObject): Unit = withContext(Dispatchers.IO) {
        val userId = enc(tokenStore.userId ?: return@withContext)
        restPatch("/rest/v1/user_settings?user_id=eq.$userId", patch)
    }

    suspend fun testWebhook(): Unit = withContext(Dispatchers.IO) {
        val userId = tokenStore.userId ?: return@withContext
        val body = JSONObject().apply {
            put("user_id", userId)
            put("alert", JSONObject().apply {
                put("type", "Test")
                put("severity", "Info")
                put("title", "CLI Pulse webhook test")
                put("message", "If you see this, your webhook integration is working correctly.")
            })
        }
        post("$supabaseUrl/functions/v1/send-webhook", body)
    }

    // ─�� Server Tier ──────────────────────────────────────

    suspend fun serverTier(): String = withContext(Dispatchers.IO) {
        try {
            val json = rpc("get_user_tier")
            json.optString("tier", "free")
        } catch (_: Exception) {
            "free"
        }
    }

    // ── Receipt Validation ─────────────────────────────────

    data class ReceiptResult(val verified: Boolean, val tier: String, val isNetworkError: Boolean = false)

    suspend fun validateReceipt(purchaseToken: String, productId: String): ReceiptResult =
        withContext(Dispatchers.IO) {
            try {
                val body = JSONObject().apply {
                    put("platform", "google")
                    put("purchaseToken", purchaseToken)
                    put("productId", productId)
                    put("packageName", "com.clipulse.android")
                }
                val req = Request.Builder()
                    .url("$supabaseUrl/functions/v1/validate-receipt")
                    .post(body.toString().toRequestBody(jsonMedia))
                    .addHeader("Content-Type", "application/json")
                    .addHeader("apikey", supabaseAnonKey)
                    .apply {
                        tokenStore.accessToken?.let {
                            addHeader("Authorization", "Bearer $it")
                        }
                    }
                    .build()
                val resp = client.newCall(req).execute()
                resp.use { r ->
                    if (r.code >= 500) {
                        // Server error (transient) — treat like network error for retry
                        return@withContext ReceiptResult(false, "free", isNetworkError = true)
                    }
                    if (!r.isSuccessful) return@withContext ReceiptResult(false, "free")
                    val json = JSONObject(r.body?.string() ?: "{}")
                    ReceiptResult(
                        verified = json.optBoolean("verified", false),
                        tier = json.optString("tier", "free"),
                    )
                }
            } catch (_: java.io.IOException) {
                // Network error — distinguishable from server rejection
                ReceiptResult(false, "free", isNetworkError = true)
            } catch (_: Exception) {
                ReceiptResult(false, "free")
            }
        }

    // ── Device Registration ──────────────────────────────

    suspend fun registerDevice(name: String, type: String = "Android", system: String): String =
        withContext(Dispatchers.IO) {
            val userId = tokenStore.userId ?: throw ApiError.TokenExpired
            val body = JSONObject().apply {
                put("user_id", userId)
                put("name", name)
                put("type", type)
                put("system", system)
                put("status", "Online")
                put("helper_version", "1.0.0")
            }
            val req = Request.Builder()
                .url("$supabaseUrl/rest/v1/devices")
                .post(body.toString().toRequestBody(jsonMedia))
                .addHeader("Content-Type", "application/json")
                .addHeader("apikey", supabaseAnonKey)
                .addHeader("Prefer", "return=representation")
                .apply {
                    tokenStore.accessToken?.let {
                        addHeader("Authorization", "Bearer $it")
                    }
                }
                .build()
            val resp = client.newCall(req).execute()
            resp.use { r ->
                if (!r.isSuccessful) throw ApiError.Http(r.code, r.body?.string() ?: "")
                val arr = JSONArray(r.body?.string() ?: "[]")
                arr.getJSONObject(0).optString("id")
            }
        }

    suspend fun updatePushToken(deviceId: String, token: String): Unit =
        withContext(Dispatchers.IO) {
            val body = JSONObject().apply {
                put("push_token", token)
                put("push_platform", "fcm")
            }
            val req = Request.Builder()
                .url("$supabaseUrl/rest/v1/devices?id=eq.${enc(deviceId)}")
                .patch(body.toString().toRequestBody(jsonMedia))
                .addHeader("Content-Type", "application/json")
                .addHeader("apikey", supabaseAnonKey)
                .apply {
                    tokenStore.accessToken?.let {
                        addHeader("Authorization", "Bearer $it")
                    }
                }
                .build()
            val resp = client.newCall(req).execute()
            resp.use { r ->
                if (!r.isSuccessful) throw ApiError.Http(r.code, r.body?.string() ?: "")
            }
        }

    suspend fun syncProviderQuotas(results: List<ProviderQuotaPayload>): Unit =
        withContext(Dispatchers.IO) {
            val userId = tokenStore.userId ?: return@withContext
            if (results.isEmpty()) return@withContext

            val arr = JSONArray()
            for (r in results) {
                arr.put(JSONObject().apply {
                    put("user_id", userId)
                    put("provider", r.provider)
                    put("remaining", r.remaining)
                    put("quota", r.quota)
                    if (r.planType != null) put("plan_type", r.planType)
                    if (r.resetTime != null) put("reset_time", r.resetTime)
                    put("tiers", JSONArray(r.tiersJson))
                    put("updated_at", isoNow())
                })
            }
            val req = Request.Builder()
                .url("$supabaseUrl/rest/v1/provider_quotas")
                .post(arr.toString().toRequestBody(jsonMedia))
                .addHeader("Content-Type", "application/json")
                .addHeader("apikey", supabaseAnonKey)
                .addHeader("Prefer", "resolution=merge-duplicates")
                .apply {
                    tokenStore.accessToken?.let {
                        addHeader("Authorization", "Bearer $it")
                    }
                }
                .build()
            val resp = client.newCall(req).execute()
            resp.use { r ->
                if (!r.isSuccessful) {
                    // Log but don't throw — quota sync is non-critical
                    android.util.Log.w("SupabaseClient", "syncProviderQuotas failed: ${r.code}")
                }
            }
        }

    data class ProviderQuotaPayload(
        val provider: String,
        val remaining: Int,
        val quota: Int,
        val planType: String? = null,
        val resetTime: String? = null,
        val tiersJson: String = "[]",
    )

    // ── OAuth PKCE (GitHub / Google via Supabase) ─────────

    /** Build a Supabase OAuth authorize URL with PKCE challenge. Returns (url, codeVerifier). */
    fun oauthAuthorizeUrl(provider: String): Pair<String, String> {
        val verifier = generateCodeVerifier()
        val challenge = sha256Base64Url(verifier)
        val redirectTo = URLEncoder.encode("clipulse://auth/callback", "UTF-8")
        val url = "$supabaseUrl/auth/v1/authorize" +
            "?provider=$provider" +
            "&redirect_to=$redirectTo" +
            "&code_challenge=$challenge" +
            "&code_challenge_method=S256"
        return url to verifier
    }

    /** Exchange an OAuth authorization code for a Supabase session (PKCE). */
    suspend fun exchangeOAuthCode(code: String, codeVerifier: String): Unit = withContext(Dispatchers.IO) {
        val body = JSONObject().apply {
            put("auth_code", code)
            put("code_verifier", codeVerifier)
        }
        val req = Request.Builder()
            .url("$supabaseUrl/auth/v1/token?grant_type=pkce")
            .post(body.toString().toRequestBody(jsonMedia))
            .addHeader("Content-Type", "application/json")
            .addHeader("apikey", supabaseAnonKey)
            .build()
        val resp: okhttp3.Response = client.newCall(req).execute()
        resp.use { r: okhttp3.Response ->
            val responseBody = r.body?.string() ?: ""
            if (!r.isSuccessful) throw ApiError.Http(r.code, responseBody)
            val json = JSONObject(responseBody)
            val at = json.getString("access_token")
            val rt = json.getString("refresh_token")
            val user = json.optJSONObject("user")
            val uid = user?.optString("id") ?: ""
            val meta = user?.optJSONObject("user_metadata")
            val name = meta?.optString("name") ?: meta?.optString("full_name") ?: ""
            val email = user?.optString("email") ?: ""
            tokenStore.updateAuthState(at, rt, uid)
            tokenStore.userName = name
            tokenStore.userEmail = email
        }
    }

    private fun generateCodeVerifier(): String {
        val bytes = ByteArray(32)
        java.security.SecureRandom().nextBytes(bytes)
        return android.util.Base64.encodeToString(bytes,
            android.util.Base64.URL_SAFE or android.util.Base64.NO_PADDING or android.util.Base64.NO_WRAP)
    }

    private fun sha256Base64Url(input: String): String {
        val digest = java.security.MessageDigest.getInstance("SHA-256").digest(input.toByteArray())
        return android.util.Base64.encodeToString(digest,
            android.util.Base64.URL_SAFE or android.util.Base64.NO_PADDING or android.util.Base64.NO_WRAP)
    }

    // ── Health ────────────────────────────────────────────

    suspend fun health(): Boolean = withContext(Dispatchers.IO) {
        try {
            val req = Request.Builder()
                .url("$supabaseUrl/auth/v1/health")
                .get()
                .addHeader("apikey", supabaseAnonKey)
                .build()
            val resp = client.newCall(req).execute()
            resp.use { it.isSuccessful }
        } catch (_: Exception) {
            false
        }
    }

    // ── Teams ─────────────────────────────────────────────

    suspend fun rpcPublic(function: String, params: JSONObject = JSONObject()): JSONObject =
        withContext(Dispatchers.IO) { rpc(function, params) }

    data class TeamInfo(val id: String, val name: String, val role: String)

    suspend fun fetchTeamsForUser(userId: String): List<TeamInfo> = withContext(Dispatchers.IO) {
        val arr = restGetArray(
            "/rest/v1/team_members?user_id=eq.${enc(userId)}&select=role,teams(id,name)"
        )
        (0 until arr.length()).mapNotNull { i ->
            val row = arr.getJSONObject(i)
            val team = row.optJSONObject("teams") ?: return@mapNotNull null
            TeamInfo(
                id = team.optString("id"),
                name = team.optString("name"),
                role = row.optString("role", "member"),
            )
        }
    }

    data class TeamMemberInfo(val userId: String, val name: String, val email: String, val role: String)

    suspend fun fetchTeamMembers(teamId: String): List<TeamMemberInfo> = withContext(Dispatchers.IO) {
        val arr = restGetArray(
            "/rest/v1/team_members?team_id=eq.${enc(teamId)}&select=role,user_id,profiles(name,email)"
        )
        (0 until arr.length()).mapNotNull { i ->
            val row = arr.getJSONObject(i)
            val profile = row.optJSONObject("profiles") ?: return@mapNotNull null
            TeamMemberInfo(
                userId = row.optString("user_id"),
                name = profile.optString("name"),
                email = profile.optString("email"),
                role = row.optString("role", "member"),
            )
        }
    }

    // ── Account Deletion ─────────────────────────────────

    suspend fun deleteAccount() = withContext(Dispatchers.IO) {
        rpc("delete_user_account")
        signOut()
    }

    // ── HTTP Helpers (all suspend, no runBlocking) ─────

    // NOTE: All callers must be on Dispatchers.IO (public methods enforce this via withContext)
    private suspend fun get(url: String, retried: Boolean = false): JSONObject {
        val currentToken = tokenStore.accessToken
        val req = Request.Builder().url(url).get()
            .addHeader("apikey", supabaseAnonKey)
            .apply {
                currentToken?.let {
                    addHeader("Authorization", "Bearer $it")
                }
            }
            .build()
        val resp = client.newCall(req).execute()
        if (resp.code == 401 && !retried) {
            resp.close() // Free connection before blocking on refresh
            refreshAccessToken(staleToken = currentToken)
            return get(url, retried = true)
        }
        return resp.use { r ->
            if (!r.isSuccessful) throw ApiError.Http(r.code, r.body?.string() ?: "")
            JSONObject(r.body?.string() ?: "{}")
        }
    }

    private suspend fun post(url: String, body: JSONObject, auth: Boolean = true, retried: Boolean = false): JSONObject {
        val currentToken = if (auth) tokenStore.accessToken else null
        val req = Request.Builder().url(url)
            .post(body.toString().toRequestBody(jsonMedia))
            .addHeader("Content-Type", "application/json")
            .addHeader("apikey", supabaseAnonKey)
            .apply {
                if (auth) currentToken?.let {
                    addHeader("Authorization", "Bearer $it")
                }
            }
            .build()
        val resp = client.newCall(req).execute()
        if (resp.code == 401 && auth && !retried) {
            resp.close()
            refreshAccessToken(staleToken = currentToken)
            return post(url, body, auth, retried = true)
        }
        return resp.use { r ->
            if (!r.isSuccessful) throw ApiError.Http(r.code, r.body?.string() ?: "")
            val text = r.body?.string() ?: "{}"
            if (text.isBlank() || text == "null") JSONObject() else JSONObject(text)
        }
    }

    private suspend fun restGetArray(path: String, retried: Boolean = false): JSONArray {
        val currentToken = tokenStore.accessToken
        val req = Request.Builder().url("$supabaseUrl$path").get()
            .addHeader("Content-Type", "application/json")
            .addHeader("apikey", supabaseAnonKey)
            .apply {
                currentToken?.let {
                    addHeader("Authorization", "Bearer $it")
                }
            }
            .build()
        val resp = client.newCall(req).execute()
        if (resp.code == 401 && !retried) {
            resp.close()
            refreshAccessToken(staleToken = currentToken)
            return restGetArray(path, retried = true)
        }
        return resp.use { r ->
            if (!r.isSuccessful) throw ApiError.Http(r.code, r.body?.string() ?: "")
            JSONArray(r.body?.string() ?: "[]")
        }
    }

    private suspend fun restPatch(path: String, body: JSONObject, retried: Boolean = false) {
        val currentToken = tokenStore.accessToken
        val req = Request.Builder().url("$supabaseUrl$path")
            .patch(body.toString().toRequestBody(jsonMedia))
            .addHeader("Content-Type", "application/json")
            .addHeader("apikey", supabaseAnonKey)
            .apply {
                currentToken?.let {
                    addHeader("Authorization", "Bearer $it")
                }
            }
            .build()
        val resp = client.newCall(req).execute()
        if (resp.code == 401 && !retried) {
            resp.close()
            refreshAccessToken(staleToken = currentToken)
            restPatch(path, body, retried = true)
            return
        }
        resp.use { r ->
            if (!r.isSuccessful) throw ApiError.Http(r.code, r.body?.string() ?: "")
        }
    }

    private suspend fun rpc(function: String, params: JSONObject = JSONObject(), retried: Boolean = false): JSONObject {
        val currentToken = tokenStore.accessToken
        val req = Request.Builder().url("$supabaseUrl/rest/v1/rpc/$function")
            .post(params.toString().toRequestBody(jsonMedia))
            .addHeader("Content-Type", "application/json")
            .addHeader("apikey", supabaseAnonKey)
            .apply {
                currentToken?.let {
                    addHeader("Authorization", "Bearer $it")
                }
            }
            .build()
        val resp = client.newCall(req).execute()
        if (resp.code == 401 && !retried) {
            resp.close()
            refreshAccessToken(staleToken = currentToken)
            return rpc(function, params, retried = true)
        }
        return resp.use { r ->
            if (!r.isSuccessful) throw ApiError.Http(r.code, r.body?.string() ?: "")
            val text = r.body?.string() ?: "{}"
            if (text.isBlank() || text == "null") JSONObject()
            else if (text.trimStart().startsWith("[")) {
                JSONObject().put("_array", JSONArray(text))
            } else JSONObject(text)
        }
    }

    private suspend fun rpcArray(function: String, params: JSONObject = JSONObject(), retried: Boolean = false): JSONArray {
        val currentToken = tokenStore.accessToken
        val req = Request.Builder().url("$supabaseUrl/rest/v1/rpc/$function")
            .post(params.toString().toRequestBody(jsonMedia))
            .addHeader("Content-Type", "application/json")
            .addHeader("apikey", supabaseAnonKey)
            .apply {
                currentToken?.let {
                    addHeader("Authorization", "Bearer $it")
                }
            }
            .build()
        val resp = client.newCall(req).execute()
        if (resp.code == 401 && !retried) {
            resp.close()
            refreshAccessToken(staleToken = currentToken)
            return rpcArray(function, params, retried = true)
        }
        return resp.use { r ->
            if (!r.isSuccessful) throw ApiError.Http(r.code, r.body?.string() ?: "")
            JSONArray(r.body?.string() ?: "[]")
        }
    }

    private suspend fun handleAuthResponse(json: JSONObject, fallbackEmail: String?): AuthResponse {
        val token = json.optString("access_token")
        val refresh = json.optString("refresh_token").takeIf { it.isNotBlank() }
        val user = json.optJSONObject("user") ?: JSONObject()
        val userId = user.optString("id")

        tokenStore.updateAuthState(access = token, refresh = refresh, user = userId)

        val profile = try {
            restGetArray("/rest/v1/profiles?id=eq.${enc(userId)}&select=paired,name,email")
        } catch (_: Exception) {
            JSONArray()
        }
        val p = profile.optJSONObject(0) ?: JSONObject()
        val metadata = user.optJSONObject("user_metadata") ?: JSONObject()

        val name = p.optString("name").ifBlank { metadata.optString("name", "") }
        val email = p.optString("email").ifBlank { user.optString("email", fallbackEmail ?: "") }
        tokenStore.userName = name
        tokenStore.userEmail = email

        return AuthResponse(
            access_token = token,
            refresh_token = refresh,
            user = UserDTO(id = userId, name = name, email = email),
            paired = p.optBoolean("paired", false),
        )
    }

    // ── Utilities ────────────────────────────────────────

    private fun enc(value: String): String =
        URLEncoder.encode(value, "UTF-8")

    private fun isoNow(): String =
        DateTimeFormatter.ISO_INSTANT.format(Instant.now())

    private fun isoAt(millis: Long): String =
        DateTimeFormatter.ISO_INSTANT.format(Instant.ofEpochMilli(millis))

    private fun JSONObject.optIntOrNull(key: String): Int? =
        if (has(key) && !isNull(key)) optInt(key) else null
}

sealed class ApiError : Exception() {
    data class Http(val code: Int, val body: String) : ApiError() {
        override val message: String get() = "HTTP $code: $body"
    }

    data object TokenExpired : ApiError() {
        override val message: String get() = "Session expired. Please sign in again."
    }
}
