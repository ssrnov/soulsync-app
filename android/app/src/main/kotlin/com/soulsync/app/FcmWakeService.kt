package com.soulsync.app

import android.content.Intent
import android.os.Build
import android.content.pm.PackageManager
import android.Manifest
import androidx.core.content.ContextCompat
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage

// Server-side revival. When the backend sends a high-priority data push (e.g. a
// cron notices this phone stopped reporting, or the admin taps "Wake"), Android
// delivers it here even if the app was swiped away, and we restart the tracking
// foreground service. NOTE: a user "Force stop" from Settings blocks all pushes
// until the app is opened again — no app can work around that.
class FcmWakeService : FirebaseMessagingService() {
    override fun onMessageReceived(message: RemoteMessage) {
        try {
            // Revive on our own wake pings; ignore unrelated messages.
            val type = message.data["type"] ?: ""
            if (type != "wake" && type != "location_request" && !message.data.containsKey("wake")) return

            val prefs = getSharedPreferences("SoulSyncPrefs", MODE_PRIVATE)
            if ((prefs.getString("jwt_token", "") ?: "").isEmpty()) return
            val fine = ContextCompat.checkSelfPermission(this, Manifest.permission.ACCESS_FINE_LOCATION)
            val coarse = ContextCompat.checkSelfPermission(this, Manifest.permission.ACCESS_COARSE_LOCATION)
            if (fine != PackageManager.PERMISSION_GRANTED && coarse != PackageManager.PERMISSION_GRANTED) return

            val svc = Intent(this, SoulSyncService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                ContextCompat.startForegroundService(this, svc)
            } else {
                startService(svc)
            }
        } catch (e: Exception) { e.printStackTrace() }
    }
}
