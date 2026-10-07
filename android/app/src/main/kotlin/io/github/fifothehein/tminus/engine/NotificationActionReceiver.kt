package io.github.fifothehein.tminus.engine

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.net.Uri

/** Snooze / Dismiss (Stop) / Dismiss all buttons on engine notifications. Join goes to JoinActivity. */
class NotificationActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val ids = intent.getStringArrayListExtra(EXTRA_ALERT_IDS) ?: return
        val actions = EngineActions.create(context)
        val notificationId = intent.getIntExtra(EXTRA_NOTIFICATION_ID, NO_NOTIFICATION_ID)
        when (intent.action) {
            ACTION_SNOOZE -> actions.snooze(ids, null)
            // The ringing notification's Stop silences the whole session, whatever ids it was posted with.
            ACTION_DISMISS -> actions.dismiss(if (notificationId == NO_NOTIFICATION_ID) ids + RingingSession.ids else ids)
            ACTION_DISMISS_ALL -> actions.dismissAll(ids)
            else -> return
        }
        // The presenter has re-posted the group's notification for the alerts still on screen. Cancel it
        // only when none are left, which also clears it if its alerts were already pruned from PlanStore.
        if (notificationId != NO_NOTIFICATION_ID && !AndroidAlertPresenter.headsUpRemains(PlanStore(context), notificationId)) {
            NotificationFactory(context).cancelHeadsUpNotifications(listOf(notificationId))
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
