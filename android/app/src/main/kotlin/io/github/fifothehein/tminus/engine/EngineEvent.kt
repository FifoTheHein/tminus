package io.github.fifothehein.tminus.engine

/** Event types on `alarm_engine/events` (roadmap §3); [wire] is the JSON value. */
enum class EngineEventType(val wire: String) {
    FIRED("fired"),
    SNOOZED("snoozed"),
    DISMISSED("dismissed"),
    DISMISSED_ALL("dismissedAll"),
    JOINED("joined"),
    MISSED("missed");

    companion object {
        fun fromWire(wire: String): EngineEventType =
            entries.firstOrNull { it.wire == wire } ?: throw IllegalArgumentException("Unknown event type: $wire")
    }
}

data class EngineEvent(
    val type: EngineEventType,
    val alertId: String,
    val occurrenceKey: String,
    val startUtcMs: Long,
    val atUtcMs: Long,
    val snoozeUntilUtcMs: Long? = null,
) {
    /** The EngineEvent JSON of roadmap §3, as a codec-friendly map. */
    fun toMap(): Map<String, Any?> = mapOf(
        "type" to type.wire,
        "alertId" to alertId,
        "occurrenceKey" to occurrenceKey,
        "startUtcMs" to startUtcMs,
        "atUtcMs" to atUtcMs,
        "snoozeUntilUtcMs" to snoozeUntilUtcMs,
    )

    companion object {
        fun of(type: EngineEventType, alert: PlannedAlert, atUtcMs: Long, snoozeUntilUtcMs: Long? = null) =
            EngineEvent(type, alert.id, alert.occurrenceKey, alert.event.startUtcMs, atUtcMs, snoozeUntilUtcMs)
    }
}
