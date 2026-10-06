package io.github.fifothehein.tminus.engine

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

/** org.json is part of the Android framework, so these run under Robolectric. */
@RunWith(RobolectricTestRunner::class)
class EngineJsonTest {
    /** The map the Flutter StandardMessageCodec hands Kotlin for PlannedAlert.toJson(). */
    private fun dartAlert(id: String, fireAt: Long): Map<String, Any?> = mapOf(
        "id" to id,
        "occurrenceKey" to "src|$id|occ",
        "fireAtUtcMs" to fireAt,
        "offsetMinutes" to 1, // small ints arrive as Int
        "strength" to "headsUp",
        "sound" to mapOf("toneUri" to null, "vibrate" to true, "gradualVolume" to false, "ringTimeoutSec" to 120),
        "event" to mapOf(
            "title" to "Sprint planning",
            "startUtcMs" to fireAt + MINUTE_MS,
            "endUtcMs" to fireAt + HOUR,
            "location" to null,
            "joinUrl" to "https://teams.microsoft.com/l/meetup-join/abc",
            "color" to 4285178101L, // 0xFF6AA0F5 exceeds Int, arrives as Long
        ),
        "coalesceGroup" to "2026-09-21T14:13Z",
    )

    @Test
    fun `parsePlan reads the codec map`() {
        val alerts = EngineJson.parsePlan(mapOf("version" to 1, "alerts" to listOf(dartAlert("a", NOW))))
        val a = alerts.single()
        assertEquals("a", a.id)
        assertEquals(NOW, a.fireAtUtcMs)
        assertEquals(Strength.HEADS_UP, a.strength)
        assertEquals(Sound(null, vibrate = true, gradualVolume = false, ringTimeoutSec = 120), a.sound)
        assertNull(a.event.location)
        assertEquals(0xFF6AA0F5L, a.event.color)
        assertEquals(0xFF6AA0F5.toInt(), a.event.color.toInt())
    }

    @Test(expected = IllegalArgumentException::class)
    fun `parsePlan rejects an unknown version`() {
        EngineJson.parsePlan(mapOf("version" to 2, "alerts" to emptyList<Any>()))
    }

    @Test(expected = IllegalArgumentException::class)
    fun `parsePlan rejects an unknown strength`() {
        EngineJson.parsePlan(mapOf("version" to 1, "alerts" to listOf(dartAlert("a", NOW) + ("strength" to "loud"))))
    }

    @Test
    fun `an alert written by Kotlin reads back equal`() {
        val a = alert("a", NOW, joinUrl = "https://teams.microsoft.com/l/meetup-join/x", location = null, toneUri = "content://t")
        assertEquals(a, EngineJson.alertFromJson(EngineJson.alertToJson(a)))
    }

    @Test
    fun `toMap turns JSON nulls into Kotlin nulls`() {
        val map = EngineJson.toMap(EngineJson.alertToJson(alert("a", NOW, location = null)))
        @Suppress("UNCHECKED_CAST")
        val event = map["event"] as Map<String, Any?>
        assertNull(event["location"])
        assertEquals("a", map["id"])
    }
}
