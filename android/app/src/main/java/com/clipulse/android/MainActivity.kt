package com.clipulse.android

import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.clipulse.android.ui.navigation.AppNavigation
import com.clipulse.android.ui.theme.CLIPulseTheme
import dagger.hilt.android.AndroidEntryPoint

@AndroidEntryPoint
class MainActivity : ComponentActivity() {
    /** OAuth code extracted from an auth callback deep link. */
    var pendingOAuthCode by mutableStateOf<String?>(null)
        private set

    /** OAuth state parameter for CSRF verification. Set by LoginScreen before launching browser. */
    var expectedOAuthState: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        handleOAuthDeepLink(intent)
        enableEdgeToEdge()
        setContent {
            CLIPulseTheme {
                AppNavigation(oauthCode = pendingOAuthCode)
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleOAuthDeepLink(intent)
    }

    private fun handleOAuthDeepLink(intent: Intent?) {
        val data = intent?.data ?: return
        // Accept both App Links (https://clipulse.app/auth/callback) and fallback custom scheme
        val isHttps = data.scheme == "https" && data.host == "clipulse.app" && data.path == "/auth/callback"
        val isCustom = data.scheme == "clipulse" && data.host == "auth" && data.path == "/callback"
        if (!isHttps && !isCustom) return

        // Verify state parameter to prevent CSRF attacks
        val state = data.getQueryParameter("state")
        val expected = expectedOAuthState
        if (expected != null && state != expected) return // state mismatch — reject

        val code = data.getQueryParameter("code")
        // Validate code is a plausible OAuth authorization code (alphanumeric + common delimiters)
        if (code != null && code.length in 10..512 && code.matches(Regex("^[A-Za-z0-9_\\-/.+=]+$"))) {
            pendingOAuthCode = code
            expectedOAuthState = null // consumed
        }
    }
}
