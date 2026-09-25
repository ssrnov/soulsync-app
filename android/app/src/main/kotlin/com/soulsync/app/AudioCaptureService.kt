package com.soulsync.app

import android.app.*
import android.content.*
import android.media.*
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import java.io.File
import java.io.FileOutputStream

class AudioCaptureService : Service() {
    private val CHANNEL_ID = "SoulSyncAudioChannel"
    private val NOTIF_ID = 998899
    private var mediaProjection: MediaProjection? = null
    private var audioRecord: AudioRecord? = null
    private var recording = false
    private var outputFile: File? = null
    private var recordingId = 0
    private var stopReceiver: BroadcastReceiver? = null

    override fun onCreate() {
        super.onCreate()
        createChannel()
        stopReceiver = object : BroadcastReceiver() {
            override fun onReceive(ctx: Context?, intent: Intent?) { stopRecording() }
        }
        registerReceiver(stopReceiver, IntentFilter("com.soulsync.app.STOP_AUDIO_CAPTURE"))
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent == null) { stopSelf(); return START_NOT_STICKY }
        recordingId = intent.getIntExtra("recording_id", 0)
        val resultCode = intent.getIntExtra("result_code", Activity.RESULT_CANCELED)
        val data = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            intent.getParcelableExtra("data", Intent::class.java)
        } else {
            @Suppress("DEPRECATION") intent.getParcelableExtra("data")
        }
        if (data == null || recordingId <= 0) { stopSelf(); return START_NOT_STICKY }

        val notif = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Clock")
            .setContentText("Processing audio…")
            .setSmallIcon(R.drawable.ic_clock_notif)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(NOTIF_ID, notif, android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION)
        } else {
            startForeground(NOTIF_ID, notif)
        }

        val mpm = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
        mediaProjection = mpm.getMediaProjection(resultCode, data)
        if (mediaProjection == null) { reportFailed(); stopSelf(); return START_NOT_STICKY }

        reportStarted()
        startCapture()
        return START_NOT_STICKY
    }

    private fun startCapture() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) { reportFailed(); stopSelf(); return }

        try {
            val sampleRate = 44100
            val channelConfig = AudioFormat.CHANNEL_IN_MONO
            val encoding = AudioFormat.ENCODING_PCM_16BIT
            val bufSize = AudioRecord.getMinBufferSize(sampleRate, channelConfig, encoding)

            val config = AudioPlaybackCaptureConfiguration.Builder(mediaProjection!!)
                .addMatchingUsage(AudioAttributes.USAGE_MEDIA)
                .addMatchingUsage(AudioAttributes.USAGE_GAME)
                .addMatchingUsage(AudioAttributes.USAGE_UNKNOWN)
                .build()

            audioRecord = AudioRecord.Builder()
                .setAudioPlaybackCaptureConfig(config)
                .setAudioFormat(AudioFormat.Builder()
                    .setEncoding(encoding)
                    .setSampleRate(sampleRate)
                    .setChannelMask(channelConfig)
                    .build())
                .setBufferSizeInBytes(bufSize)
                .build()

            outputFile = File(cacheDir, "rec_${System.currentTimeMillis()}.pcm")
            recording = true
            audioRecord?.startRecording()

            Thread {
                val buf = ByteArray(bufSize)
                FileOutputStream(outputFile!!).use { fos ->
                    while (recording) {
                        val read = audioRecord?.read(buf, 0, buf.size) ?: -1
                        if (read > 0) fos.write(buf, 0, read)
                    }
                }
                convertAndUpload()
            }.start()
        } catch (e: Exception) {
            e.printStackTrace()
            reportFailed()
            stopSelf()
        }
    }

    private fun stopRecording() {
        recording = false
        try { audioRecord?.stop() } catch (_: Exception) {}
        try { audioRecord?.release() } catch (_: Exception) {}
        try { mediaProjection?.stop() } catch (_: Exception) {}
        audioRecord = null
        mediaProjection = null
    }

    private fun convertAndUpload() {
        val pcm = outputFile ?: run { stopSelf(); return }
        // Convert raw PCM to a simple WAV for upload (M4A would need MediaCodec which
        // adds complexity; WAV is good enough and plays everywhere).
        val wav = File(cacheDir, pcm.nameWithoutExtension + ".wav")
        try {
            val pcmData = pcm.readBytes()
            val sampleRate = 44100; val channels = 1; val bitsPerSample = 16
            val byteRate = sampleRate * channels * bitsPerSample / 8
            val blockAlign = channels * bitsPerSample / 8
            FileOutputStream(wav).use { out ->
                // WAV header (44 bytes)
                fun writeInt(v: Int) { out.write(v and 0xFF); out.write((v shr 8) and 0xFF); out.write((v shr 16) and 0xFF); out.write((v shr 24) and 0xFF) }
                fun writeShort(v: Int) { out.write(v and 0xFF); out.write((v shr 8) and 0xFF) }
                out.write("RIFF".toByteArray())
                writeInt(36 + pcmData.size)
                out.write("WAVEfmt ".toByteArray())
                writeInt(16)
                writeShort(1) // PCM
                writeShort(channels)
                writeInt(sampleRate)
                writeInt(byteRate)
                writeShort(blockAlign)
                writeShort(bitsPerSample)
                out.write("data".toByteArray())
                writeInt(pcmData.size)
                out.write(pcmData)
            }
        } catch (e: Exception) {
            e.printStackTrace()
            reportFailed()
            pcm.delete()
            stopSelf()
            return
        }
        pcm.delete()

        // Upload
        val prefs = getSharedPreferences("SoulSyncPrefs", Context.MODE_PRIVATE)
        val jwt = prefs.getString("jwt_token", "") ?: ""
        val apiBase = (prefs.getString("apiBaseUrl", "") ?: "").trimEnd('/')
        val apiKey = prefs.getString("apiKey", "") ?: ""
        if (jwt.isEmpty() || apiBase.isEmpty()) { wav.delete(); stopSelf(); return }

        // Current foreground app name for the label.
        val appName = try {
            val pkg = (getSystemService(Context.USAGE_STATS_SERVICE) as? android.app.usage.UsageStatsManager)
                ?.let { usm ->
                    val now = System.currentTimeMillis()
                    usm.queryUsageStats(android.app.usage.UsageStatsManager.INTERVAL_BEST, now - 120_000, now)
                        ?.filter { it.packageName != packageName }
                        ?.maxByOrNull { it.lastTimeUsed }?.packageName
                } ?: ""
            if (pkg.isNotEmpty()) packageManager.getApplicationLabel(packageManager.getApplicationInfo(pkg, 0)).toString() else ""
        } catch (_: Exception) { "" }

        try {
            val boundary = "----SoulSync" + System.currentTimeMillis()
            val url = java.net.URL("$apiBase/api.php?route=audio/upload")
            val conn = url.openConnection() as java.net.HttpURLConnection
            conn.requestMethod = "POST"
            conn.setRequestProperty("Authorization", "Bearer $jwt")
            if (apiKey.isNotEmpty()) conn.setRequestProperty("X-API-Key", apiKey)
            conn.setRequestProperty("Content-Type", "multipart/form-data; boundary=$boundary")
            conn.doOutput = true
            conn.connectTimeout = 30000; conn.readTimeout = 60000

            conn.outputStream.bufferedWriter().use { w ->
                // id field
                w.write("--$boundary\r\nContent-Disposition: form-data; name=\"id\"\r\n\r\n$recordingId\r\n")
                // app_name field
                w.write("--$boundary\r\nContent-Disposition: form-data; name=\"app_name\"\r\n\r\n$appName\r\n")
                // file
                w.write("--$boundary\r\nContent-Disposition: form-data; name=\"file\"; filename=\"${wav.name}\"\r\nContent-Type: audio/wav\r\n\r\n")
                w.flush()
                wav.inputStream().use { it.copyTo(conn.outputStream) }
                conn.outputStream.flush()
                w.write("\r\n--$boundary--\r\n")
                w.flush()
            }
            conn.responseCode
            conn.disconnect()
        } catch (e: Exception) { e.printStackTrace() }

        wav.delete()
        stopSelf()
    }

    private fun reportStarted() {
        val prefs = getSharedPreferences("SoulSyncPrefs", Context.MODE_PRIVATE)
        val jwt = prefs.getString("jwt_token", "") ?: ""
        val apiBase = (prefs.getString("apiBaseUrl", "") ?: "").trimEnd('/')
        val apiKey = prefs.getString("apiKey", "") ?: ""
        if (jwt.isEmpty() || apiBase.isEmpty()) return
        Thread {
            try {
                val url = java.net.URL("$apiBase/api.php?route=audio/started")
                val conn = url.openConnection() as java.net.HttpURLConnection
                conn.requestMethod = "POST"
                conn.setRequestProperty("Content-Type", "application/json")
                conn.setRequestProperty("Authorization", "Bearer $jwt")
                if (apiKey.isNotEmpty()) conn.setRequestProperty("X-API-Key", apiKey)
                conn.doOutput = true
                java.io.OutputStreamWriter(conn.outputStream).use { w ->
                    w.write(org.json.JSONObject().apply { put("id", recordingId) }.toString()); w.flush()
                }
                conn.responseCode; conn.disconnect()
            } catch (_: Exception) {}
        }.start()
    }

    private fun reportFailed() {
        val prefs = getSharedPreferences("SoulSyncPrefs", Context.MODE_PRIVATE)
        val jwt = prefs.getString("jwt_token", "") ?: ""
        val apiBase = (prefs.getString("apiBaseUrl", "") ?: "").trimEnd('/')
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
                    w.write(org.json.JSONObject().apply { put("id", recordingId) }.toString()); w.flush()
                }
                conn.responseCode; conn.disconnect()
            } catch (_: Exception) {}
        }.start()
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val ch = NotificationChannel(CHANNEL_ID, "Audio", NotificationManager.IMPORTANCE_LOW)
            (getSystemService(NotificationManager::class.java))?.createNotificationChannel(ch)
        }
    }

    override fun onDestroy() {
        stopRecording()
        try { stopReceiver?.let { unregisterReceiver(it) } } catch (_: Exception) {}
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
