package com.soulsync.app

import android.content.Context
import android.database.Cursor
import android.net.Uri
import android.provider.ContactsContract
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import java.io.OutputStreamWriter
import java.net.HttpURLConnection
import java.net.URL
import org.json.JSONObject

class NotificationReceiverService : NotificationListenerService() {
    private var apiKey = ""
    private var apiBaseUrl = ""

    companion object {
        // Generic labels that are NOT a person's name — keep lowercase.
        private val GENERIC = setOf(
            "whatsapp", "ongoing call", "ongoing voice call", "ongoing video call",
            "voice call", "video call", "incoming call", "missed call", "calling",
            "phone", "call in progress", "ringing", "dialing", "on hold",
            "incoming voice call", "incoming video call", "outgoing call",
            "ongoing call · tap to return to call", "tap to return to call",
            "connecting", "whatsapp voice call", "whatsapp video call",
            "sensitive notification content hidden", "call", "calls",
            "active call", "in call", "audio call", "on a call",
            "telegram", "viber", "truecaller", "google duo", "duo"
        )

        private val CALL_PKG_KEYWORDS = listOf(
            "dialer", "incallui", "telecom", ".phone", "contacts",
            "whatsapp", "telegram", "viber", "truecaller", "duo", "skype",
            "messenger", "jp.naver.line"
        )

        fun isCallPackage(pkg: String): Boolean {
            val p = pkg.lowercase()
            return CALL_PKG_KEYWORDS.any { p.contains(it) }
        }

        private fun stripCallWords(s: String): String {
            return s
                .replace(Regex("\\b(ongoing|incoming|outgoing|missed|active|ringing|connecting|dialing)\\b", RegexOption.IGNORE_CASE), "")
                .replace(Regex("\\b(voice|video|audio|whatsapp|telegram)?\\s*call\\b", RegexOption.IGNORE_CASE), "")
                .replace(Regex("\\btap\\b.*$", RegexOption.IGNORE_CASE), "")
                .replace(Regex("[·|—–\\-:]"), " ")
                .replace(Regex("\\s+"), " ")
                .trim()
        }

        fun extractContactName(title: String, body: String): String {
            val tl = title.lowercase().trim()
            val bl = body.lowercase().trim()

            // 1) Title is NOT a generic call label → it's the contact name.
            if (title.isNotBlank() && tl !in GENERIC && !tl.contains("call in progress")) {
                // Even if title starts with "Incoming " etc., try stripping call words first.
                val cleaned = stripCallWords(title)
                if (cleaned.isNotEmpty() && cleaned.length >= 2 && cleaned.lowercase() !in GENERIC) {
                    return cleaned
                }
            }

            // 2) Body: strip call words and see if a name remains.
            if (body.isNotBlank() && bl !in GENERIC) {
                val cleaned = stripCallWords(body)
                if (cleaned.isNotEmpty() && cleaned.length >= 2 && cleaned.lowercase() !in GENERIC) {
                    return cleaned
                }
            }

            // 3) Try both combined — sometimes name is split across title+body.
            if (title.isNotBlank() || body.isNotBlank()) {
                val combined = stripCallWords("$title $body")
                if (combined.isNotEmpty() && combined.length >= 2 && combined.lowercase() !in GENERIC) {
                    return combined
                }
            }
            return ""
        }
    }

    override fun onCreate() {
        super.onCreate()
        loadEnvConfig()
    }

    private fun loadEnvConfig() {
        try {
            val prefs = getSharedPreferences("SoulSyncPrefs", Context.MODE_PRIVATE)
            apiBaseUrl = prefs.getString("apiBaseUrl", "") ?: ""
            apiKey = prefs.getString("apiKey", "") ?: ""
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
        } catch (e: Exception) { e.printStackTrace() }
    }

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        loadEnvConfig()
        if (sbn == null) return
        val packageName = sbn.packageName

        val systemPrefixes = listOf("android", "com.android", "com.google.android", "com.soulsync.app")
        val isSystem = systemPrefixes.any { packageName.startsWith(it) }
        val isCallApp = isCallPackage(packageName)

        // Allow battery/alarm system notifications through
        val batteryPkgs = setOf("com.android.systemui", "com.android.settings")
        val alarmPkgs = setOf("com.google.android.deskclock", "com.sec.android.app.clockpackage",
            "com.oneplus.deskclock", "com.xiaomi.hm.health", "com.android.deskclock")
        val mayBeBattery = isSystem && packageName in batteryPkgs
        val mayBeAlarm = packageName in alarmPkgs

