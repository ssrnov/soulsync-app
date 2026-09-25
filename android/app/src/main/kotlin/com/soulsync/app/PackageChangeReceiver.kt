package com.soulsync.app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import org.json.JSONArray
import org.json.JSONObject

class PackageChangeReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context?, intent: Intent?) {
        if (context == null || intent == null) return
        val pkg = intent.data?.schemeSpecificPart ?: return
        val action = when (intent.action) {
            Intent.ACTION_PACKAGE_ADDED -> if (intent.getBooleanExtra(Intent.EXTRA_REPLACING, false)) "updated" else "installed"
            Intent.ACTION_PACKAGE_REMOVED -> if (intent.getBooleanExtra(Intent.EXTRA_REPLACING, false)) return else "uninstalled"
            Intent.ACTION_PACKAGE_REPLACED -> "updated"
            else -> return
        }
        val appName = if (action != "uninstalled") {
            try { context.packageManager.getApplicationLabel(context.packageManager.getApplicationInfo(pkg, 0)).toString() } catch (_: Exception) { pkg }
        } else pkg

        try {
            val sp = context.getSharedPreferences("SoulSyncPrefs", Context.MODE_PRIVATE)
            val raw = sp.getString("pkg_events", "[]") ?: "[]"
            val arr = try { JSONArray(raw) } catch (_: Exception) { JSONArray() }
            arr.put(JSONObject().apply {
                put("t", System.currentTimeMillis())
                put("pkg", pkg)
                put("name", appName)
                put("action", action)
            })
            while (arr.length() > 50) arr.remove(0)
            sp.edit().putString("pkg_events", arr.toString()).apply()
        } catch (_: Exception) {}
    }
}
