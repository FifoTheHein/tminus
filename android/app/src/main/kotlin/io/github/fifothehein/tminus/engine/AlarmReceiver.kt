package io.github.fifothehein.tminus.engine

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.net.Uri

/** AlarmManager's target for every alert alarm, and for boot recovery's alarm. */
class AlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            ACTION_FIRE -> EngineActions.create(context).fire(intent.getStringExtra(EXTRA_ALERT_ID) ?: return)
            // Boot recovery's alarm: rings again what was ringing at reboot.
            ACTION_RECOVER -> EngineActions.create(context).recoverPresented()
        }
    }

    companion object {
        const val ACTION_FIRE = "io.github.fifothehein.tminus.action.FIRE"
        const val ACTION_RECOVER = "io.github.fifothehein.tminus.action.RECOVER"
        const val EXTRA_ALERT_ID = "alertId"

        fun recoverIntent(context: Context): Intent = Intent(context, AlarmReceiver::class.java).setAction(ACTION_RECOVER)

        /** The data URI keeps each alert's PendingIntent distinct even if two ids share a hashCode. */
        fun fireIntent(context: Context, alertId: String): Intent =
            Intent(context, AlarmReceiver::class.java)
                .setAction(ACTION_FIRE)
                .setData(Uri.parse("tminus://alert/${Uri.encode(alertId)}"))
                .putExtra(EXTRA_ALERT_ID, alertId)
    }
}
