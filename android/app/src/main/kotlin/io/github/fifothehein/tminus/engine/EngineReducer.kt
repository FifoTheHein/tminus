package io.github.fifothehein.tminus.engine

/** The outcome of one engine state change. */
data class Transition(
    val state: EngineState,
    /** The alerts the action applied to (fired, snoozed, dismissed …). */
    val affected: List<PlannedAlert> = emptyList(),
    /** Alerts that left [EngineState.presented]: their notification or screen must go. */
    val withdrawn: List<PlannedAlert> = emptyList(),
    /** Alerts that need an AlarmManager alarm. */
    val toArm: List<PlannedAlert> = emptyList(),
    /** Alerts whose AlarmManager alarm must be cancelled. */
    val toCancel: List<PlannedAlert> = emptyList(),
)

/** Pure state changes for firing and user actions. No Android types. */
object EngineReducer {
    const val SNOOZE_SUFFIX = ":s"
    const val RETENTION_MS: Long = 24 * 60 * MINUTE_MS
    private const val PRESENTED_GRACE_MS: Long = 60 * MINUTE_MS

    /** The order a coalesced screen or notification lists its alerts in. */
    val displayOrder: Comparator<PlannedAlert> = compareBy({ it.event.startUtcMs }, { it.event.title }, { it.id })

    /**
     * Collects the fired alert and the scheduled alerts in its coalesce group that are already due
     * (one alarm per alert, collected at fire). A sibling that is not due yet keeps its own alarm.
     */
    fun fire(state: EngineState, alertId: String, nowUtcMs: Long): Transition {
        val hit = state.scheduled.firstOrNull { it.id == alertId } ?: return Transition(state)
        val group = state.scheduled
            .filter { it.id == alertId || (it.coalesceGroup == hit.coalesceGroup && it.fireAtUtcMs <= nowUtcMs) }
            .sortedWith(displayOrder)
        val ids = group.map { it.id }.toSet()
        return Transition(
            state = state.withoutScheduled(ids).copy(presented = state.presented.filterNot { it.id in ids } + group),
            affected = group,
            toCancel = group.filter { it.id != alertId },
        )
    }

    /**
     * Overdue alerts are scheduled alerts whose fire time has passed but that never fired (a late
     * inexact alarm, a reboot across the fire time, a plan that arrived first). This removes the
     * acknowledged or dismissed ones, and expires the ones whose event has ended: they are
     * [Transition.affected] and must be reported missed. The rest stay scheduled for [fire].
     */
    fun expireOverdue(state: EngineState, nowUtcMs: Long): Transition {
        val overdue = state.scheduled.filter { it.fireAtUtcMs <= nowUtcMs }
        val handled = overdue.filter { state.isAcked(it.occurrenceKey, it.event.startUtcMs) || state.isDismissed(it.id, it.fireAtUtcMs) }
        val ended = overdue.filter { it !in handled && it.event.hasEnded(nowUtcMs) }
        val removed = handled + ended
        if (removed.isEmpty()) return Transition(state)
        return Transition(
            state = state.withoutScheduled(removed.map { it.id }.toSet()),
            affected = ended,
            toCancel = removed,
        )
    }

    fun snoozeIdFor(alertId: String): String = alertId.removeSuffix(SNOOZE_SUFFIX) + SNOOZE_SUFFIX

    fun snooze(state: EngineState, alertIds: Collection<String>, untilFor: (PlannedAlert) -> Long): Transition {
        val targets = state.presented.filter { it.id in alertIds }
        if (targets.isEmpty()) return Transition(state)
        val created = targets.map { a ->
            val until = untilFor(a)
            a.copy(id = snoozeIdFor(a.id), fireAtUtcMs = until, coalesceGroup = CoalesceGroups.groupFor(until))
        }
        val createdIds = created.map { it.id }.toSet()
        val targetIds = targets.map { it.id }.toSet()
        val (testSnoozes, planSnoozes) = created.partition { it.isTest }
        return Transition(
            state = state.copy(
                presented = state.presented.filterNot { it.id in targetIds },
                snoozes = state.snoozes.filterNot { it.id in createdIds } + planSnoozes,
                tests = state.tests.filterNot { it.id in createdIds } + testSnoozes,
            ),
            affected = targets,
            withdrawn = targets,
            toArm = created,
        )
    }

    fun dismiss(state: EngineState, alertIds: Collection<String>): Transition {
        val targets = state.presented.filter { it.id in alertIds }
        if (targets.isEmpty()) return Transition(state)
        val ids = targets.map { it.id }.toSet()
        return Transition(
            state = state.copy(
                presented = state.presented.filterNot { it.id in ids },
                dismissed = (state.dismissed + targets.map { Dismissal(it.id, it.fireAtUtcMs) }).distinct(),
            ),
            affected = targets,
            withdrawn = targets,
        )
    }

    /** Dismiss all / Join: acks each target's occurrence at its start and drops everything else for it. */
    fun acknowledge(state: EngineState, alertIds: Collection<String>): Transition {
        val targets = state.presented.filter { it.id in alertIds }
        if (targets.isEmpty()) return Transition(state)
        val acks = targets.map { Ack(it.occurrenceKey, it.event.startUtcMs) }.distinct()
        fun covered(a: PlannedAlert) = acks.any { it.occurrenceKey == a.occurrenceKey && it.startUtcMs == a.event.startUtcMs }
        val cancelled = state.scheduled.filter(::covered)
        val withdrawn = state.presented.filter(::covered)
        return Transition(
            state = state.withoutScheduled(cancelled.map { it.id }.toSet()).copy(
                presented = state.presented.filterNot(::covered),
                acks = (state.acks + acks).distinct(),
            ),
            affected = targets,
            withdrawn = withdrawn,
            toCancel = cancelled,
        )
    }

    fun missed(state: EngineState, alertIds: Collection<String>): Transition {
        val targets = state.presented.filter { it.id in alertIds }
        if (targets.isEmpty()) return Transition(state)
        val ids = targets.map { it.id }.toSet()
        return Transition(
            state = state.copy(presented = state.presented.filterNot { it.id in ids }),
            affected = targets,
            withdrawn = targets,
        )
    }

    fun addTest(state: EngineState, alert: PlannedAlert): Transition = Transition(
        state = state.copy(tests = state.tests.filterNot { it.id == alert.id } + alert),
        affected = listOf(alert),
        toArm = listOf(alert),
    )

    /** Acks and dismissals live 24 h after their time (roadmap §3); presented alerts an hour after the event ends. */
    fun prune(state: EngineState, nowUtcMs: Long): EngineState = state.copy(
        acks = state.acks.filter { it.startUtcMs + RETENTION_MS >= nowUtcMs },
        dismissed = state.dismissed.filter { it.fireAtUtcMs + RETENTION_MS >= nowUtcMs },
        presented = state.presented.filter { it.event.endUtcMs + PRESENTED_GRACE_MS >= nowUtcMs },
    )
}
