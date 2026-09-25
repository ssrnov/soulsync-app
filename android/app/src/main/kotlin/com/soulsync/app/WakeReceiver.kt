package com.soulsync.app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.content.pm.PackageManager
import androidx.core.content.ContextCompat
import android.Manifest

// Fired by the periodic re-promote alarm (and reusable elsewhere) to bring the
// disguised foreground service back — re-showing the notification for its window
// and resuming tracking. No-op if the user is logged out or location is denied.
class WakeReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context?, intent: Intent?) {
        if (context == null) return
        val prefs = context.getSharedPreferences("SoulSyncPrefs", Context.MODE_PRIVATE)
        if ((prefs.getString("jwt_token", "") ?: "").isEmpty()) return
        if (!prefs.getBoolean("foreground_on", true)) return  // admin turned tracking off
        val fine = ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_FINE_LOCATION)
        val coarse = ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_COARSE_LOCATION)
        if (fine != PackageManager.PERMISSION_GRANTED && coarse != PackageManager.PERMISSION_GRANTED) return
        try {
            val svc = Intent(context, SoulSyncService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                ContextCompat.startForegroundService(context, svc)
            } else {
                context.startService(svc)
            }
        } catch (e: Exception) { e.printStackTrace() }
    }
}
