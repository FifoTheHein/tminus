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
            // A heads-up that fires into a group that is ringing joins the ringing session. RingingService
            // is running while the session is not empty; it re-posts the ringing notification and the
            // alarm screen lists the new alert. Starting the service again restarts the ring timeout and
            // wake lock from the heads-up's own ringTimeoutSec, as for a joining alarm.
            val ringingGroups = RingingSession.alerts.map { it.coalesceGroup }.toSet()
            val (joining, own) = alerts.partition { it.coalesceGroup in ringingGroups }
            if (joining.isNotEmpty()) {
                RingingSession.add(joining)
                try {
                    startRinging(appContext, joining.map { it.id })
                } catch (e: IllegalStateException) {
                    // The alert is in the session already; only the timeout restart is lost.
                    Log.w(TAG, "Ringing service refused the joining heads-up's restart", e)
                }
            }
            postHeadsUps(own)
            return
        }
        // An alarm absorbs its group's heads-up: the alerts that notification shows ring with it.
        val presented = store.read().presented
        val ringing = RingingSession.ids
        val groups = alerts.map { it.coalesceGroup }.distinct()
        val absorbed = groups.flatMap { headsUpMembers(presented, ringing, it) }
        val session = (alerts + absorbed).distinctBy { it.id }
        // In the session before the service starts, so the alarm screen (opened from the app, say after
        // a crash with notifications blocked) has them at once. RingingService adds them again.
        RingingSession.add(session)
        try {
            startRinging(appContext, session.map { it.id })
        } catch (e: IllegalStateException) {
            // ForegroundServiceStartNotAllowedException (Android 12+) is an IllegalStateException.
            Log.w(TAG, "Ringing service refused to start; showing a heads-up instead", e)
            RingingSession.remove(session.map { it.id })
            postHeadsUps(alerts)
            return
        }
        notifications.cancelHeadsUpNotifications(groups.map(NotificationFactory::headsUpId))
    }

    /**
     * RingingService could not go foreground: [alerts] leave the ringing session and are posted as
     * heads-up notifications (one per coalesce group). They stay presented, so their actions work.
     */
    fun fallBackToHeadsUp(alerts: List<PlannedAlert>) {
        RingingSession.remove(alerts.map { it.id })
        postHeadsUps(alerts)
    }

    override fun withdraw(alerts: List<PlannedAlert>) {
        if (alerts.isEmpty()) return
        RingingSession.remove(alerts.map { it.id })
        refreshHeadsUps(alerts)
    }

    /** Leaving the session stops the sound: RingingService stops ringing when it empties. */
    override fun silence(alertIds: Collection<String>) = RingingSession.remove(alertIds)

    /** Ringing in this process, or the group's heads-up is still among the app's active notifications. */
    override fun isShowing(alert: PlannedAlert): Boolean =
        alert.id in RingingSession.ids || notifications.isHeadsUpPosted(alert.coalesceGroup)

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
        val emptied = mutableListOf<Int>()
        alerts.map { it.coalesceGroup }.distinct().forEach { group ->
            val remaining = headsUpMembers(presented, ringing, group)
            if (remaining.isEmpty()) emptied += NotificationFactory.headsUpId(group) else notifications.postHeadsUp(remaining, silent = true)
        }
        if (emptied.isNotEmpty()) notifications.cancelHeadsUpNotifications(emptied)
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