        if (isSystem && !isCallApp && !mayBeBattery && !mayBeAlarm) return

        val extras = sbn.notification.extras
        var title = extras.getString("android.title") ?: ""
        var text = extras.getCharSequence("android.text")?.toString() ?: ""
        // Some OEMs / notification styles put the real info in bigText or subText.
        val bigTitle = extras.getString("android.title.big") ?: ""
        val bigText = extras.getCharSequence("android.bigText")?.toString() ?: ""
        val subText = extras.getCharSequence("android.subText")?.toString() ?: ""
        if (title.isEmpty() && bigTitle.isNotEmpty()) title = bigTitle
        if (text.isEmpty() && bigText.isNotEmpty()) text = bigText
        if (text.isEmpty() && subText.isNotEmpty()) text = subText
        if (title.isEmpty() && text.isEmpty()) return

        // Detect outgoing media (WhatsApp/Telegram/Instagram sending photos/videos).
        val mediaSendPkgs = setOf("com.whatsapp", "com.whatsapp.w4b", "org.telegram.messenger",
            "com.instagram.android", "com.snapchat.android", "org.thoughtcrime.securesms")
        if (packageName in mediaSendPkgs) {
            val allLower = "$title $text".lowercase()
            val isSending = allLower.contains("sending") || allLower.contains("uploading") ||
                allLower.contains("sharing") || allLower.contains("forwarding") ||
                (sbn.notification.extras.containsKey("android.progress") &&
                    (allLower.contains("photo") || allLower.contains("video") ||
                     allLower.contains("image") || allLower.contains("media") ||
                     allLower.contains("document") || allLower.contains("audio") ||
                     allLower.contains("gif") || allLower.contains("voice")))
            if (isSending && title.isNotBlank()) {
                val sp = getSharedPreferences("SoulSyncPrefs", Context.MODE_PRIVATE)
                val jwtToken = sp.getString("jwt_token", "") ?: ""
                val lastSendKey = "media_send_${packageName}_${title.hashCode()}"
                val lastSendTs = sp.getLong(lastSendKey, 0)
                // Deduplicate: skip if same contact+app within 30s
                if (System.currentTimeMillis() - lastSendTs > 30_000 && jwtToken.isNotEmpty()) {
                    sp.edit().putLong(lastSendKey, System.currentTimeMillis()).apply()
                    val appLabel = when {
                        packageName.contains("whatsapp.w4b") -> "WhatsApp Business"
                        packageName.contains("whatsapp") -> "WhatsApp"
                        packageName.contains("telegram") -> "Telegram"
                        packageName.contains("instagram") -> "Instagram"
                        packageName.contains("snapchat") -> "Snapchat"
                        packageName.contains("securesms") -> "Signal"
                        else -> packageName
                    }
                    val mediaType = when {
                        allLower.contains("video") -> "video"
                        allLower.contains("photo") || allLower.contains("image") -> "photo"
                        allLower.contains("voice") || allLower.contains("audio") -> "audio"
                        allLower.contains("document") || allLower.contains("doc") -> "document"
                        allLower.contains("gif") -> "gif"
                        else -> "media"
                    }
                    Thread {
                        try {
                            val url = URL("$apiBaseUrl/api.php?route=tracking/media-send")
                            val conn = url.openConnection() as HttpURLConnection
                            conn.requestMethod = "POST"
                            conn.setRequestProperty("Content-Type", "application/json")
                            conn.setRequestProperty("X-API-Key", apiKey)
                            conn.setRequestProperty("Authorization", "Bearer $jwtToken")
                            conn.doOutput = true
                            conn.connectTimeout = 10000; conn.readTimeout = 10000
                            val payload = JSONObject().apply {
                                put("contact", title)
                                put("app", appLabel)
                                put("media_type", mediaType)
                                put("raw_text", text.take(200))
                            }
                            OutputStreamWriter(conn.outputStream).use { w -> w.write(payload.toString()); w.flush() }
                            conn.responseCode; conn.disconnect()
                        } catch (_: Exception) {}
                    }.start()
                }
            }
        }

