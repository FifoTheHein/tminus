package io.github.fifothehein.tminus.engine

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import java.time.Instant
import java.time.ZoneId
import java.util.Locale

class AlertTextTest {
    private val zone = ZoneId.of("Africa/Johannesburg")
    private val text = AlertText(zone, is24Hour = true, locale = Locale.US)
    private val start = Instant.parse("2026-10-06T08:00:00Z").toEpochMilli() // 10:00 in Johannesburg

    private fun meeting(joinUrl: String? = null, location: String? = null, title: String = "Sprint planning") =
        alert("a", start - MINUTE_MS, start = start, title = title, joinUrl = joinUrl, location = location)

    @Test
    fun `range uses local time and an en dash`() {
        assertEquals("10:00–10:30", text.range(meeting().event))
    }

    @Test
    fun `12-hour devices get AM and PM`() {
        assertEquals("10:00 AM", AlertText(zone, is24Hour = false, locale = Locale.US).time(start))
    }

    @Test
    fun `where shows Teams and the location without repeating Teams`() {
        val link = "https://teams.microsoft.com/l/meetup-join/abc"
        assertEquals("Teams", text.where(meeting(joinUrl = link).event))
        assertEquals("Teams", text.where(meeting(joinUrl = link, location = "Microsoft Teams Meeting").event))
        assertEquals("Teams · Boardroom 2", text.where(meeting(joinUrl = link, location = "Boardroom 2").event))
        assertEquals("Boardroom 2", text.where(meeting(location = "Boardroom 2").event))
        assertNull(text.where(meeting(location = "  ").event))
        assertNull(text.where(meeting().event))
    }

    @Test
    fun `detail joins range and place`() {
        assertEquals("10:00–10:30 · Teams", text.detail(meeting(joinUrl = "https://teams.microsoft.com/l/meetup-join/abc").event))
        assertEquals("10:00–10:30", text.detail(meeting().event))
    }

    @Test
    fun `titles match the brief`() {
        val a = meeting()
        assertEquals("In 10 min · Sprint planning", text.headsUpTitle(a, start - 10 * MINUTE_MS))
        assertEquals("Starts in 1 min · Sprint planning", text.ringingTitle(a, start - MINUTE_MS))
        assertEquals("Starting now · Sprint planning", text.ringingTitle(a, start))
        assertEquals("Missed: Design review (14:00)", text.missedTitle(
            alert("d", start + 4 * HOUR - MINUTE_MS, start = start + 4 * HOUR, title = "Design review"),
        ))
        assertEquals("3 meetings starting", text.coalescedTitle(3))
        assertEquals("Sprint planning, Call the bank", text.coalescedText(listOf(a, meeting(title = "Call the bank"))))
    }
}
