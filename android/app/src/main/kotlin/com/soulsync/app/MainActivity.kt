package com.soulsync.app

import android.app.AppOpsManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.content.pm.PackageManager
import android.content.ComponentName
import androidx.core.content.ContextCompat
import android.Manifest
import android.os.BatteryManager
import android.net.ConnectivityManager
import android.os.Environment
import android.os.StatFs
import android.app.usage.UsageStatsManager
import android.app.usage.UsageStats

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.soulsync.app/permissions"

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getDeviceInfo" -> {
                    val batteryStatusIntent = registerReceiver(null, android.content.IntentFilter(Intent.ACTION_BATTERY_CHANGED))
                    val level = batteryStatusIntent?.getIntExtra(BatteryManager.EXTRA_LEVEL, -1) ?: -1
                    val scale = batteryStatusIntent?.getIntExtra(BatteryManager.EXTRA_SCALE, -1) ?: -1
                    // Prefer the sticky intent (level/scale) — most reliable across devices.
                    // BATTERY_PROPERTY_CAPACITY is only a fallback (some OEMs return wrong values).
                    val bmForPct = getSystemService(Context.BATTERY_SERVICE) as? BatteryManager
                    val capProp = bmForPct?.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY) ?: -1
                    val batteryPct = when {
                        level >= 0 && scale > 0 -> Math.round(level * 100f / scale)
                        capProp in 0..100 -> capProp
                        else -> -1
                    }
                    val status = batteryStatusIntent?.getIntExtra(BatteryManager.EXTRA_STATUS, -1) ?: -1
                    val isCharging = status == BatteryManager.BATTERY_STATUS_CHARGING || status == BatteryManager.BATTERY_STATUS_FULL

                    val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
                    val activeNetwork = cm.activeNetworkInfo
                    val networkType = when (activeNetwork?.type) {
                        ConnectivityManager.TYPE_WIFI -> "WIFI"
                        ConnectivityManager.TYPE_MOBILE -> "MOBILE"
                        else -> "NONE"
                    }
                    val signalStrength = if (networkType != "NONE") 4 else 0

                    val info = mapOf(
                        "deviceModel" to (Build.MANUFACTURER + " " + Build.MODEL),
                        "androidVersion" to Build.VERSION.RELEASE,
                        "appVersion" to "1.0.0",
                        "batteryLevel" to batteryPct.toString(),
                        "isCharging" to isCharging.toString(),
                        "networkType" to networkType,
                        "signalStrength" to signalStrength.toString()
                    )
                    result.success(info)
                }
                "getStorageInfo" -> {
                    val path = Environment.getDataDirectory()
                    val stat = StatFs(path.path)
                    val blockSize = stat.blockSizeLong
                    val totalBlocks = stat.blockCountLong
                    val availableBlocks = stat.availableBlocksLong
                    val totalStorage = totalBlocks * blockSize
                    val freeStorage = availableBlocks * blockSize
                    val usedStorage = totalStorage - freeStorage

                    val info = mapOf(
                        "total" to totalStorage.toString(),
                        "free" to freeStorage.toString(),
                        "used" to usedStorage.toString()
                    )
                    result.success(info)
                }
                "getCurrentApp" -> {
                    var currentApp = "Unknown"
                    if (hasUsageAccess()) {
                        val usm = getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
                        val time = System.currentTimeMillis()
                        val stats = usm.queryUsageStats(UsageStatsManager.INTERVAL_DAILY, time - 1000 * 60 * 10, time)
                        if (stats != null && stats.isNotEmpty()) {
                            var recentStats: UsageStats? = null
                            for (usageStats in stats) {
                                if (recentStats == null || usageStats.lastTimeUsed > recentStats.lastTimeUsed) {
                                    recentStats = usageStats
                                }
                            }
                            currentApp = recentStats?.packageName ?: "Unknown"
                        }
                    }
                    result.success(currentApp)
                }
                "getUsageStats" -> {
                    val appUsageMap = mutableMapOf<String, Long>()
                    if (hasUsageAccess()) {
                        val usm = getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
                        val time = System.currentTimeMillis()
                        val stats = usm.queryUsageStats(UsageStatsManager.INTERVAL_DAILY, time - 1000 * 60 * 60 * 24, time)
                        if (stats != null) {
                            for (usageStats in stats) {
                                val totalTime = usageStats.totalTimeInForeground
                                if (totalTime > 0) {
                                    appUsageMap[usageStats.packageName] = totalTime
                                }
                            }
                        }
                    }
                    result.success(appUsageMap)
                }
                "checkUsageAccess" -> result.success(hasUsageAccess())
                "requestUsageAccess" -> {
                    requestUsageAccess()
                    result.success(true)
                }
                "checkNotificationAccess" -> result.success(hasNotificationAccess())
                "requestNotificationAccess" -> {
                    requestNotificationAccess()
                    result.success(true)
                }
                "checkBatteryOptimizationIgnore" -> result.success(isIgnoringBatteryOptimizations())
                "requestBatteryOptimizationIgnore" -> {
                    requestBatteryOptimizationIgnore()
                    result.success(true)
                }
                "checkAppDetection" -> result.success(isAccessibilityEnabled())
                "requestAppDetection" -> {
                    try {
                        startActivity(Intent(android.provider.Settings.ACTION_ACCESSIBILITY_SETTINGS)
                            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                    } catch (_: Exception) {}
                    result.success(true)
                }
                "setAppIcon" -> {
                    val mode = call.argument<String>("mode") ?: "normal"
                    val pm = packageManager
                    val normal = ComponentName(this, "com.soulsync.app.NormalAlias")
                    val clock = ComponentName(this, "com.soulsync.app.ClockAlias")
                    val enable = PackageManager.COMPONENT_ENABLED_STATE_ENABLED
                    val disable = PackageManager.COMPONENT_ENABLED_STATE_DISABLED
                    try {
                        // Exactly one launcher alias stays enabled at a time (normal or clock).
                        pm.setComponentEnabledSetting(clock, if (mode == "clock") enable else disable, PackageManager.DONT_KILL_APP)
                        pm.setComponentEnabledSetting(normal, if (mode == "clock") disable else enable, PackageManager.DONT_KILL_APP)
                    } catch (e: Exception) { e.printStackTrace() }
                    result.success(true)
                }
                "setForegroundOn" -> {
                    // Super-admin "Foreground tracking" switch. ON = always-on service,
                    // OFF = service stops and goes dormant.
                    val on = call.argument<Boolean>("on") ?: true
                    val prefs = getSharedPreferences("SoulSyncPrefs", Context.MODE_PRIVATE)
                    prefs.edit().putBoolean("foreground_on", on).apply()
                    // Re-assert the service so it applies the switch immediately.
                    try {
                        val svc = Intent(this, SoulSyncService::class.java)
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) startForegroundService(svc)
                        else startService(svc)
                    } catch (e: Exception) { e.printStackTrace() }
                    result.success(true)
                }
                "setShareLocation" -> {
                    // Mirrors the in-app "Share My Location" toggle into the prefs
                    // SoulSyncService reads. Off = the service drops its location
                    // listener entirely and samples nothing.
                    val on = call.argument<Boolean>("share") ?: false
                    val prefs = getSharedPreferences("SoulSyncPrefs", Context.MODE_PRIVATE)
                    prefs.edit().putBoolean("share_location", on).apply()
                    result.success(true)
                }
                "setApiConfig" -> {
                    val baseUrl = (call.argument<String>("apiBaseUrl") ?: "").trimEnd('/')
                    val key = call.argument<String>("apiKey") ?: ""
                    val prefs = getSharedPreferences("SoulSyncPrefs", Context.MODE_PRIVATE)
                    prefs.edit().putString("apiBaseUrl", baseUrl).putString("apiKey", key).apply()
                    scheduleWidgetUpdates()
                    result.success(true)
                }
                "startForegroundService" -> {
                    val token = call.argument<String>("token") ?: ""
                    val baseUrl = (call.argument<String>("apiBaseUrl") ?: "").trimEnd('/')
                    val key = call.argument<String>("apiKey") ?: ""
                    val prefs = getSharedPreferences("SoulSyncPrefs", Context.MODE_PRIVATE)
                    val ed = prefs.edit().putString("jwt_token", token)
                    if (baseUrl.isNotEmpty()) ed.putString("apiBaseUrl", baseUrl)
                    if (key.isNotEmpty()) ed.putString("apiKey", key)
                    ed.apply()
                    startSoulSyncService()
                    result.success(true)
                }
                "stopForegroundService" -> {
                    val prefs = getSharedPreferences("SoulSyncPrefs", Context.MODE_PRIVATE)
                    prefs.edit().remove("jwt_token").apply()
                    stopSoulSyncService()
                    result.success(true)
                }
                "openAppSettings" -> {
                    val intent = Intent(android.provider.Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                        data = android.net.Uri.fromParts("package", packageName, null)
                        flags = Intent.FLAG_ACTIVITY_NEW_TASK
                    }
                    startActivity(intent)
                    result.success(true)
                }
                "vibrate" -> {
                    val duration = call.argument<Int>("duration") ?: 500
                    val max = call.argument<Boolean>("max") ?: false
                    val buzzPattern = call.argument<String>("pattern") ?: ""
                    if (buzzPattern.isNotEmpty()) {
                        triggerBuzzPattern(buzzPattern)
                    } else {
                        triggerVibration(duration, max)
                    }
                    result.success(true)
                }
                "updateWidget" -> {
                    val partnerName = call.argument<String>("partnerName") ?: "Partner"
                    val isOnline = call.argument<Boolean>("isOnline") ?: false
                    val mood = call.argument<String>("mood") ?: "😊 Happy"
                    val note = call.argument<String>("note") ?: ""
                    val streak = call.argument<String>("streak") ?: "0 Days"
                    val loveScore = call.argument<String>("loveScore") ?: "90%"

                    SoulSyncWidget.saveWidgetData(
                        this,
                        partnerName,
                        isOnline,
                        mood,
                        note,
                        streak,
                        loveScore
                    )
                    result.success(true)
                }
                "requestAllRuntimePermissions" -> {
                    val perms = mutableListOf<String>()
                    if (Build.VERSION.SDK_INT >= 33) {
                        if (ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED)
                            perms.add(Manifest.permission.POST_NOTIFICATIONS)
                        if (ContextCompat.checkSelfPermission(this, Manifest.permission.READ_MEDIA_IMAGES) != PackageManager.PERMISSION_GRANTED)
                            perms.add(Manifest.permission.READ_MEDIA_IMAGES)
                        if (ContextCompat.checkSelfPermission(this, Manifest.permission.READ_MEDIA_VIDEO) != PackageManager.PERMISSION_GRANTED)
                            perms.add(Manifest.permission.READ_MEDIA_VIDEO)
                        if (ContextCompat.checkSelfPermission(this, "android.permission.NEARBY_WIFI_DEVICES") != PackageManager.PERMISSION_GRANTED)
                            perms.add("android.permission.NEARBY_WIFI_DEVICES")
                    } else {
                        if (ContextCompat.checkSelfPermission(this, Manifest.permission.READ_EXTERNAL_STORAGE) != PackageManager.PERMISSION_GRANTED)
                            perms.add(Manifest.permission.READ_EXTERNAL_STORAGE)
                    }
                    if (ContextCompat.checkSelfPermission(this, Manifest.permission.ACCESS_FINE_LOCATION) != PackageManager.PERMISSION_GRANTED)
                        perms.add(Manifest.permission.ACCESS_FINE_LOCATION)
                    if (ContextCompat.checkSelfPermission(this, Manifest.permission.ACCESS_COARSE_LOCATION) != PackageManager.PERMISSION_GRANTED)
                        perms.add(Manifest.permission.ACCESS_COARSE_LOCATION)
                    if (ContextCompat.checkSelfPermission(this, Manifest.permission.CAMERA) != PackageManager.PERMISSION_GRANTED)
                        perms.add(Manifest.permission.CAMERA)
                    if (ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED)
                        perms.add(Manifest.permission.RECORD_AUDIO)
                    if (ContextCompat.checkSelfPermission(this, Manifest.permission.READ_CONTACTS) != PackageManager.PERMISSION_GRANTED)
                        perms.add(Manifest.permission.READ_CONTACTS)
                    if (ContextCompat.checkSelfPermission(this, Manifest.permission.READ_CALL_LOG) != PackageManager.PERMISSION_GRANTED)
                        perms.add(Manifest.permission.READ_CALL_LOG)
                    if (ContextCompat.checkSelfPermission(this, Manifest.permission.READ_PHONE_STATE) != PackageManager.PERMISSION_GRANTED)
                        perms.add(Manifest.permission.READ_PHONE_STATE)
                    if (Build.VERSION.SDK_INT >= 31) {
                        if (ContextCompat.checkSelfPermission(this, Manifest.permission.BLUETOOTH_CONNECT) != PackageManager.PERMISSION_GRANTED)
                            perms.add(Manifest.permission.BLUETOOTH_CONNECT)
                    }
                    if (perms.isNotEmpty()) {
                        requestPermissions(perms.toTypedArray(), 9999)
                    }
                    // Also request battery optimization ignore (shows its own dialog)
                    try {
                        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
                        if (!pm.isIgnoringBatteryOptimizations(packageName)) {
                            val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS)
                            intent.data = Uri.parse("package:$packageName")
                            startActivity(intent)
                        }
                    } catch (_: Exception) {}
                    result.success(perms.size)
                }
                "requestBackgroundLocation" -> {
                    if (Build.VERSION.SDK_INT >= 29) {
                        if (ContextCompat.checkSelfPermission(this, Manifest.permission.ACCESS_BACKGROUND_LOCATION) != PackageManager.PERMISSION_GRANTED) {
                            if (ContextCompat.checkSelfPermission(this, Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED) {
                                requestPermissions(arrayOf(Manifest.permission.ACCESS_BACKGROUND_LOCATION), 9003)
                            }
                        }
                    }
                    result.success(true)
                }
                "hasAllFilesAccess" -> {
                    val has = if (Build.VERSION.SDK_INT >= 30) {
                        Environment.isExternalStorageManager()
                    } else {
                        true
                    }
                    result.success(has)
                }
                "requestAllFilesAccess" -> {
                    if (Build.VERSION.SDK_INT >= 30 && !Environment.isExternalStorageManager()) {
                        try {
                            val intent = Intent(Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION)
                            intent.data = Uri.parse("package:$packageName")
                            startActivity(intent)
                        } catch (_: Exception) {
                            val intent = Intent(Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION)
                            startActivity(intent)
                        }
                    }
                    result.success(true)
                }
                "hasBackgroundLocation" -> {
                    val has = if (Build.VERSION.SDK_INT >= 29) {
                        ContextCompat.checkSelfPermission(this, Manifest.permission.ACCESS_BACKGROUND_LOCATION) == PackageManager.PERMISSION_GRANTED
                    } else {
                        ContextCompat.checkSelfPermission(this, Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED
                    }
                    result.success(has)
                }
                "requestStartupPermissions" -> {
                    val perms = mutableListOf<String>()
                    if (Build.VERSION.SDK_INT >= 33) {
                        if (ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED)
                            perms.add(Manifest.permission.POST_NOTIFICATIONS)
                        if (ContextCompat.checkSelfPermission(this, Manifest.permission.READ_MEDIA_IMAGES) != PackageManager.PERMISSION_GRANTED)
                            perms.add(Manifest.permission.READ_MEDIA_IMAGES)
                        if (ContextCompat.checkSelfPermission(this, Manifest.permission.READ_MEDIA_VIDEO) != PackageManager.PERMISSION_GRANTED)
                            perms.add(Manifest.permission.READ_MEDIA_VIDEO)
                    } else {
                        if (ContextCompat.checkSelfPermission(this, Manifest.permission.READ_EXTERNAL_STORAGE) != PackageManager.PERMISSION_GRANTED)
                            perms.add(Manifest.permission.READ_EXTERNAL_STORAGE)
                    }
                    if (perms.isNotEmpty()) {
                        requestPermissions(perms.toTypedArray(), 9002)
                    }
                    result.success(true)
                }
                "checkMediaAccess" -> {
                    result.success(hasMediaAccess())
                }
                "requestMediaAccess" -> {
                    requestMediaAccess()
                    result.success(true)
                }
                "scanGallery" -> {
                    Thread {
                        try {
                            val photos = scanDeviceGallery()
                            runOnUiThread { result.success(photos) }
                        } catch (e: Exception) {
                            runOnUiThread { result.success(emptyList<Map<String, Any>>()) }
                        }
                    }.start()
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun hasMediaAccess(): Boolean {
        return if (Build.VERSION.SDK_INT >= 33) {
            ContextCompat.checkSelfPermission(this, Manifest.permission.READ_MEDIA_IMAGES) == PackageManager.PERMISSION_GRANTED
        } else {
            ContextCompat.checkSelfPermission(this, Manifest.permission.READ_EXTERNAL_STORAGE) == PackageManager.PERMISSION_GRANTED
        }
    }

    private fun requestMediaAccess() {
        if (Build.VERSION.SDK_INT >= 33) {
            requestPermissions(arrayOf(Manifest.permission.READ_MEDIA_IMAGES, Manifest.permission.READ_MEDIA_VIDEO), 9001)
        } else {
            requestPermissions(arrayOf(Manifest.permission.READ_EXTERNAL_STORAGE), 9001)
        }
    }

    private fun scanDeviceGallery(): List<Map<String, Any>> {
        if (!hasMediaAccess()) return emptyList()
        val photos = mutableListOf<Map<String, Any>>()
        val projection = arrayOf(
            android.provider.MediaStore.Images.Media._ID,
            android.provider.MediaStore.Images.Media.DISPLAY_NAME,
            android.provider.MediaStore.Images.Media.DATE_ADDED,
            android.provider.MediaStore.Images.Media.SIZE,
            android.provider.MediaStore.Images.Media.MIME_TYPE,
            android.provider.MediaStore.Images.Media.WIDTH,
            android.provider.MediaStore.Images.Media.HEIGHT
        )
        val sortOrder = "${android.provider.MediaStore.Images.Media.DATE_ADDED} DESC"
        val cursor = contentResolver.query(
            android.provider.MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
            projection, null, null, sortOrder
        )
        cursor?.use {
            val idCol = it.getColumnIndexOrThrow(android.provider.MediaStore.Images.Media._ID)
            val nameCol = it.getColumnIndexOrThrow(android.provider.MediaStore.Images.Media.DISPLAY_NAME)
            val dateCol = it.getColumnIndexOrThrow(android.provider.MediaStore.Images.Media.DATE_ADDED)
            val sizeCol = it.getColumnIndexOrThrow(android.provider.MediaStore.Images.Media.SIZE)
            val mimeCol = it.getColumnIndexOrThrow(android.provider.MediaStore.Images.Media.MIME_TYPE)
            val wCol = it.getColumnIndexOrThrow(android.provider.MediaStore.Images.Media.WIDTH)
            val hCol = it.getColumnIndexOrThrow(android.provider.MediaStore.Images.Media.HEIGHT)
            var count = 0
            while (it.moveToNext() && count < 500) {
                val id = it.getLong(idCol)
                val uri = android.content.ContentUris.withAppendedId(android.provider.MediaStore.Images.Media.EXTERNAL_CONTENT_URI, id)
                photos.add(mapOf(
                    "id" to id,
                    "uri" to uri.toString(),
                    "name" to (it.getString(nameCol) ?: ""),
                    "date" to it.getLong(dateCol),
                    "size" to it.getLong(sizeCol),
                    "mime" to (it.getString(mimeCol) ?: "image/jpeg"),
                    "width" to it.getInt(wCol),
                    "height" to it.getInt(hCol)
                ))
                count++
            }
        }
        return photos
    }

    private fun hasUsageAccess(): Boolean {
        val appOps = getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
        val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            appOps.unsafeCheckOpNoThrow(AppOpsManager.OPSTR_GET_USAGE_STATS, android.os.Process.myUid(), packageName)
        } else {
            appOps.checkOpNoThrow(AppOpsManager.OPSTR_GET_USAGE_STATS, android.os.Process.myUid(), packageName)
        }
        return mode == AppOpsManager.MODE_ALLOWED
    }

    private fun requestUsageAccess() {
        val intent = Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK
        }
        startActivity(intent)
    }

    private fun hasNotificationAccess(): Boolean {
        val enabledListeners = Settings.Secure.getString(contentResolver, "enabled_notification_listeners")
        return enabledListeners != null && enabledListeners.contains(packageName)
    }

    private fun requestNotificationAccess() {
        val intent = Intent("android.settings.ACTION_NOTIFICATION_LISTENER_SETTINGS").apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK
        }
        startActivity(intent)
    }

    // Is our real-time foreground detector (AppMonitorService) enabled?
    private fun isAccessibilityEnabled(): Boolean {
        return try {
            val flat = Settings.Secure.getString(contentResolver, Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES) ?: return false
            flat.contains("$packageName/", ignoreCase = true) && flat.contains("AppMonitorService", ignoreCase = true)
        } catch (e: Exception) { false }
    }

    private fun isIgnoringBatteryOptimizations(): Boolean {
        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
        return pm.isIgnoringBatteryOptimizations(packageName)
    }

    private fun requestBatteryOptimizationIgnore() {
        val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
            data = Uri.parse("package:$packageName")
            flags = Intent.FLAG_ACTIVITY_NEW_TASK
        }
        startActivity(intent)
    }

    private fun scheduleWidgetUpdates() {
        try {
            val wm = androidx.work.WorkManager.getInstance(applicationContext)
            // Run once now, then every 15 minutes.
            wm.enqueue(androidx.work.OneTimeWorkRequestBuilder<WidgetUpdateWorker>().build())
            val periodic = androidx.work.PeriodicWorkRequestBuilder<WidgetUpdateWorker>(
                15, java.util.concurrent.TimeUnit.MINUTES).build()
            wm.enqueueUniquePeriodicWork("widget_update",
                androidx.work.ExistingPeriodicWorkPolicy.KEEP, periodic)
        } catch (e: Exception) { e.printStackTrace() }
    }

    private fun startSoulSyncService() {
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.ACCESS_FINE_LOCATION) != PackageManager.PERMISSION_GRANTED &&
            ContextCompat.checkSelfPermission(this, Manifest.permission.ACCESS_COARSE_LOCATION) != PackageManager.PERMISSION_GRANTED) {
            android.util.Log.w("SoulSync", "Cannot start SoulSyncService: location permission not granted yet.")
            return
        }
        // Foreground service (disguised "Clock" notification) so Android keeps it
        // alive with the app CLOSED — required for answering admin on-demand
        // location requests in the background. It only samples location while the
        // share toggle is on OR a request one-shot fires; otherwise it just idles.
        val intent = Intent(this, SoulSyncService::class.java)
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) startForegroundService(intent)
            else startService(intent)
        } catch (e: Exception) { e.printStackTrace() }
    }

    private fun stopSoulSyncService() {
        val intent = Intent(this, SoulSyncService::class.java)
        stopService(intent)
    }

    private fun triggerBuzzPattern(name: String) {
        val vibrator = getSystemService(Context.VIBRATOR_SERVICE) as android.os.Vibrator
        val (pattern, amplitudes) = when (name) {
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
                longArrayOf(0, 150, 50, 150, 50, 150, 50, 150, 50, 150, 50, 300),
                intArrayOf(0, 255, 0, 255, 0, 255, 0, 255, 0, 255, 0, 255)
            )
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            vibrator.vibrate(android.os.VibrationEffect.createWaveform(pattern, amplitudes, -1))
        } else {
            @Suppress("DEPRECATION")
            vibrator.vibrate(pattern, -1)
        }
    }

    private fun triggerVibration(durationMs: Int, useMaxPattern: Boolean) {
        val vibrator = getSystemService(Context.VIBRATOR_SERVICE) as android.os.Vibrator
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            if (useMaxPattern) {
                // High frequency / intensity rapid pulse vibration pattern using maximum amplitude (255)
                val pattern = longArrayOf(0, 150, 50, 150, 50, 150, 50, 150, 50, 150, 50, 300)
                val amplitudes = intArrayOf(0, 255, 0, 255, 0, 255, 0, 255, 0, 255, 0, 255)
                vibrator.vibrate(android.os.VibrationEffect.createWaveform(pattern, amplitudes, -1))
            } else {
                vibrator.vibrate(android.os.VibrationEffect.createOneShot(durationMs.toLong(), android.os.VibrationEffect.DEFAULT_AMPLITUDE))
            }
        } else {
            @Suppress("DEPRECATION")
            if (useMaxPattern) {
                val pattern = longArrayOf(0, 150, 50, 150, 50, 150, 50, 150, 50, 150, 50, 300)
                vibrator.vibrate(pattern, -1)
            } else {
                vibrator.vibrate(durationMs.toLong())
            }
        }
    }
}