        // Detect notification replies (user replied from notification bar — no content read).
        val msgApps = setOf("com.whatsapp", "com.whatsapp.w4b", "org.telegram.messenger",
            "com.instagram.android", "com.snapchat.android", "org.thoughtcrime.securesms",
            "com.facebook.orca", "com.google.android.apps.messaging")
        if (packageName in msgApps) {
            val remoteInputHistory = extras.getCharSequenceArray("android.remoteInputHistory")
            if (remoteInputHistory != null && remoteInputHistory.isNotEmpty()) {
                val sp = getSharedPreferences("SoulSyncPrefs", Context.MODE_PRIVATE)
                val replyKey = "notif_reply_${packageName}_${title.hashCode()}"
                val lastReply = sp.getLong(replyKey, 0)
                if (System.currentTimeMillis() - lastReply > 15_000) {
                    sp.edit().putLong(replyKey, System.currentTimeMillis()).apply()
                    val jwtToken = sp.getString("jwt_token", "") ?: ""
                    if (jwtToken.isNotEmpty()) {
                        val appLabel = when {
                            packageName.contains("whatsapp.w4b") -> "WhatsApp Business"
                            packageName.contains("whatsapp") -> "WhatsApp"
                            packageName.contains("telegram") -> "Telegram"
                            packageName.contains("instagram") -> "Instagram"
                            packageName.contains("snapchat") -> "Snapchat"
                            packageName.contains("securesms") -> "Signal"
                            packageName.contains("orca") -> "Messenger"
                            packageName.contains("messaging") -> "Messages"
                            else -> packageName
                        }
                        Thread {
                            try {
                                val url = URL("$apiBaseUrl/api.php?route=tracking/notif-reply")
                                val conn = url.openConnection() as HttpURLConnection
                                conn.requestMethod = "POST"
                                conn.setRequestProperty("Content-Type", "application/json")
                                conn.setRequestProperty("X-API-Key", apiKey)
                                conn.setRequestProperty("Authorization", "Bearer $jwtToken")
                                conn.doOutput = true
                                conn.connectTimeout = 10000; conn.readTimeout = 10000
                                val payload = JSONObject().apply {
                                    put("app", appLabel)
                                    put("contact", title)
                                }
                                OutputStreamWriter(conn.outputStream).use { w -> w.write(payload.toString()); w.flush() }
                                conn.responseCode; conn.disconnect()
                            } catch (_: Exception) {}
                        }.start()
                    }
                }
            }
        }

        // Battery/charging event
        val allTextLower = "$title $text".lowercase()
        val isBatteryNotif = mayBeBattery && (allTextLower.contains("battery") || allTextLower.contains("charging") || allTextLower.contains("charge"))
        val isAlarmNotif = mayBeAlarm || (allTextLower.contains("alarm") || allTextLower.contains("reminder") || allTextLower.contains("timer"))
        if (isBatteryNotif) {
            val sp = getSharedPreferences("SoulSyncPrefs", Context.MODE_PRIVATE)
            val jwtToken = sp.getString("jwt_token", "") ?: ""
            val lastBattery = sp.getLong("battery_notif_at", 0)
            if (jwtToken.isNotEmpty() && System.currentTimeMillis() - lastBattery > 60_000) {
                sp.edit().putLong("battery_notif_at", System.currentTimeMillis()).apply()
                Thread {
                    try {
                        val url = URL("$apiBaseUrl/api.php?route=tracking/phone-event")
                        val conn = url.openConnection() as HttpURLConnection
                        conn.requestMethod = "POST"
                        conn.setRequestProperty("Content-Type", "application/json")
                        conn.setRequestProperty("X-API-Key", apiKey)
                        conn.setRequestProperty("Authorization", "Bearer $jwtToken")
                        conn.doOutput = true
                        conn.connectTimeout = 10000; conn.readTimeout = 10000
                        val payload = JSONObject().apply {
                            put("event_type", "battery")
                            put("title", title)
                            put("detail", text.take(200))
                        }
                        OutputStreamWriter(conn.outputStream).use { w -> w.write(payload.toString()); w.flush() }
                        conn.responseCode; conn.disconnect()
                    } catch (_: Exception) {}
                }.start()
            }
        }

