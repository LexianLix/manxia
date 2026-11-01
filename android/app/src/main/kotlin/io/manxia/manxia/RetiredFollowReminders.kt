package io.manxia.manxia

import android.app.AlarmManager
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build

/** Cancels v0.4.5 reminders during upgrade without touching the personal library. */
object RetiredFollowReminders {
    fun clear(context: Context) {
        val old = PendingIntent.getBroadcast(context, 40501,
            Intent(context, FollowReminderReceiver::class.java).setAction("io.manxia.FOLLOW_REMINDER"),
            PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE)
        if (old != null) {
            context.getSystemService(AlarmManager::class.java).cancel(old)
            old.cancel()
        }
        val notifications = context.getSystemService(NotificationManager::class.java)
        notifications.cancel(40501)
        if (Build.VERSION.SDK_INT >= 26) notifications.deleteNotificationChannel("follow-reminders")
        val preferences = context.getSharedPreferences("follow-reminder", Context.MODE_PRIVATE)
        if (preferences.contains("enabled")) preferences.edit().putBoolean("enabled", false).apply()
    }
}

// Retain the old component name only to safely consume an already pending alarm.
class FollowReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) { RetiredFollowReminders.clear(context) }
}
