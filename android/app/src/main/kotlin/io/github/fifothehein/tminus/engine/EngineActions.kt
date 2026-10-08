package io.github.fifothehein.tminus.engine

import android.content.Context

/** Shows and removes alert UI. AndroidAlertPresenter (Task 10) is the real one; tests use a fake. */
interface AlertPresenter {
    /** [alerts] just fired together (one coalesce group). */
    fun present(alerts: List<PlannedAlert>)

    /** The user handled [alerts], or they were acknowledged elsewhere: remove their UI. */
    fun withdraw(alerts: List<PlannedAlert>)

    /** [alerts] rang until the ring timeout. */
    fun missed(alerts: List<PlannedAlert>)

    /** True while [alert] is ringing or its heads-up notification is still posted. */
    fun isShowing(alert: PlannedAlert): Boolean

    /**
     * Stops the sound for [alertIds] now, whatever the engine state says about them: every stop
     * control silences first and reconciles the state afterwards.
     */
    fun silence(alertIds: Collection<String>)
}

/**
 * Every alarm and user action: updates PlanStore and AlarmManager, queues the engine event and
 * tells the presenter. Call on the main thread. Every stop path (snooze, dismiss, acknowledge,
 * missed) silences its ids first, so a ringing alert stops even if the state no longer lists it.
 */