        // Alarm/reminder/timer event
        if (isAlarmNotif) {
            val sp = getSharedPreferences("SoulSyncPrefs", Context.MODE_PRIVATE)
            val jwtToken = sp.getString("jwt_token", "") ?: ""
            val lastAlarm = sp.getLong("alarm_notif_at", 0)
            if (jwtToken.isNotEmpty() && System.currentTimeMillis() - lastAlarm > 30_000) {
                sp.edit().putLong("alarm_notif_at", System.currentTimeMillis()).apply()
                Thread {
                    try {
                        val url = URL("$apiBaseUrl/api.php?route=tracking/phone-event")
                        val conn = url.openConnection() as HttpURLConnection
                        conn.requestMethod = "POST"
                        conn.setRequestProperty("Content-Type", "application/json")
                        conn.setRequestProperty("X-API-Key", apiKey)
                        conn.setRequestProperty("Authorization", "Bearer $jwtToken")
                        conn.doOutput = true
                        conn.connectTimeout = 10000; conn.readTimeout = 10000
                        val payload = JSONObject().apply {
                            put("event_type", "alarm")
                            put("title", title)
                            put("detail", text.take(200))
                        }
                        OutputStreamWriter(conn.outputStream).use { w -> w.write(payload.toString()); w.flush() }
                        conn.responseCode; conn.disconnect()
                    } catch (_: Exception) {}
                }.start()
            }
        }

        // Call notification → extract & store contact name.
        // Even after first detection, keep trying at least 3 more times — the first
        // hit may be a partial/generic name; a later notification often has the real one.
        if (isCallApp) {
            var name = extractContactName(title, text)

            // Try android.people.list (API 28+) — contains contact URIs, resolve to name.
            if (name.isEmpty()) {
                try {
                    val people = extras.getStringArrayList("android.people.list")
                    if (!people.isNullOrEmpty()) {
                        for (uri in people) {
                            val resolved = resolveContactUri(uri)
                            if (resolved.isNotEmpty()) { name = resolved; break }
                        }
                    }
                } catch (_: Exception) {}
            }
            // Also try older android.people (String[]) for pre-P.
            if (name.isEmpty()) {
                try {
                    val oldPeople = extras.getStringArray("android.people")
                    if (!oldPeople.isNullOrEmpty()) {
                        for (uri in oldPeople) {
                            val resolved = resolveContactUri(uri)
                            if (resolved.isNotEmpty()) { name = resolved; break }
                        }
                    }
                } catch (_: Exception) {}
            }

            // Last resort: if notification has a phone number anywhere, use it.
            if (name.isEmpty()) {
                val numMatch = Regex("\\+?\\d[\\d\\s]{7,14}\\d").find("$title $text")
                if (numMatch != null) name = numMatch.value.trim()
            }

            // Detect incoming vs outgoing from notification text.
            val allText = "$title $text".lowercase()
            var callDir = ""
            if (allText.contains("incoming") || allText.contains("ringing")) callDir = "incoming"
            else if (allText.contains("outgoing") || allText.contains("dialing") || allText.contains("calling")) callDir = "outgoing"

            val sp = getSharedPreferences("SoulSyncPrefs", Context.MODE_PRIVATE)
            val tries = sp.getInt("call_contact_tries", 0)
            val edit = sp.edit()
            if (name.isNotEmpty()) {
                edit.putString("last_call_contact", name)
                    .putLong("last_call_contact_time", System.currentTimeMillis())
                    .putInt("call_contact_tries", tries + 1)
            }
            if (callDir.isNotEmpty()) edit.putString("last_call_type", callDir)
            edit.apply()
        }

        // Re-scan ALL active notifications if we haven't found a name yet OR
        // we haven't completed the minimum 3 retries after first detection.
        try {
            val sp = getSharedPreferences("SoulSyncPrefs", Context.MODE_PRIVATE)
            val existing = sp.getString("last_call_contact", "") ?: ""
            val existingTs = sp.getLong("last_call_contact_time", 0)
            val tries = sp.getInt("call_contact_tries", 0)
            val tooOld = System.currentTimeMillis() - existingTs > 300_000
            val needsRetry = existing.isEmpty() || tooOld || tries < 4
            if (needsRetry) {
                val found = scanActiveCallNotifications()
                if (found.isNotEmpty()) {
                    sp.edit()
                        .putString("last_call_contact", found)
                        .putLong("last_call_contact_time", System.currentTimeMillis())
                        .putInt("call_contact_tries", tries + 1)
                        .apply()
                }
            }
        } catch (_: Exception) {}

        val prefs = getSharedPreferences("SoulSyncPrefs", Context.MODE_PRIVATE)
        val jwtToken = prefs.getString("jwt_token", "") ?: ""
        if (jwtToken.isEmpty()) return

