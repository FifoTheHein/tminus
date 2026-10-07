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
            ACTION_RETRY_RINGING -> retryRinging(context, intent.getStringArrayListExtra(EXTRA_ALERT_IDS) ?: return)
        }
    }

    /**
     * The retry after a refused ringing start: the alerts that are still presented ring again (their
     * heads-up is withdrawn). The service is told it is a retry, so a second refusal is not retried.
     */
    private fun retryRinging(context: Context, alertIds: List<String>) {
        val presenter = AndroidAlertPresenter(context, startRinging = { ctx, ids -> RingingService.start(ctx, ids, retry = true) })
        PlanStore(context).read().presented.filter { it.id in alertIds }
            .groupBy { it.coalesceGroup }.values
            .forEach { presenter.present(it.sortedWith(EngineReducer.displayOrder)) }
    }

    companion object {
        const val ACTION_FIRE = "io.github.fifothehein.tminus.action.FIRE"
        const val ACTION_RECOVER = "io.github.fifothehein.tminus.action.RECOVER"
        const val ACTION_RETRY_RINGING = "io.github.fifothehein.tminus.action.RETRY_RINGING"
        const val EXTRA_ALERT_IDS = "alertIds"
        const val EXTRA_ALERT_ID = "alertId"

        fun recoverIntent(context: Context): Intent = Intent(context, AlarmReceiver::class.java).setAction(ACTION_RECOVER)

        fun retryRingingIntent(context: Context, alertIds: List<String>): Intent =
            Intent(context, AlarmReceiver::class.java)
                .setAction(ACTION_RETRY_RINGING)
                .setData(Uri.parse("tminus://retry/${Uri.encode(alertIds.joinToString(","))}"))
                .putStringArrayListExtra(EXTRA_ALERT_IDS, ArrayList(alertIds))

        /** The data URI keeps each alert's PendingIntent distinct even if two ids share a hashCode. */
        fun fireIntent(context: Context, alertId: String): Intent =
            Intent(context, AlarmReceiver::class.java)
                .setAction(ACTION_FIRE)
                .setData(Uri.parse("tminus://alert/${Uri.encode(alertId)}"))
                .putExtra(EXTRA_ALERT_ID, alertId)
    }
}
