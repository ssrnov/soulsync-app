package com.soulsync.app

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.view.View
import android.widget.RemoteViews

class SoulSyncWidget : AppWidgetProvider() {

    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray) {
        for (appWidgetId in appWidgetIds) {
            updateWidget(context, appWidgetManager, appWidgetId)
        }
    }

    override fun onAppWidgetOptionsChanged(context: Context, appWidgetManager: AppWidgetManager, appWidgetId: Int, newOptions: Bundle) {
        updateWidget(context, appWidgetManager, appWidgetId)
        super.onAppWidgetOptionsChanged(context, appWidgetManager, appWidgetId, newOptions)
    }

    companion object {
        private const val PREFS_NAME = "SoulSyncWidgetPrefs"

        fun saveWidgetData(
            context: Context,
            partnerName: String,
            isOnline: Boolean,
            mood: String,
            note: String,
            streak: String,
            loveScore: String
        ) {
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            prefs.edit().apply {
                putString("partnerName", partnerName)
                putBoolean("isOnline", isOnline)
                putString("mood", mood)
                putString("note", note)
                putString("streak", streak)
                putString("loveScore", loveScore)
                apply()
            }

            // Trigger update on all widgets
            val appWidgetManager = AppWidgetManager.getInstance(context)
            val component = ComponentName(context, SoulSyncWidget::class.java)
            val ids = appWidgetManager.getAppWidgetIds(component)
            val widget = SoulSyncWidget()
            widget.onUpdate(context, appWidgetManager, ids)
        }

        // Map a stored mood (label like "romantic" OR an emoji already) to its emoji.
        private fun moodToEmoji(m: String): String {
            val s = m.trim()
            if (s.isEmpty()) return "💜"
            // If it's already an emoji (non-letter), keep it.
            if (!s[0].isLetter()) return s
            return when (s.lowercase()) {
                "happy" -> "😊"; "sad" -> "😢"; "sleeping" -> "😴"; "busy" -> "⏰"
                "romantic" -> "😍"; "excited" -> "🤩"; "gaming" -> "🎮"; "working" -> "💼"
                else -> "💜"
            }
        }

        private fun updateWidget(context: Context, appWidgetManager: AppWidgetManager, appWidgetId: Int) {
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val note = prefs.getString("note", "") ?: ""
            val mood = prefs.getString("mood", "") ?: ""

            // Shows the partner's note + their current mood emoji (falls back to 💜).
            val views = RemoteViews(context.packageName, R.layout.widget_note)
            try {
                views.setTextViewText(R.id.widget_note, if (note.isBlank()) "No note yet" else note)
            } catch (e: Exception) { e.printStackTrace() }
            try {
                views.setTextViewText(R.id.widget_heart, moodToEmoji(mood))
            } catch (e: Exception) { e.printStackTrace() }
            // No click action — tapping the widget does nothing.
            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }
}
