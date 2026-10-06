package io.github.fifothehein.tminus.engine

data class PlanDiffResult(
    val state: EngineState,
    val toArm: List<PlannedAlert>,
    val toCancel: List<PlannedAlert>,
    val kept: List<PlannedAlert>,
)

/**
 * The applyPlan diff by `id + fireAtUtcMs + strength` (spec §7, roadmap §3 engine rules).
 * Pure: AlarmScheduler carries out the result.
 */
object PlanDiff {
    fun apply(old: EngineState, incoming: List<PlannedAlert>, nowUtcMs: Long): PlanDiffResult {
        val base = EngineReducer.prune(old, nowUtcMs)
        val wanted = incoming.distinctBy { it.id }.filter { a ->
            a.fireAtUtcMs > nowUtcMs &&
                !base.isAcked(a.occurrenceKey, a.event.startUtcMs) &&
                !base.isDismissed(a.id, a.fireAtUtcMs) &&
                base.presented.none { it.id == a.id && it.fireAtUtcMs == a.fireAtUtcMs }
        }
        // Strength is part of the key: a heads-up that becomes an alarm needs setAlarmClock, not its old alarm.
        fun sameAlarm(a: PlannedAlert, b: PlannedAlert) =
            a.id == b.id && a.fireAtUtcMs == b.fireAtUtcMs && a.strength == b.strength
        val armedBefore = base.plan.filter { it.fireAtUtcMs > nowUtcMs }
        val kept = wanted.filter { w -> armedBefore.any { sameAlarm(it, w) } }
        val newOrMoved = wanted.filter { w -> armedBefore.none { sameAlarm(it, w) } }
        val gone = armedBefore.filter { o -> wanted.none { sameAlarm(it, o) } }

        // The occurrences the plan still lists, at their start. A missing key means the meeting was
        // cancelled, removed or has ended (roadmap §3); the same key at another start means it moved,
        // and the re-planned alerts for the new start take over.
        val plannedOccurrences = incoming.map { Ack(it.occurrenceKey, it.event.startUtcMs) }.toSet()
        fun stillPlanned(a: PlannedAlert) = Ack(a.occurrenceKey, a.event.startUtcMs) in plannedOccurrences
        // An overdue alert (stored, due, never fired) is never dropped silently: it stays for
        // EngineActions.reconcile, which rings it or reports it missed. It is dropped only if it was
        // acked or dismissed, or if its event has not ended but its occurrence is no longer planned.
        fun overdueKept(a: PlannedAlert) =
            !base.isAcked(a.occurrenceKey, a.event.startUtcMs) &&
                !base.isDismissed(a.id, a.fireAtUtcMs) &&
                (a.event.hasEnded(nowUtcMs) || stillPlanned(a))
        val wantedIds = wanted.map { it.id }.toSet()
        val overduePlan = base.plan.filter { it.fireAtUtcMs <= nowUtcMs && it.id !in wantedIds && overdueKept(it) }
        val (keepSnoozes, dropSnoozes) = base.snoozes.partition {
            if (it.fireAtUtcMs > nowUtcMs) {
                stillPlanned(it) && !base.isAcked(it.occurrenceKey, it.event.startUtcMs)
            } else {
                overdueKept(it)
            }
        }
        return PlanDiffResult(
            state = base.copy(plan = wanted + overduePlan, snoozes = keepSnoozes),
            toArm = newOrMoved,
            toCancel = gone + dropSnoozes,
            kept = kept,
        )
    }
}
