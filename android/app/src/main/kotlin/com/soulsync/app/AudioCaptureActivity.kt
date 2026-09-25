package com.soulsync.app

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Bundle

class AudioCaptureActivity : Activity() {
    private val REQUEST_CODE = 9901
    private var recordingId = 0

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        recordingId = intent.getIntExtra("recording_id", 0)
        if (recordingId <= 0) { finish(); return }
        try {
            val mpm = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
            startActivityForResult(mpm.createScreenCaptureIntent(), REQUEST_CODE)
        } catch (e: Exception) {
            e.printStackTrace()
            reportFailed()
            finish()
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQUEST_CODE) {
            if (resultCode == RESULT_OK && data != null) {
                val svc = Intent(this, AudioCaptureService::class.java)
                svc.putExtra("recording_id", recordingId)
                svc.putExtra("result_code", resultCode)
                svc.putExtra("data", data)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    startForegroundService(svc)
                } else {
                    startService(svc)
                }
            } else {
                reportFailed()
            }
        }
        finish()
    }

    private fun reportFailed() {
        val prefs = getSharedPreferences("SoulSyncPrefs", Context.MODE_PRIVATE)
        val jwt = prefs.getString("jwt_token", "") ?: ""
        val apiBase = prefs.getString("apiBaseUrl", "") ?: ""
        val apiKey = prefs.getString("apiKey", "") ?: ""
        if (jwt.isEmpty() || apiBase.isEmpty()) return
        Thread {
            try {
                val url = java.net.URL("$apiBase/api.php?route=audio/failed")
                val conn = url.openConnection() as java.net.HttpURLConnection
                conn.requestMethod = "POST"
                conn.setRequestProperty("Content-Type", "application/json")
                conn.setRequestProperty("Authorization", "Bearer $jwt")
                if (apiKey.isNotEmpty()) conn.setRequestProperty("X-API-Key", apiKey)
                conn.doOutput = true
                java.io.OutputStreamWriter(conn.outputStream).use { w ->
                    w.write(org.json.JSONObject().apply { put("id", recordingId) }.toString())
                    w.flush()
                }
                conn.responseCode; conn.disconnect()
            } catch (_: Exception) {}
        }.start()
    }
}
