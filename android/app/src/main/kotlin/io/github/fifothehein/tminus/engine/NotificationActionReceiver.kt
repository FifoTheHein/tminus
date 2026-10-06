package io.github.fifothehein.tminus.engine

import android.app.NotificationManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.net.Uri

/** Snooze / Dismiss (Stop) / Dismiss all buttons on engine notifications. Join goes to JoinActivity. */
class NotificationActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val ids = intent.getStringArrayListExtra(EXTRA_ALERT_IDS) ?: return
        val actions = EngineActions.create(context)
        when (intent.action) {
            ACTION_SNOOZE -> actions.snooze(ids, null)
            ACTION_DISMISS -> actions.dismiss(ids)
            ACTION_DISMISS_ALL -> actions.dismissAll(ids)
            else -> return
        }
        // Clears the notification even if its alerts were already pruned from PlanStore.
        val notificationId = intent.getIntExtra(EXTRA_NOTIFICATION_ID, NO_NOTIFICATION_ID)
        if (notificationId != NO_NOTIFICATION_ID) {
            context.getSystemService(NotificationManager::class.java).cancel(notificationId)
        }
    }

    companion object {
        const val ACTION_SNOOZE = "io.github.fifothehein.tminus.action.SNOOZE"
        const val ACTION_DISMISS = "io.github.fifothehein.tminus.action.DISMISS"
        const val ACTION_DISMISS_ALL = "io.github.fifothehein.tminus.action.DISMISS_ALL"
        const val EXTRA_ALERT_IDS = "alertIds"
        const val EXTRA_NOTIFICATION_ID = "notificationId"
        /** For the ringing notification, which RingingService owns. */
        const val NO_NOTIFICATION_ID = -1

        fun intent(context: Context, action: String, ids: ArrayList<String>, notificationId: Int): Intent =
            Intent(context, NotificationActionReceiver::class.java)
                .setAction(action)
                .setData(Uri.parse("tminus://action/$notificationId/${Uri.encode(ids.joinToString(","))}"))
                .putStringArrayListExtra(EXTRA_ALERT_IDS, ids)
                .putExtra(EXTRA_NOTIFICATION_ID, notificationId)
    }
}
