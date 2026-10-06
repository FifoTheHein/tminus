package io.github.fifothehein.tminus.engine

import android.content.Context

/** The real AlertPresenter. Task 12 adds the ringing branch for alarm-strength groups. */
class AndroidAlertPresenter(
    context: Context,
    private val store: PlanStore = PlanStore(context),
    private val notifications: NotificationFactory = NotificationFactory(context),
) : AlertPresenter {

    override fun present(alerts: List<PlannedAlert>) {
        notifications.postHeadsUp(alerts)
    }

    override fun withdraw(alerts: List<PlannedAlert>) {
        refreshHeadsUps(alerts)
    }

    override fun missed(alerts: List<PlannedAlert>) {
        alerts.forEach(notifications::postMissed)
        withdraw(alerts)
    }

    /** Re-posts (silently) or cancels each heads-up notification that showed one of [alerts]. */
    private fun refreshHeadsUps(alerts: List<PlannedAlert>) {
        if (alerts.isEmpty()) return
        val presented = store.read().presented
        alerts.map { it.coalesceGroup }.distinct().forEach { group ->
            val remaining = presented.filter { it.coalesceGroup == group }
            if (remaining.isEmpty()) notifications.cancelHeadsUp(group) else notifications.postHeadsUp(remaining, silent = true)
        }
    }
}
