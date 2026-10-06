package io.github.fifothehein.tminus.engine

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Instant
import java.time.ZoneId
import java.util.Locale

class AlarmScreenModelTest {
    private val text = AlertText(ZoneId.of("Africa/Johannesburg"), is24Hour = true, locale = Locale.US)
    private val start = Instant.parse("2026-10-06T08:00:00Z").toEpochMilli() // 10:00 local
    private val link = "https://teams.microsoft.com/l/meetup-join/abc"

    private fun meeting(id: String, title: String, start: Long = this.start, joinUrl: String? = link) =
        alert(id, start - MINUTE_MS, start = start, title = title, joinUrl = joinUrl, location = null)

    @Test
    fun `a single alarm one minute before start`() {
        val m = AlarmScreenModel.of(listOf(meeting("a", "Sprint planning")), start - MINUTE_MS, text)!!
        assertEquals("ALARM −1", m.chip)
        assertEquals(AlarmScreenModel.Headline("Starts in", "1", "min"), m.headline)
        assertNull(m.subtitle)
        assertFalse(m.coalesced)
        val item = m.items.single()
        assertEquals("Sprint planning", item.title)
        assertEquals("10:00–10:30", item.range)
        assertEquals("Teams", item.where)
        assertEquals(link, item.joinUrl)
        assertEquals(listOf(SnoozeOption.PLUS_1_MIN, SnoozeOption.PLUS_5_MIN, SnoozeOption.AT_START), m.snoozeOptions)
    }

    @Test
    fun `starting now and started ago headlines`() {
        val a = listOf(meeting("a", "Sprint planning"))
        assertEquals(AlarmScreenModel.Headline(null, "Now", null), AlarmScreenModel.of(a, start, text)!!.headline)
        val late = AlarmScreenModel.of(a, start + 2 * MINUTE_MS, text)!!
        assertEquals(AlarmScreenModel.Headline("Started", "2", "min ago"), late.headline)
        assertEquals(listOf(SnoozeOption.PLUS_1_MIN, SnoozeOption.PLUS_5_MIN), late.snoozeOptions)
    }

    @Test
    fun `a heads-up shown on the screen says HEADS-UP`() {
        val h = alert("h", start - 10 * MINUTE_MS, strength = Strength.HEADS_UP, start = start)
        assertEquals("HEADS-UP −10", AlarmScreenModel.of(listOf(h), start - 10 * MINUTE_MS, text)!!.chip)
    }

    @Test
    fun `three meetings at the same start are coalesced and sorted by title`() {
        val alerts = listOf(
            meeting("s", "Sprint planning"),
            meeting("c", "Call the bank", joinUrl = null),
            meeting("r", "Architecture review"),
        )
        val m = AlarmScreenModel.of(alerts, start, text)!!
        assertTrue(m.coalesced)
        assertEquals("3 ALARMS", m.chip)
        assertEquals("3 meetings starting at 10:00", m.subtitle)
        assertEquals(listOf("Architecture review", "Call the bank", "Sprint planning"), m.items.map { it.title })
        assertNull(m.items[1].joinUrl)
    }

    @Test
    fun `different starts drop the time and use the earliest start for options`() {
        val m = AlarmScreenModel.of(
            listOf(meeting("late", "Later", start = start + 10 * MINUTE_MS), meeting("now", "Now one", start = start)),
            start,
            text,
        )!!
        assertEquals("2 meetings starting", m.subtitle)
        assertEquals(AlarmScreenModel.Headline(null, "Now", null), m.headline)
        assertEquals(listOf(SnoozeOption.PLUS_1_MIN, SnoozeOption.PLUS_5_MIN), m.snoozeOptions)
    }

    @Test
    fun `no alerts gives no model`() {
        assertNull(AlarmScreenModel.of(emptyList(), start, text))
    }

    @Test
    fun `calendar colours switch to the theme's variant`() {
        val darkBlue = 0xFF6AA0F5.toInt()
        val lightBlue = 0xFF2F6FD6.toInt()
        val pairs = listOf(darkBlue to lightBlue)
        assertEquals(lightBlue, CalendarColors.forTheme(darkBlue, dark = false, pairs = pairs))
        assertEquals(darkBlue, CalendarColors.forTheme(lightBlue, dark = true, pairs = pairs))
        assertEquals(darkBlue, CalendarColors.forTheme(0x806AA0F5.toInt(), dark = true, pairs = pairs)) // alpha ignored
        assertEquals(0xFF123456.toInt(), CalendarColors.forTheme(0xFF123456.toInt(), dark = false, pairs = pairs))
    }
}
