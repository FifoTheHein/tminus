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
}

/**
 * Every alarm and user action: updates PlanStore and AlarmManager, queues the engine event and
 * tells the presenter. Call on the main thread.
 */
class EngineActions(
    context: Context,
    private val presenter: AlertPresenter,
    private val store: PlanStore = PlanStore(context),
    private val scheduler: AlarmScheduler = AlarmScheduler(context, store),
    private val clock: () -> Long = System::currentTimeMillis,
) {
    private val appContext: Context = context.applicationContext

    /** An alarm went off: collects its coalesce group and presents it. Returns the collected alerts. */
    fun fire(alertId: String): List<PlannedAlert> {
        val t = transition { EngineReducer.fire(it, alertId) }
        if (t.affected.isEmpty()) return emptyList()
        t.toCancel.forEach { scheduler.cancel(it.id) }
        val now = clock()
        t.affected.forEach { emit(EngineEvent.of(EngineEventType.FIRED, it, now)) }
        presenter.present(t.affected)
        return t.affected
    }

    /** [option] null means each alert's notification default (roadmap §5.1). Past choices become +1 min. */
    fun snooze(alertIds: Collection<String>, option: SnoozeOption?) {
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
        val t = transition { EngineReducer.missed(it, alertIds) }
        if (t.affected.isEmpty()) return
        val now = clock()
        t.affected.forEach { emit(EngineEvent.of(EngineEventType.MISSED, it, now)) }
        presenter.missed(t.affected)
    }

    private fun acknowledge(alertIds: Collection<String>, type: EngineEventType): List<PlannedAlert> {
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
        /** EngineActions with the real presenter, for receivers, services and activities. */
        fun create(context: Context): EngineActions = EngineActions(context, AndroidAlertPresenter(context))
    }
}
