package io.github.fifothehein.tminus.engine

import org.json.JSONArray
import org.json.JSONObject

/** org.json mapping (roadmap §5.4). Alert keys match Dart `PlannedAlert.toJson` exactly. */
object EngineJson {
    const val PLAN_VERSION = 1
    private const val STATE_VERSION = 1

    /** Parses the applyPlan argument `{"version": 1, "alerts": [...]}` as the Flutter codec delivers it. */
    fun parsePlan(args: Map<*, *>): List<PlannedAlert> {
        val o = JSONObject(args)
        val version = o.getInt("version")
        require(version == PLAN_VERSION) { "Unsupported plan version $version" }
        return o.getJSONArray("alerts").objects().map(::alertFromJson)
    }

    fun alertToJson(a: PlannedAlert): JSONObject = JSONObject()
        .put("id", a.id)
        .put("occurrenceKey", a.occurrenceKey)
        .put("fireAtUtcMs", a.fireAtUtcMs)
        .put("offsetMinutes", a.offsetMinutes)
        .put("strength", a.strength.wire)
        .put(
            "sound",
            JSONObject()
                .put("toneUri", a.sound.toneUri ?: JSONObject.NULL)
                .put("vibrate", a.sound.vibrate)
                .put("gradualVolume", a.sound.gradualVolume)
                .put("ringTimeoutSec", a.sound.ringTimeoutSec),
        )
        .put(
            "event",
            JSONObject()
                .put("title", a.event.title)
                .put("startUtcMs", a.event.startUtcMs)
                .put("endUtcMs", a.event.endUtcMs)
                .put("location", a.event.location ?: JSONObject.NULL)
                .put("joinUrl", a.event.joinUrl ?: JSONObject.NULL)
                .put("color", a.event.color),
        )
        .put("coalesceGroup", a.coalesceGroup)

    fun alertFromJson(o: JSONObject): PlannedAlert {
        val s = o.getJSONObject("sound")
        val e = o.getJSONObject("event")
        return PlannedAlert(
            id = o.getString("id"),
            occurrenceKey = o.getString("occurrenceKey"),
            fireAtUtcMs = o.getLong("fireAtUtcMs"),
            offsetMinutes = o.getInt("offsetMinutes"),
            strength = Strength.fromWire(o.getString("strength")),
            sound = Sound(
                toneUri = s.stringOrNull("toneUri"),
                vibrate = s.getBoolean("vibrate"),
                gradualVolume = s.getBoolean("gradualVolume"),
                ringTimeoutSec = s.getInt("ringTimeoutSec"),
            ),
            event = EventSnapshot(
                title = e.getString("title"),
                startUtcMs = e.getLong("startUtcMs"),
                endUtcMs = e.getLong("endUtcMs"),
                location = e.stringOrNull("location"),
                joinUrl = e.stringOrNull("joinUrl"),
                color = e.getLong("color"),
            ),
            coalesceGroup = o.getString("coalesceGroup"),
        )
    }

    fun stateToJson(state: EngineState): JSONObject = JSONObject()
        .put("version", STATE_VERSION)
        .put("plan", alerts(state.plan))
        .put("snoozes", alerts(state.snoozes))
        .put("tests", alerts(state.tests))
        .put("presented", alerts(state.presented))
        .put(
            "acks",
            JSONArray(state.acks.map { JSONObject().put("occurrenceKey", it.occurrenceKey).put("startUtcMs", it.startUtcMs) }),
        )
        .put(
            "dismissed",
            JSONArray(state.dismissed.map { JSONObject().put("alertId", it.alertId).put("fireAtUtcMs", it.fireAtUtcMs) }),
        )

    fun stateFromJson(o: JSONObject): EngineState {
        val version = o.getInt("version")
        require(version == STATE_VERSION) { "Unsupported state version $version" }
        return EngineState(
            plan = o.getJSONArray("plan").objects().map(::alertFromJson),
            snoozes = o.getJSONArray("snoozes").objects().map(::alertFromJson),
            tests = o.getJSONArray("tests").objects().map(::alertFromJson),
            presented = o.getJSONArray("presented").objects().map(::alertFromJson),
            acks = o.getJSONArray("acks").objects().map { Ack(it.getString("occurrenceKey"), it.getLong("startUtcMs")) },
            dismissed = o.getJSONArray("dismissed").objects().map { Dismissal(it.getString("alertId"), it.getLong("fireAtUtcMs")) },
        )
    }

    fun eventToJson(e: EngineEvent): JSONObject = JSONObject()
        .put("type", e.type.wire)
        .put("alertId", e.alertId)
        .put("occurrenceKey", e.occurrenceKey)
        .put("startUtcMs", e.startUtcMs)
        .put("atUtcMs", e.atUtcMs)
        .put("snoozeUntilUtcMs", e.snoozeUntilUtcMs ?: JSONObject.NULL)

    fun eventFromJson(o: JSONObject): EngineEvent = EngineEvent(
        type = EngineEventType.fromWire(o.getString("type")),
        alertId = o.getString("alertId"),
        occurrenceKey = o.getString("occurrenceKey"),
        startUtcMs = o.getLong("startUtcMs"),
        atUtcMs = o.getLong("atUtcMs"),
        snoozeUntilUtcMs = if (o.isNull("snoozeUntilUtcMs")) null else o.getLong("snoozeUntilUtcMs"),
    )

    /** A plain map the Flutter codec can send; JSON nulls become Kotlin nulls. */
    fun toMap(o: JSONObject): Map<String, Any?> =
        o.keys().asSequence().associateWith { key -> unwrap(o.get(key)) }

    private fun unwrap(v: Any?): Any? = when (v) {
        JSONObject.NULL -> null
        is JSONObject -> toMap(v)
        is JSONArray -> (0 until v.length()).map { unwrap(v.get(it)) }
        else -> v
    }

    private fun alerts(list: List<PlannedAlert>) = JSONArray(list.map(::alertToJson))

    private fun JSONArray.objects(): List<JSONObject> = (0 until length()).map { getJSONObject(it) }

    private fun JSONObject.stringOrNull(key: String): String? = if (isNull(key)) null else getString(key)
}
