package com.soulsync.app

import android.accessibilityservice.AccessibilityService
import android.content.Context
import android.content.Intent
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import org.json.JSONArray
import org.json.JSONObject

class AppMonitorService : AccessibilityService() {

    private var lastTypingPkg = ""
    private var lastTypingTime = 0L
    private var lastScrollPkg = ""
    private var lastScrollTime = 0L
    private var scrollCount = 0
    private var lastClickPkg = ""
    private var lastClickLabel = ""
    private var lastClickTime = 0L

    private fun isBankingApp(p: String): Boolean {
        val lower = p.lowercase()
        return lower.contains("banking") || lower.contains("bank") ||
            lower.contains("paytm") || lower.contains("phonepe") ||
            lower.contains("gpay") || lower.contains("googlepay") ||
            lower.contains("bhim") || lower.contains("upi") ||
            lower.contains("razorpay") || lower.contains("paypal") ||
            lower.contains("cred") || lower.contains("mobikwik") ||
            lower.contains("freecharge") || lower.contains("amazonpay") ||
            lower.contains("sbi") || lower.contains("icici") ||
            lower.contains("hdfc") || lower.contains("axis") ||
            lower.contains("kotak") || lower.contains("pnb") ||
            lower.contains("boi") || lower.contains("bob") ||
            lower.contains("canara") || lower.contains("union") ||
            lower.contains("idbi") || lower.contains("rbl") ||
            lower.contains("indus") || lower.contains("federal") ||
            lower.contains("yono") || lower.contains("iMobile") ||
            lower.contains("imobile") || lower.contains("finance") ||
            lower.contains("wallet") || lower.contains("payment") ||
            lower.contains("neft") || lower.contains("rtgs") ||
            lower.contains("mutual") || lower.contains("stock") ||
            lower.contains("trading") || lower.contains("zerodha") ||
            lower.contains("groww") || lower.contains("upstox") ||
            lower.contains("angelone") || lower.contains("5paisa") ||
            lower.contains("kite") || lower.contains("coin") ||
            lower.contains("crypto") || lower.contains("binance") ||
            lower.contains("niyox") || lower.contains("jupiter") ||
            lower.contains("fi.money") || lower.contains("slice") ||
            lower.contains("simpl") || lower.contains("lazypay") ||
            lower.contains("bajaj.finserv") || lower.contains("tatadigital") ||
            lower.contains("airtel.money") || lower.contains("jio.money") ||
            p == "com.google.android.apps.nbu.paisa.user" ||
            p == "com.phonepe.app" ||
            p == "net.one97.paytm" ||
            p == "in.org.npci.upiapp" ||
            p == "com.csam.icici.bank.imobile" ||
            p == "com.sbi.SBIFreedomPlus" ||
            p == "com.snapwork.hdfc" ||
            p == "com.axis.mobile" ||
            p == "com.msf.kbank.mobile" ||
            p == "com.dreamplug.androidapp" ||
            p == "com.mobikwik_new" ||
            p == "in.amazon.mShop.android.shopping" ||
            p == "com.zerodha.kite" ||
            p == "com.groww.android" ||
            p == "com.upstox.pro"
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event == null) return
        val pkg = event.packageName?.toString() ?: return
        if (isBankingApp(pkg)) return
        val now = System.currentTimeMillis()

