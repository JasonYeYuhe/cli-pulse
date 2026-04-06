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
    /** OAuth code extracted from a clipulse://auth/callback deep link. */
    var pendingOAuthCode by mutableStateOf<String?>(null)
        private set

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
        if (data.scheme == "clipulse" && data.host == "auth") {
            val code = data.getQueryParameter("code")
            if (code != null) {
                pendingOAuthCode = code
            }
        }
    }
}
