package io.github.fifothehein.tminus.engine

import android.content.Intent
import org.robolectric.Robolectric
import org.robolectric.android.controller.ServiceController

/** 2026-09-21T14:13:20Z. Tests that go through AlarmScheduler inject this as the clock. */
const val NOW: Long = 1_790_000_000_000L
const val HOUR: Long = 60 * MINUTE_MS

/** A PlannedAlert for tests. The event starts at [start] (default: 1 min after firing) and lasts 30 min. */
fun alert(
    id: String,
    fireAt: Long,
    strength: Strength = Strength.ALARM,
    occurrenceKey: String = "src|$id|occ",
    start: Long = fireAt + MINUTE_MS,
    title: String = "Meeting $id",
    joinUrl: String? = null,
    location: String? = "Boardroom 2",
    toneUri: String? = null,
    group: String = CoalesceGroups.groupFor(fireAt),
): PlannedAlert = PlannedAlert(
    id = id,
    occurrenceKey = occurrenceKey,
    fireAtUtcMs = fireAt,
    offsetMinutes = ((start - fireAt) / MINUTE_MS).toInt(),
    strength = strength,
    sound = Sound.DEFAULT.copy(toneUri = toneUri),
    event = EventSnapshot(
        title = title,
        startUtcMs = start,
        endUtcMs = start + 30 * MINUTE_MS,
        location = location,
        joinUrl = joinUrl,
        color = 0xFF6AA0F5L,
    ),
    coalesceGroup = group,
)

private val ringingServices = mutableListOf<ServiceController<RingingService>>()

/**
 * Builds a RingingService and remembers it. Call [destroyRingingServices] from @After: a service that is
 * never destroyed keeps its RingingSession listener, which then posts ringing notifications in later
 * test classes (RingingSession is process-wide).
 */
fun buildRingingService(intent: Intent): ServiceController<RingingService> =
    Robolectric.buildService(RingingService::class.java, intent).also { ringingServices += it }

fun destroyRingingServices() {
    ringingServices.forEach { it.destroy() }
    ringingServices.clear()
}
