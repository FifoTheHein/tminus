package io.github.fifothehein.tminus.engine

import android.content.Context
import android.util.Log

/** The real AlertPresenter: alarm groups ring in RingingService, heads-up groups are notifications. */
class AndroidAlertPresenter(
    context: Context,
    private val store: PlanStore = PlanStore(context),
    private val notifications: NotificationFactory = NotificationFactory(context),
    private val startRinging: (Context, List<String>) -> Unit = { ctx, ids -> RingingService.start(ctx, ids) },
) : AlertPresenter {
    private val appContext: Context = context.applicationContext

    override fun present(alerts: List<PlannedAlert>) {
        if (alerts.none { it.strength == Strength.ALARM }) {
            notifications.postHeadsUp(alerts)
            return
        }
        try {
            startRinging(appContext, alerts.map { it.id })
        } catch (e: IllegalStateException) {
            // ForegroundServiceStartNotAllowedException (Android 12+) is an IllegalStateException.
            Log.w(TAG, "Ringing service refused to start; showing a heads-up instead", e)
            notifications.postHeadsUp(alerts)
        }
    }

    override fun withdraw(alerts: List<PlannedAlert>) {
        if (alerts.isEmpty()) return
        RingingSession.remove(alerts.map { it.id })
        refreshHeadsUps(alerts)
    }

    override fun missed(alerts: List<PlannedAlert>) {
        alerts.forEach(notifications::postMissed)
        withdraw(alerts)
    }

    /** Re-posts (silently) or cancels each heads-up notification that showed one of [alerts]. */
    private fun refreshHeadsUps(alerts: List<PlannedAlert>) {
        val presented = store.read().presented
        val ringing = RingingSession.ids
        alerts.map { it.coalesceGroup }.distinct().forEach { group ->
            val remaining = presented.filter { it.coalesceGroup == group && it.id !in ringing }
            if (remaining.isEmpty()) notifications.cancelHeadsUp(group) else notifications.postHeadsUp(remaining, silent = true)
        }
    }

    private companion object {
        const val TAG = "TMinusEngine"
    }
}
