package io.github.fifothehein.tminus.engine

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