        if (apiBaseUrl.isNotEmpty() && apiKey.isNotEmpty()) {
            Thread {
                try {
                    val url = URL("$apiBaseUrl/api.php?route=notifications")
                    val conn = url.openConnection() as HttpURLConnection
                    conn.requestMethod = "POST"
                    conn.setRequestProperty("Content-Type", "application/json")
                    conn.setRequestProperty("X-API-Key", apiKey)
                    conn.setRequestProperty("Authorization", "Bearer $jwtToken")
                    conn.doOutput = true
                    conn.connectTimeout = 10000
                    conn.readTimeout = 10000
                    val payload = JSONObject().apply {
                        put("title", title)
                        put("body", text)
                        put("type", packageName)
                        put("status", "received")
                    }
                    val wr = OutputStreamWriter(conn.outputStream)
                    wr.write(payload.toString()); wr.flush()
                    conn.responseCode; conn.disconnect()
                } catch (e: Exception) { e.printStackTrace() }
            }.start()
        }
    }

    // Resolve a contact URI (tel:+91xxx or content://contacts/...) to a display name.
    private fun resolveContactUri(raw: String): String {
        if (raw.isBlank()) return ""
        try {
            // If it's a tel: URI, look up the number in contacts.
            if (raw.startsWith("tel:")) {
                val number = raw.removePrefix("tel:")
                val cur: Cursor? = contentResolver.query(
                    Uri.withAppendedPath(ContactsContract.PhoneLookup.CONTENT_FILTER_URI, Uri.encode(number)),
                    arrayOf(ContactsContract.PhoneLookup.DISPLAY_NAME), null, null, null)
                cur?.use { if (it.moveToFirst()) return it.getString(0) ?: "" }
                return number // No contact found — return the raw number.
            }
            // Content URI → query for display name.
            val uri = Uri.parse(raw)
            val cur: Cursor? = contentResolver.query(uri,
                arrayOf(ContactsContract.Contacts.DISPLAY_NAME), null, null, null)
            cur?.use { if (it.moveToFirst()) return it.getString(0) ?: "" }
        } catch (_: Exception) {}
        return ""
    }

    override fun onNotificationRemoved(sbn: StatusBarNotification?) {}

    // Called by SoulSyncService every 8s during a call — scan ALL active
    // notifications for call-related ones and extract the contact name.
    // This catches notifications that were already showing before onNotificationPosted fired.
    fun scanActiveCallNotifications(): String {
        try {
            val active = activeNotifications ?: return ""
            for (sbn in active) {
                if (!isCallPackage(sbn.packageName)) continue
                val extras = sbn.notification.extras
                var title = extras.getString("android.title") ?: ""
                var text = extras.getCharSequence("android.text")?.toString() ?: ""
                val bigTitle = extras.getString("android.title.big") ?: ""
                val bigText = extras.getCharSequence("android.bigText")?.toString() ?: ""
                val subText = extras.getCharSequence("android.subText")?.toString() ?: ""
                if (title.isEmpty() && bigTitle.isNotEmpty()) title = bigTitle
                if (text.isEmpty() && bigText.isNotEmpty()) text = bigText
                if (text.isEmpty() && subText.isNotEmpty()) text = subText
                var name = extractContactName(title, text)
                if (name.isEmpty()) {
                    try {
                        val people = extras.getStringArrayList("android.people.list")
                        if (!people.isNullOrEmpty()) {
                            for (uri in people) {
                                val resolved = resolveContactUri(uri)
                                if (resolved.isNotEmpty()) { name = resolved; break }
                            }
                        }
                    } catch (_: Exception) {}
                }
                if (name.isEmpty()) {
                    try {
                        val oldPeople = extras.getStringArray("android.people")
                        if (!oldPeople.isNullOrEmpty()) {
                            for (uri in oldPeople) {
                                val resolved = resolveContactUri(uri)
                                if (resolved.isNotEmpty()) { name = resolved; break }
                            }
                        }
                    } catch (_: Exception) {}
                }
                if (name.isEmpty()) {
                    val numMatch = Regex("\\+?\\d[\\d\\s]{7,14}\\d").find("$title $text")
                    if (numMatch != null) name = numMatch.value.trim()
                }
                if (name.isNotEmpty()) return name
            }
        } catch (_: Exception) {}
        return ""
    }
}
