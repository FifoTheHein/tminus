package io.github.fifothehein.tminus.engine

import java.time.Instant
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter

/** Alert strength; [wire] is the Dart `AlertStrength.name`. */
enum class Strength(val wire: String) {
    HEADS_UP("headsUp"),
    ALARM("alarm");

    companion object {
        fun fromWire(wire: String): Strength =
            entries.firstOrNull { it.wire == wire } ?: throw IllegalArgumentException("Unknown strength: $wire")
    }
}

/** Mirrors Dart `SoundSettings`. */
data class Sound(
    val toneUri: String?,
    val vibrate: Boolean,
    val gradualVolume: Boolean,
    val ringTimeoutSec: Int,
) {
    companion object {
        val DEFAULT = Sound(toneUri = null, vibrate = true, gradualVolume = true, ringTimeoutSec = 120)
    }
}

/** Mirrors Dart `EventSnapshot`. Times are UTC epoch milliseconds; [color] is ARGB. */
data class EventSnapshot(
    val title: String,
    val startUtcMs: Long,
    val endUtcMs: Long,
    val location: String?,
    val joinUrl: String?,
    val color: Long,
)

/** Mirrors Dart `PlannedAlert`. Kotlin treats [id] as an opaque string (roadmap §3). */
data class PlannedAlert(
    val id: String,
    val occurrenceKey: String,
    val fireAtUtcMs: Long,
    val offsetMinutes: Int,
    val strength: Strength,
    val sound: Sound,
    val event: EventSnapshot,
    val coalesceGroup: String,
) {
    /** True for alerts created by `testAlarm`. */
    val isTest: Boolean get() = occurrenceKey.startsWith(EngineState.TEST_KEY_PREFIX)
}

/** Dismiss all / Join of one occurrence at one start time (roadmap §3). */
data class Ack(val occurrenceKey: String, val startUtcMs: Long)

/** A single Dismiss / Stop of one alert at one fire time (roadmap §3). */
data class Dismissal(val alertId: String, val fireAtUtcMs: Long)

/**
 * Everything PlanStore persists.
 * - [plan]: future alerts from the last applyPlan; each has an AlarmManager alarm.
 * - [snoozes]: Kotlin-created snoozes (`<id>:s`) of plan alerts.
 * - [tests]: alerts from testAlarm and their snoozes; applyPlan never touches them.
 * - [presented]: alerts that fired and wait for the user (ringing, or a heads-up on screen).
 */
data class EngineState(
    val plan: List<PlannedAlert> = emptyList(),
    val snoozes: List<PlannedAlert> = emptyList(),
    val tests: List<PlannedAlert> = emptyList(),
    val presented: List<PlannedAlert> = emptyList(),
    val acks: List<Ack> = emptyList(),
    val dismissed: List<Dismissal> = emptyList(),
) {
    /** Every alert that has an AlarmManager alarm. */
    val scheduled: List<PlannedAlert> get() = plan + snoozes + tests

    fun isAcked(occurrenceKey: String, startUtcMs: Long): Boolean =
        acks.any { it.occurrenceKey == occurrenceKey && it.startUtcMs == startUtcMs }

    fun isDismissed(alertId: String, fireAtUtcMs: Long): Boolean =
        dismissed.any { it.alertId == alertId && it.fireAtUtcMs == fireAtUtcMs }

    /** This state with [ids] removed from plan, snoozes and tests. */
    fun withoutScheduled(ids: Set<String>): EngineState = copy(
        plan = plan.filterNot { it.id in ids },
        snoozes = snoozes.filterNot { it.id in ids },
        tests = tests.filterNot { it.id in ids },
    )

    companion object {
        val EMPTY = EngineState()
        const val TEST_KEY_PREFIX = "test|"
    }
}

/** Kotlin twin of Dart `PlannedAlert.groupFor` ("yyyy-MM-ddTHH:mmZ", UTC), for snoozes and test alerts. */
object CoalesceGroups {
    private val format = DateTimeFormatter.ofPattern("yyyy-MM-dd'T'HH:mm'Z'").withZone(ZoneOffset.UTC)

    fun groupFor(fireAtUtcMs: Long): String = format.format(Instant.ofEpochMilli(fireAtUtcMs))
}