class EngineActions(
    context: Context,
    private val presenter: AlertPresenter,
    private val store: PlanStore = PlanStore(context),
    private val scheduler: AlarmScheduler = AlarmScheduler(context, store),
    private val clock: () -> Long = System::currentTimeMillis,
) {
    private val appContext: Context = context.applicationContext

    /** The `applyPlan` channel method: diffs and arms the plan, then [reconcile]s overdue alerts. */
    fun applyPlan(incoming: List<PlannedAlert>): ApplyResult = scheduler.applyPlan(incoming).also { reconcile() }

    /** App start, boot, app update and time changes: arms every future alert, then [reconcile]s. */
    fun rearmAll(): Int = scheduler.rearmAll().also { reconcile() }

    /**
     * LOCKED_BOOT_COMPLETED / BOOT_COMPLETED. Android 15+ forbids starting the mediaPlayback service
     * from the boot broadcasts, so nothing rings from here: what should ring now (an alarm that was
     * ringing at reboot, an alert that came due while the phone was off, or one due within the window)
     * fires through AlarmManager [RECOVERY_DELAY_MS] from now, and AlarmReceiver may start the service.
     * Heads-ups that were on screen are posted again now.
     */
    fun recoverAfterBoot() {
        recoverPresented(ringLater = true)
        scheduler.rearmAll()
        reconcile(fireLater = true)
    }

    /**
     * Overdue alerts are never dropped silently: one whose event has not ended fires now through
     * [fire] (coalescing, events, presenter); one whose event has ended is reported missed.
     */
    fun reconcile(fireLater: Boolean = false) {
        val now = clock()
        val expired = transition { EngineReducer.expireOverdue(it, now) }
        expired.toCancel.forEach { scheduler.cancel(it.id) }
        if (expired.affected.isNotEmpty()) {
            expired.affected.forEach { emit(EngineEvent.of(EngineEventType.MISSED, it, now)) }
            presenter.missed(expired.affected)
        }
        if (fireLater) {
            // Nothing rings inside the boot window: every alert due before it ends (overdue, or due in the
            // next RECOVERY_DELAY_MS) gets its own alarm at the window's end; AlarmReceiver fires it with
            // its group.
            val windowEnd = now + RECOVERY_DELAY_MS
            store.read().scheduled.filter { it.fireAtUtcMs < windowEnd }.forEach { scheduler.arm(it, windowEnd) }
            return
        }
        while (true) {
            val next = store.read().scheduled.filter { it.fireAtUtcMs <= now }.minWithOrNull(EngineReducer.displayOrder) ?: break
            val fired = fire(next.id)
            if (fired.isEmpty()) break
            fired.forEach { scheduler.cancel(it.id) } // a late alarm may still be pending
        }
    }

    /**
     * Boot, app update and app start: an alert left in `presented` after the process died (a crash,
     * an update, a reboot) has no screen or notification any more. If its event has not ended it is
     * presented again, group by group, without a second `fired` event; otherwise it is reported
     * missed. Alerts that are still ringing or still have their heads-up posted are left alone.
     * Call it before [rearmAll], so alerts that [reconcile] fires are not presented twice.
     */
    fun recoverPresented(ringLater: Boolean = false) {
        val now = clock()
        val orphans = store.read().presented.filterNot(presenter::isShowing)
        if (orphans.isEmpty()) return
        val (ended, live) = orphans.partition { it.event.hasEnded(now) }
        if (ended.isNotEmpty()) missed(ended.map { it.id })
        // At boot ([ringLater]) an alarm group rings through boot recovery's alarm, which calls this again.
        val (later, ringNow) = live.groupBy { it.coalesceGroup }.values
            .partition { group -> ringLater && group.any { it.strength == Strength.ALARM } }
        ringNow.forEach { presenter.present(it.sortedWith(EngineReducer.displayOrder)) }
        if (later.isNotEmpty()) scheduler.armRecovery(now + RECOVERY_DELAY_MS)
    }

    /** An alarm went off: collects its coalesce group and presents it. Returns the collected alerts. */
    fun fire(alertId: String): List<PlannedAlert> {
        val now = clock()
        val t = transition { EngineReducer.fire(it, alertId, now) }
        if (t.affected.isEmpty()) return emptyList()
        t.toCancel.forEach { scheduler.cancel(it.id) }
        t.affected.forEach { emit(EngineEvent.of(EngineEventType.FIRED, it, now)) }
        presenter.present(t.affected)
        return t.affected
    }

    /** [option] null means each alert's notification default (roadmap §5.1). Past choices become +1 min. */
    fun snooze(alertIds: Collection<String>, option: SnoozeOption?) {
        presenter.silence(alertIds)
        val now = clock()
        val t = transition { s ->
            EngineReducer.snooze(s, alertIds) { a ->
                val chosen = option ?: SnoozeOptions.notificationDefault(now, a.event.startUtcMs)
                SnoozeOptions.untilOrNextMinute(chosen, now, a.event.startUtcMs)
            }
        }
        t.toArm.forEach(scheduler::arm)
        t.affected.zip(t.toArm).forEach { (alert, snooze) ->
            emit(EngineEvent.of(EngineEventType.SNOOZED, alert, now, snooze.fireAtUtcMs))
        }
        withdraw(t.withdrawn)
    }

    /** Dismiss / Stop: ends only these alerts; later alerts of the occurrence still fire (spec §6). */
    fun dismiss(alertIds: Collection<String>) {
        presenter.silence(alertIds)
        val t = transition { EngineReducer.dismiss(it, alertIds) }
        val now = clock()
        t.affected.forEach { emit(EngineEvent.of(EngineEventType.DISMISSED, it, now)) }
        withdraw(t.withdrawn)
    }

    fun dismissAll(alertIds: Collection<String>) {
        acknowledge(alertIds, EngineEventType.DISMISSED_ALL)
    }

    /** Records the join (counts as Dismiss all) and returns the alert so the caller can open its link. */
    fun join(alertId: String): PlannedAlert? = acknowledge(listOf(alertId), EngineEventType.JOINED).firstOrNull()

    fun missed(alertIds: Collection<String>) {
        presenter.silence(alertIds)
        val t = transition { EngineReducer.missed(it, alertIds) }
        if (t.affected.isEmpty()) return
        val now = clock()
        t.affected.forEach { emit(EngineEvent.of(EngineEventType.MISSED, it, now)) }
        presenter.missed(t.affected)
    }

    private fun acknowledge(alertIds: Collection<String>, type: EngineEventType): List<PlannedAlert> {
        presenter.silence(alertIds)
        val t = transition { EngineReducer.acknowledge(it, alertIds) }
        t.toCancel.forEach { scheduler.cancel(it.id) }
        val now = clock()
        t.affected.forEach { emit(EngineEvent.of(type, it, now)) }
        withdraw(t.withdrawn)
        return t.affected
    }

    private fun withdraw(alerts: List<PlannedAlert>) {
        if (alerts.isNotEmpty()) presenter.withdraw(alerts)
    }

    private fun transition(block: (EngineState) -> Transition): Transition =
        store.update { s -> block(s).let { it.state to it } }

    private fun emit(event: EngineEvent) = EngineEvents.emit(appContext, event)

    companion object {
        /**
         * How far out boot recovery's alarms are set. A boot broadcast gives the app a 20 s FGS
         * allow-list, and while it lasts Android 15+ attributes any FGS start to BOOT_COMPLETED and
         * refuses mediaPlayback, even from an alarm (ForegroundServiceStartNotAllowedException on the
         * API 36 emulator with a 3 s delay). So the alarm fires just after that window.
         */
        const val RECOVERY_DELAY_MS = 30_000L

        /** EngineActions with the real presenter, for receivers, services and activities. */
        fun create(context: Context): EngineActions = EngineActions(context, AndroidAlertPresenter(context))
    }
}
