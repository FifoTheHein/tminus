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
            postHeadsUps(alerts)
            return
        }
        try {
            startRinging(appContext, alerts.map { it.id })
        } catch (e: IllegalStateException) {
            // ForegroundServiceStartNotAllowedException (Android 12+) is an IllegalStateException.
            Log.w(TAG, "Ringing service refused to start; showing a heads-up instead", e)
            postHeadsUps(alerts)
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

    /**
     * One notification per coalesce group (spec §6): [alerts] just fired, so each group's post lists
     * them together with the group's members that are already on screen as a heads-up.
     */
    private fun postHeadsUps(alerts: List<PlannedAlert>) {
        val presented = store.read().presented
        val ringing = RingingSession.ids
        alerts.groupBy { it.coalesceGroup }.forEach { (group, fired) ->
            val members = (headsUpMembers(presented, ringing, group) + fired).distinctBy { it.id }
            notifications.postHeadsUp(members.sortedWith(EngineReducer.displayOrder))
        }
    }

    /** Re-posts (silently) or cancels each heads-up notification that showed one of [alerts]. */
    private fun refreshHeadsUps(alerts: List<PlannedAlert>) {
        val presented = store.read().presented
        val ringing = RingingSession.ids
        alerts.map { it.coalesceGroup }.distinct().forEach { group ->
            val remaining = headsUpMembers(presented, ringing, group)
            if (remaining.isEmpty()) notifications.cancelHeadsUp(group) else notifications.postHeadsUp(remaining, silent = true)
        }
    }

    companion object {
        private const val TAG = "TMinusEngine"

        /** The alerts a group's heads-up notification shows: presented, in [group] and not ringing. */
        fun headsUpMembers(presented: List<PlannedAlert>, ringing: Set<String>, group: String): List<PlannedAlert> =
            presented.filter { it.coalesceGroup == group && it.id !in ringing }.sortedWith(EngineReducer.displayOrder)

        /** True while some presented, non-ringing alert still belongs on the heads-up [notificationId]. */
        fun headsUpRemains(store: PlanStore, notificationId: Int): Boolean {
            val ringing = RingingSession.ids
            return store.read().presented.any {
                it.id !in ringing && NotificationFactory.headsUpId(it.coalesceGroup) == notificationId
            }
        }
    }
}
