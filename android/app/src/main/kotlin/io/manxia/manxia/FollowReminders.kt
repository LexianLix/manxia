package io.manxia.manxia

import android.Manifest
import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import java.util.Calendar

object FollowReminders {
    const val CHANNEL = "follow-reminders"
    const val ACTION = "io.manxia.FOLLOW_REMINDER"
    private const val ID = 40501
    private fun prefs(context: Context) = context.getSharedPreferences("follow-reminder", Context.MODE_PRIVATE)
    fun allowed(context: Context): Boolean {
        if (Build.VERSION.SDK_INT >= 33 && context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) return false
        val manager = context.getSystemService(NotificationManager::class.java)
        return manager.areNotificationsEnabled() && (Build.VERSION.SDK_INT < 26 || manager.getNotificationChannel(CHANNEL)?.importance != NotificationManager.IMPORTANCE_NONE)
    }
    fun config(context: Context): Map<String, Any> {
        val p = prefs(context)
        return mapOf("available" to true, "allowed" to allowed(context),
            "enabled" to p.getBoolean("enabled", false),
            "days" to (p.getStringSet("days", setOf("5")) ?: setOf("5")).mapNotNull { it.toIntOrNull() }.sorted(),
            "hour" to p.getInt("hour", 20), "minute" to p.getInt("minute", 0))
    }
    fun configure(context: Context, values: Map<*, *>) {
        val days = (values["days"] as? List<*>)?.mapNotNull { (it as? Number)?.toInt() }?.filter { it in 1..7 }?.toSet() ?: emptySet()
        val hour = (values["hour"] as? Number)?.toInt() ?: 20
        val minute = (values["minute"] as? Number)?.toInt() ?: 0
        require(hour in 0..23 && minute in 0..59)
        val enabled = values["enabled"] == true && allowed(context) && days.isNotEmpty()
        prefs(context).edit().putBoolean("enabled", enabled)
            .putStringSet("days", days.map { it.toString() }.toSet())
            .putInt("hour", hour).putInt("minute", minute)
            .putString("title", (values["title"] as? String)?.take(100) ?: "漫匣")
            .putString("body", (values["body"] as? String)?.take(250) ?: "")
            .apply()
        schedule(context)
        if (!enabled) context.getSystemService(NotificationManager::class.java).cancel(ID)
    }
    private fun pending(context: Context): PendingIntent = PendingIntent.getBroadcast(context, ID,
        Intent(context, FollowReminderReceiver::class.java).setAction(ACTION),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    fun schedule(context: Context) {
        val alarm = context.getSystemService(AlarmManager::class.java)
        val p = prefs(context)
        alarm.cancel(pending(context))
        if (!p.getBoolean("enabled", false) || !allowed(context)) return
        val days = p.getStringSet("days", emptySet()) ?: emptySet()
        val now = System.currentTimeMillis()
        for (offset in 0..7) {
            val date = Calendar.getInstance().apply {
                add(Calendar.DATE, offset)
                set(Calendar.HOUR_OF_DAY, p.getInt("hour", 20))
                set(Calendar.MINUTE, p.getInt("minute", 0))
                set(Calendar.SECOND, 0); set(Calendar.MILLISECOND, 0)
            }
            val weekday = ((date.get(Calendar.DAY_OF_WEEK) + 5) % 7) + 1
            if (weekday.toString() in days && date.timeInMillis > now) {
                alarm.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, date.timeInMillis, pending(context))
                return
            }
        }
    }
    @Suppress("DEPRECATION")
    fun notify(context: Context) {
        val p = prefs(context)
        if (!p.getBoolean("enabled", false) || !allowed(context)) return
        val manager = context.getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= 26) manager.createNotificationChannel(
            NotificationChannel(CHANNEL, p.getString("title", "漫匣") ?: "漫匣", NotificationManager.IMPORTANCE_DEFAULT))
        val open = PendingIntent.getActivity(context, ID,
            Intent(context, MainActivity::class.java).putExtra("followCalendar", true)
                .addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(context, CHANNEL) else Notification.Builder(context)
        manager.notify(ID, builder.setSmallIcon(R.drawable.ic_follow_reminder)
            .setContentTitle(p.getString("title", "漫匣")).setContentText(p.getString("body", ""))
            .setContentIntent(open).setAutoCancel(true).build())
    }
}

class FollowReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        try {
            if (intent.action == FollowReminders.ACTION) FollowReminders.notify(context)
            FollowReminders.schedule(context)
        } catch (error: Exception) {
            android.util.Log.w("Manxia", "Unable to deliver follow reminder", error)
        }
    }
}
