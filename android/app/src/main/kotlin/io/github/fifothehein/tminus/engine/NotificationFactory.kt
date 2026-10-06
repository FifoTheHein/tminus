package io.github.fifothehein.tminus.engine

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.provider.Settings
import android.util.Log
import androidx.core.app.NotificationCompat
import io.github.fifothehein.tminus.MainActivity
import io.github.fifothehein.tminus.R

/** Builds and posts every engine notification (spec §7 Firing, brief §10). At most three actions each. */
class NotificationFactory(
    context: Context,
    private val text: AlertText = AlertText.forDevice(context),
    private val clock: () -> Long = System::currentTimeMillis,
) {
    private val appContext: Context = context.applicationContext
    private val manager: NotificationManager = appContext.getSystemService(NotificationManager::class.java)

    fun ensureChannels() {
        val ringing = NotificationChannel(CHANNEL_RINGING, "Ringing alarms", NotificationManager.IMPORTANCE_HIGH).apply {
            description = "Full-screen meeting alarms. The alarm plays its own sound."
            setSound(null, null)
            enableVibration(false)
            lockscreenVisibility = Notification.VISIBILITY_PUBLIC
        }
        val headsUp = NotificationChannel(CHANNEL_HEADS_UP, "Heads-up", NotificationManager.IMPORTANCE_HIGH).apply {
            description = "Reminders before a meeting. Silent when the phone is on silent."
            setSound(
                Settings.System.DEFAULT_NOTIFICATION_URI,
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_NOTIFICATION_EVENT)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build(),
            )
            enableVibration(true)
            lockscreenVisibility = Notification.VISIBILITY_PUBLIC
        }
        val missed = NotificationChannel(CHANNEL_MISSED, "Missed alarms", NotificationManager.IMPORTANCE_DEFAULT).apply {
            description = "Alarms that rang until they timed out."
        }
        manager.createNotificationChannels(listOf(ringing, headsUp, missed))
    }

    fun postHeadsUp(alerts: List<PlannedAlert>, silent: Boolean = false) {
        if (alerts.isEmpty()) return
        ensureChannels()
        notify(headsUpId(alerts.first().coalesceGroup), headsUp(alerts, silent))
    }

    fun cancelHeadsUp(group: String) = manager.cancel(headsUpId(group))

    fun postMissed(alert: PlannedAlert) {
        ensureChannels()
        notify(missedId(alert.id), missed(alert))
    }

    /** Single: Join (if link) · Snooze · Dismiss all. Coalesced: Dismiss · Snooze all · Dismiss all. */
    fun headsUp(alerts: List<PlannedAlert>, silent: Boolean = false): Notification {
        val ids = ArrayList(alerts.map { it.id })
        val notificationId = headsUpId(alerts.first().coalesceGroup)
        val b = base(CHANNEL_HEADS_UP, alerts.first())
            .setCategory(NotificationCompat.CATEGORY_REMINDER)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setSilent(silent)
            // Swiping a heads-up away is a single Dismiss of what it showed.
            .setDeleteIntent(action(NotificationActionReceiver.ACTION_DISMISS, ids, notificationId))
        if (alerts.size == 1) {
            val a = alerts.single()
            b.setContentTitle(text.headsUpTitle(a, clock())).setContentText(text.detail(a.event))
            if (a.event.joinUrl != null) b.addAction(0, "Join", join(a.id))
            b.addAction(0, "Snooze", action(NotificationActionReceiver.ACTION_SNOOZE, ids, notificationId))
            b.addAction(0, "Dismiss all", action(NotificationActionReceiver.ACTION_DISMISS_ALL, ids, notificationId))
        } else {
            coalesced(b, alerts)
            b.addAction(0, "Dismiss", action(NotificationActionReceiver.ACTION_DISMISS, ids, notificationId))
            b.addAction(0, "Snooze all", action(NotificationActionReceiver.ACTION_SNOOZE, ids, notificationId))
            b.addAction(0, "Dismiss all", action(NotificationActionReceiver.ACTION_DISMISS_ALL, ids, notificationId))
        }
        return b.build()
    }

    fun missed(alert: PlannedAlert): Notification = base(CHANNEL_MISSED, alert)
        .setContentTitle(text.missedTitle(alert))
        .setContentText(text.detail(alert.event))
        .setCategory(NotificationCompat.CATEGORY_REMINDER)
        .setAutoCancel(true)
        .addAction(0, "Open", openApp())
        .build()

    /** Single: Stop · Snooze · Join (link) or Dismiss all. Coalesced: Stop · Snooze all · Dismiss all (spec §7). */
    fun ringing(alerts: List<PlannedAlert>): Notification {
        val b = NotificationCompat.Builder(appContext, CHANNEL_RINGING)
            .setSmallIcon(R.drawable.ic_stat_tminus)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setShowWhen(true)
            .setWhen(clock())
            .setContentIntent(alarmScreen())
            .setFullScreenIntent(alarmScreen(), true)
        if (alerts.isEmpty()) return b.setContentTitle("Alarm").build()
        val ids = ArrayList(alerts.map { it.id })
        val none = NotificationActionReceiver.NO_NOTIFICATION_ID
        b.setColor(alerts.first().event.color.toInt())
        if (alerts.size == 1) {
            val a = alerts.single()
            b.setContentTitle(text.ringingTitle(a, clock())).setContentText(text.detail(a.event))
            b.addAction(0, "Stop", action(NotificationActionReceiver.ACTION_DISMISS, ids, none))
            b.addAction(0, "Snooze", action(NotificationActionReceiver.ACTION_SNOOZE, ids, none))
            if (a.event.joinUrl != null) {
                b.addAction(0, "Join", join(a.id))
            } else {
                b.addAction(0, "Dismiss all", action(NotificationActionReceiver.ACTION_DISMISS_ALL, ids, none))
            }
        } else {
            coalesced(b, alerts)
            b.addAction(0, "Stop", action(NotificationActionReceiver.ACTION_DISMISS, ids, none))
            b.addAction(0, "Snooze all", action(NotificationActionReceiver.ACTION_SNOOZE, ids, none))
            b.addAction(0, "Dismiss all", action(NotificationActionReceiver.ACTION_DISMISS_ALL, ids, none))
        }
        return b.build()
    }

    fun notifyRinging(alerts: List<PlannedAlert>) = notify(RINGING_NOTIFICATION_ID, ringing(alerts))

    private fun base(channel: String, lead: PlannedAlert): NotificationCompat.Builder =
        NotificationCompat.Builder(appContext, channel)
            .setSmallIcon(R.drawable.ic_stat_tminus)
            .setColor(lead.event.color.toInt())
            .setContentIntent(openApp())
            .setShowWhen(true)
            .setWhen(clock())
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)

    private fun coalesced(b: NotificationCompat.Builder, alerts: List<PlannedAlert>) {
        val style = NotificationCompat.InboxStyle()
        alerts.forEach { style.addLine("${it.event.title} · ${text.range(it.event)}") }
        b.setContentTitle(text.coalescedTitle(alerts.size))
            .setContentText(text.coalescedText(alerts))
            .setStyle(style)
    }

    private fun action(action: String, ids: ArrayList<String>, notificationId: Int): PendingIntent =
        PendingIntent.getBroadcast(
            appContext,
            "$action|$notificationId|${ids.joinToString(",")}".hashCode(),
            NotificationActionReceiver.intent(appContext, action, ids, notificationId),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

    private fun join(alertId: String): PendingIntent = PendingIntent.getActivity(
        appContext,
        "join|$alertId".hashCode(),
        JoinActivity.intent(appContext, alertId),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )

    private fun openApp(): PendingIntent = PendingIntent.getActivity(
        appContext,
        OPEN_REQUEST_CODE,
        Intent(appContext, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )

    private fun alarmScreen(): PendingIntent = PendingIntent.getActivity(
        appContext,
        ALARM_REQUEST_CODE,
        Intent(appContext, AlarmActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_NO_USER_ACTION),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )

    private fun notify(id: Int, notification: Notification) {
        try {
            manager.notify(id, notification)
        } catch (e: SecurityException) {
            Log.w(TAG, "POST_NOTIFICATIONS not granted; Health reports this", e)
        }
    }

    companion object {
        const val CHANNEL_RINGING = "alarm_ringing"
        const val CHANNEL_HEADS_UP = "heads_up"
        const val CHANNEL_MISSED = "missed"
        const val RINGING_NOTIFICATION_ID = 1001
        private const val OPEN_REQUEST_CODE = 0x5102
        private const val ALARM_REQUEST_CODE = 0x5103
        private const val TAG = "TMinusEngine"

        fun headsUpId(group: String): Int = "headsUp|$group".hashCode()

        fun missedId(alertId: String): Int = "missed|$alertId".hashCode()
    }
}
