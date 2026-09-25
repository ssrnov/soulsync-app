package com.soulsync.app

import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.Manifest
import androidx.core.content.ContextCompat
import androidx.work.Worker
import androidx.work.WorkerParameters
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL

// Runs in the background (every ~15 min) to fetch the partner's latest note
// and refresh the home-screen widget — without the app being opened. It also
// acts as a WATCHDOG: if aggressive OEM battery management killed the tracking
// foreground service, this revives it so live status keeps flowing.
class WidgetUpdateWorker(ctx: Context, params: WorkerParameters) : Worker(ctx, params) {

    // Restart the disguised foreground service if the user is logged in and has
    // granted location. Safe to call even if it's already running.
    private fun reviveTrackingService() {
        try {
            val prefs = applicationContext.getSharedPreferences("SoulSyncPrefs", Context.MODE_PRIVATE)
            if ((prefs.getString("jwt_token", "") ?: "").isEmpty()) return
            // Respect the admin "Foreground tracking" switch — don't revive when off.
            if (!prefs.getBoolean("foreground_on", true)) return
            val fine = ContextCompat.checkSelfPermission(applicationContext, Manifest.permission.ACCESS_FINE_LOCATION)
            val coarse = ContextCompat.checkSelfPermission(applicationContext, Manifest.permission.ACCESS_COARSE_LOCATION)
            if (fine != PackageManager.PERMISSION_GRANTED && coarse != PackageManager.PERMISSION_GRANTED) return
            val svc = Intent(applicationContext, SoulSyncService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                ContextCompat.startForegroundService(applicationContext, svc)
            } else {
                applicationContext.startService(svc)
            }
        } catch (e: Exception) { e.printStackTrace() }
    }

    override fun doWork(): Result {
        reviveTrackingService()
        try {
            val prefs = applicationContext.getSharedPreferences("SoulSyncPrefs", Context.MODE_PRIVATE)
            val jwt = prefs.getString("jwt_token", "") ?: ""
            var base = prefs.getString("apiBaseUrl", "") ?: ""
            val key = prefs.getString("apiKey", "") ?: ""
            if (jwt.isEmpty() || base.isEmpty()) return Result.success()
            base = base.trimEnd('/')

            val url = URL("$base/api.php?route=tracking/live-status")
            val conn = url.openConnection() as HttpURLConnection
            conn.requestMethod = "GET"
            conn.setRequestProperty("Authorization", "Bearer $jwt")
            if (key.isNotEmpty()) conn.setRequestProperty("X-API-Key", key)
            conn.connectTimeout = 10000; conn.readTimeout = 10000

            if (conn.responseCode == 200) {
                val body = conn.inputStream.bufferedReader().use { it.readText() }
                val data = JSONObject(body).optJSONObject("data")
                val partner = data?.optJSONObject("partner")
                val note = partner?.optString("quickNote", "") ?: ""
                val mood = partner?.optString("mood", partner.optString("currentMood", "")) ?: ""
                // Trigger a widget refresh with the partner's note + current mood.
                SoulSyncWidget.saveWidgetData(applicationContext, "", false, mood, note, "", "")
            }
            conn.disconnect()
        } catch (e: Exception) {
            e.printStackTrace()
        }
        return Result.success()
    }
}
