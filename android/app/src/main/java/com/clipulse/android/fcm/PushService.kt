package com.clipulse.android.fcm

import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import android.util.Log
import androidx.core.app.NotificationCompat
import com.clipulse.android.R
import com.clipulse.android.data.remote.SupabaseClient
import com.clipulse.android.data.remote.TokenStore
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage
import dagger.hilt.android.AndroidEntryPoint
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import java.util.concurrent.atomic.AtomicInteger
import javax.inject.Inject

@AndroidEntryPoint
class PushService : FirebaseMessagingService() {

    companion object {
        private const val TAG = "PushService"
        private const val CHANNEL_ID = "cli_pulse_alerts"
        private const val CHANNEL_NAME = "CLI Pulse Alerts"
        private val notificationIdCounter = AtomicInteger(0)
    }

    @Inject lateinit var supabase: SupabaseClient
    @Inject lateinit var tokenStore: TokenStore

    override fun onNewToken(token: String) {
        Log.d(TAG, "FCM token refreshed")
        val deviceId = tokenStore.deviceId
        if (deviceId != null && tokenStore.accessToken != null) {
            CoroutineScope(Dispatchers.IO).launch {
                try {
                    supabase.updatePushToken(deviceId, token)
                    Log.d(TAG, "Push token registered for device $deviceId")
                } catch (e: Exception) {
                    Log.w(TAG, "Failed to register push token: ${e.message}")
                }
            }
        } else {
            Log.d(TAG, "Skipping push token upload: deviceId=$deviceId, authenticated=${tokenStore.accessToken != null}")
        }
    }

    override fun onMessageReceived(message: RemoteMessage) {
        val title = message.notification?.title ?: message.data["title"] ?: "CLI Pulse"
        val body = message.notification?.body ?: message.data["body"] ?: ""

        if (body.isBlank()) return

        val manager = getSystemService(NotificationManager::class.java)

        // Create channel (Android 8+)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID, CHANNEL_NAME, NotificationManager.IMPORTANCE_DEFAULT,
            )
            manager.createNotificationChannel(channel)
        }

        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(title)
            .setContentText(body)
            .setAutoCancel(true)
            .build()

        manager.notify(notificationIdCounter.incrementAndGet(), notification)
    }
}
