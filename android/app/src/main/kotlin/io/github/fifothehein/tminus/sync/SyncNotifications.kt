package io.github.fifothehein.tminus.sync

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import androidx.core.app.NotificationCompat
import io.github.fifothehein.tminus.MainActivity
import io.github.fifothehein.tminus.R

/**
 * The "Feed stale" and "Feed broken" notifications (spec §8.10, §9; brief §10). One per source and
 * kind, alert-once, withdrawn when the source syncs again. Dart writes the text; this only posts it.
 */
class SyncNotifications(context: Context) {
    private val appContext: Context = context.applicationContext
    private val manager: NotificationManager = appContext.getSystemService(NotificationManager::class.java)

    fun ensureChannel() {
        manager.createNotificationChannel(
            NotificationChannel(CHANNEL_STATUS, "Calendar sync problems", NotificationManager.IMPORTANCE_DEFAULT).apply {
                description = "A calendar has stopped syncing, so alarms may be out of date"
            },
        )
    }

    /** [kind] is [KIND_STALE] (action Sync now) or [KIND_BROKEN] (action Fix). */
    fun post(kind: String, sourceId: String, title: String, text: String) {
        require(kind == KIND_STALE || kind == KIND_BROKEN) { "Unknown notice kind: $kind" }
        ensureChannel()
        val open = openSource(sourceId)
        val builder = NotificationCompat.Builder(appContext, CHANNEL_STATUS)
            .setSmallIcon(R.drawable.ic_stat_tminus)
            .setContentTitle(title)
            .setContentText(text)
            .setStyle(NotificationCompat.BigTextStyle().bigText(text))
            .setCategory(NotificationCompat.CATEGORY_STATUS)
            .setOnlyAlertOnce(true)
            .setAutoCancel(true)
            .setContentIntent(open)
            .setGroup(GROUP)
            .setGroupAlertBehavior(NotificationCompat.GROUP_ALERT_CHILDREN)
        if (kind == KIND_STALE) {
            builder.addAction(0, "Sync now", SyncActionReceiver.syncNow(appContext))
        } else {
            builder.addAction(0, "Fix", open)
        }
        notify(id(kind, sourceId), builder.build())
        notify(SUMMARY_ID, summary())
    }

    fun cancel(kind: String, sourceId: String) {
        val cancelled = id(kind, sourceId)
        manager.cancel(cancelled)
        // A cancel is applied asynchronously on a device, so the notice just cancelled may still be listed.
        val others = manager.activeNotifications.any {
            it.notification.group == GROUP && it.id != SUMMARY_ID && it.id != cancelled
        }
        if (!others) manager.cancel(SUMMARY_ID)
    }

    private fun summary(): Notification = NotificationCompat.Builder(appContext, CHANNEL_STATUS)
        .setSmallIcon(R.drawable.ic_stat_tminus)
        .setContentTitle("Calendar sync problems")
        .setGroup(GROUP)
        .setGroupSummary(true)
        .setGroupAlertBehavior(NotificationCompat.GROUP_ALERT_CHILDREN)
        .setOnlyAlertOnce(true)
        .build()

    /** Opens the app; Plan 5's router reads [EXTRA_ROUTE] and shows the source. */
    private fun openSource(sourceId: String): PendingIntent = PendingIntent.getActivity(
        appContext,
        "open|$sourceId".hashCode(),
        Intent(appContext, MainActivity::class.java)
            .putExtra(EXTRA_ROUTE, "/sources/$sourceId")
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )

    private fun notify(id: Int, notification: Notification) {
        try {
            manager.notify(id, notification)
        } catch (e: SecurityException) {
            Log.w(TAG, "Notifications are blocked", e)
        }
    }

    companion object {
        const val CHANNEL_STATUS = "sync_status"
        const val KIND_STALE = "stale"
        const val KIND_BROKEN = "broken"
        const val EXTRA_ROUTE = "io.github.fifothehein.tminus.ROUTE"
        private const val GROUP = "io.github.fifothehein.tminus.SYNC"
        private const val SUMMARY_ID = 0x5302
        private const val TAG = "TMinusSync"

        fun id(kind: String, sourceId: String): Int = "sync|$kind|$sourceId".hashCode()
    }
}

/** The Feed stale notification's Sync now button: an expedited sync. */
class SyncActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != ACTION_SYNC_NOW) return
        SyncScheduler(context).runNow(SyncWorker.TRIGGER_MANUAL, expedited = true)
    }

    companion object {
        const val ACTION_SYNC_NOW = "io.github.fifothehein.tminus.SYNC_NOW"

        fun syncNow(context: Context): PendingIntent = PendingIntent.getBroadcast(
            context,
            0x5303,
            Intent(context, SyncActionReceiver::class.java).setAction(ACTION_SYNC_NOW),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }
}
