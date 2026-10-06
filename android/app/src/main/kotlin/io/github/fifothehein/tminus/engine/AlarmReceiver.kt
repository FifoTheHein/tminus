package io.github.fifothehein.tminus.engine

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.net.Uri

/** AlarmManager's target for every alert alarm. */
class AlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != ACTION_FIRE) return
        val alertId = intent.getStringExtra(EXTRA_ALERT_ID) ?: return
        EngineActions.create(context).fire(alertId)
    }

    companion object {
        const val ACTION_FIRE = "io.github.fifothehein.tminus.action.FIRE"
        const val EXTRA_ALERT_ID = "alertId"

        /** The data URI keeps each alert's PendingIntent distinct even if two ids share a hashCode. */
        fun fireIntent(context: Context, alertId: String): Intent =
            Intent(context, AlarmReceiver::class.java)
                .setAction(ACTION_FIRE)
                .setData(Uri.parse("tminus://alert/${Uri.encode(alertId)}"))
                .putExtra(EXTRA_ALERT_ID, alertId)
    }
}