        var launcher = ""
        try {
            val hi = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME)
            launcher = packageManager.resolveActivity(hi, 0)?.activityInfo?.packageName ?: ""
        } catch (_: Exception) {}

        when (event.eventType) {
            AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED -> {
                if (pkg == launcher) {
                    storeFg("", "", now)
                    storeEvent(now, pkg, "app_drawer", "Home/Launcher")
                    return
                }
                if (isSystemPkg(pkg) || pkg == packageName) return
                val cls = event.className?.toString() ?: ""
                storeFg(pkg, cls, now)

                // Screen title / toolbar text from the window
                val screenTitle = extractScreenTitle(event)
                if (screenTitle.isNotEmpty()) {
                    storeEvent(now, pkg, "screen", screenTitle)
                }

                // Detect recent apps switcher
                if (cls.contains("RecentsTvActivity") || cls.contains("RecentsActivity") ||
                    cls.contains("com.android.systemui.recents")) {
                    storeEvent(now, pkg, "recent_apps", "Opened Recent Apps")
                }
            }

            AccessibilityEvent.TYPE_VIEW_TEXT_CHANGED -> {
                if (isSystemPkg(pkg) || pkg == packageName) return
                // Typing detection — record that user is typing in this app.
                // Throttle: max once per 3s per app.
                if (pkg != lastTypingPkg || now - lastTypingTime > 3000) {
                    lastTypingPkg = pkg
                    lastTypingTime = now
                    storeEvent(now, pkg, "typing", "Typing")
                    // Store typing state for presence ping
                    try {
                        getSharedPreferences("SoulSyncPrefs", Context.MODE_PRIVATE).edit()
                            .putString("acc_typing_pkg", pkg)
                            .putLong("acc_typing_time", now)
                            .apply()
                    } catch (_: Exception) {}
                }
            }

            AccessibilityEvent.TYPE_VIEW_CLICKED -> {
                if (isSystemPkg(pkg) || pkg == packageName) return
                val label = getClickLabel(event)
                if (label.isNotEmpty()) {
                    // Throttle: skip duplicate click same label within 1s
                    if (pkg == lastClickPkg && label == lastClickLabel && now - lastClickTime < 1000) return
                    lastClickPkg = pkg
                    lastClickLabel = label
                    lastClickTime = now
                    storeEvent(now, pkg, "click", label)
                }
            }

            AccessibilityEvent.TYPE_VIEW_SCROLLED -> {
                if (isSystemPkg(pkg) || pkg == packageName) return
                // Throttle: aggregate scrolls per app, flush every 5s
                if (pkg == lastScrollPkg && now - lastScrollTime < 5000) {
                    scrollCount++
                    return
                }
                if (lastScrollPkg.isNotEmpty() && scrollCount > 0) {
                    storeEvent(lastScrollTime, lastScrollPkg, "scroll", "Scrolled ×$scrollCount")
                }
                lastScrollPkg = pkg
                lastScrollTime = now
                scrollCount = 1
            }

            AccessibilityEvent.TYPE_NOTIFICATION_STATE_CHANGED -> {
                if (pkg == packageName) return
                val text = event.text?.joinToString(" ") ?: ""
                if (text.isNotEmpty()) {
                    storeEvent(now, pkg, "notif_dismiss", "Notification: ${text.take(80)}")
                }
            }

            AccessibilityEvent.TYPE_VIEW_FOCUSED -> {
                if (isSystemPkg(pkg) || pkg == packageName) return
                // Input focus — detect tap on text fields (search bar, chat box, etc.)
                val cls = event.className?.toString() ?: ""
                if (cls.contains("EditText") || cls.contains("TextField") || cls.contains("Input")) {
                    val hint = event.contentDescription?.toString()
                        ?: event.text?.joinToString(" ")
                        ?: ""
                    val label = if (hint.isNotEmpty() && hint.length < 60) "Focus: $hint" else "Input field focused"
                    storeEvent(now, pkg, "input_focus", label)
                }
            }

            AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED -> {
                // Clipboard / copy-paste detection: contentChangeTypes includes CONTENT_CHANGE_TYPE_TEXT
                if (isSystemPkg(pkg) || pkg == packageName) return
                try {
                    if (event.contentChangeTypes and AccessibilityEvent.CONTENT_CHANGE_TYPE_TEXT != 0) {
                        // Check clipboard
                        val cm = getSystemService(Context.CLIPBOARD_SERVICE) as? android.content.ClipboardManager
                        if (cm != null && cm.hasPrimaryClip()) {
                            val clipTime = getSharedPreferences("SoulSyncPrefs", Context.MODE_PRIVATE)
                                .getLong("acc_last_clip_time", 0)
                            if (now - clipTime > 2000) {
                                getSharedPreferences("SoulSyncPrefs", Context.MODE_PRIVATE).edit()
                                    .putLong("acc_last_clip_time", now)
                                    .apply()
                                storeEvent(now, pkg, "clipboard", "Copy/Paste used")
                            }
                        }
                    }
                } catch (_: Exception) {}
            }
        }
    }

    private fun storeFg(pkg: String, cls: String, time: Long) {
        try {
            getSharedPreferences("SoulSyncPrefs", Context.MODE_PRIVATE).edit()
                .putString("acc_fg_pkg", pkg)
                .putString("acc_fg_class", if (pkg.isEmpty()) "" else cls)
                .putLong("acc_fg_time", time)
                .apply()
        } catch (_: Exception) {}
    }

    // Store accessibility event in a rolling buffer (SharedPrefs JSON array, max 200).
    private fun storeEvent(time: Long, pkg: String, type: String, detail: String) {
        try {
            val sp = getSharedPreferences("SoulSyncPrefs", Context.MODE_PRIVATE)
            val raw = sp.getString("acc_events", "[]") ?: "[]"
            val arr = try { JSONArray(raw) } catch (_: Exception) { JSONArray() }
            val ev = JSONObject().apply {
                put("t", time)
                put("pkg", pkg)
                put("type", type)
                put("detail", detail.take(120))
            }
            arr.put(ev)
            // Keep only last 200 events
            while (arr.length() > 200) arr.remove(0)
            sp.edit().putString("acc_events", arr.toString()).apply()
        } catch (_: Exception) {}
    }

    private fun getClickLabel(event: AccessibilityEvent): String {
        // Try content description first
        val cd = event.contentDescription?.toString()
        if (!cd.isNullOrBlank() && cd.length < 60) return cd

        // Try event text
        val txt = event.text?.joinToString(" ")?.trim()
        if (!txt.isNullOrBlank() && txt.length < 60) return txt

        // Try source node
        try {
            val src = event.source
            if (src != null) {
                val nd = src.text?.toString()
                src.recycle()
                if (!nd.isNullOrBlank() && nd.length < 60) return nd
            }
        } catch (_: Exception) {}

        return ""
    }

    private fun extractScreenTitle(event: AccessibilityEvent): String {
        // Try to get the window/activity title from content description or text
        val cd = event.contentDescription?.toString()
        if (!cd.isNullOrBlank() && cd.length in 2..80) return cd

        val txt = event.text?.joinToString(" ")?.trim()
        if (!txt.isNullOrBlank() && txt.length in 2..80) return txt

        return ""
    }

    override fun onInterrupt() {}

    private fun isSystemPkg(p: String): Boolean {
        return p == "android" || p == "com.android.systemui" ||
            p.startsWith("com.android.inputmethod") || p.contains(".ime") ||
            p.contains("inputmethod") || p.contains("latin") ||
            p.contains("launcher") || p.startsWith("com.android.settings") ||
            p.startsWith("com.android.vending") || p.startsWith("com.google.android.gms") ||
            p.startsWith("com.google.android.gsf") ||
            p.startsWith("com.google.android.googlequicksearchbox") ||
            p.contains("com.vivo.") || p.contains("com.bbk.") || p.contains("com.oppo.") ||
            p.contains("com.coloros.") || p.contains("com.miui.") || p.contains("com.xiaomi.")
    }
}
