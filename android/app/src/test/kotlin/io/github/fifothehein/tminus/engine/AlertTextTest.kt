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

    private val zoomLink = "https://example.zoom.us/j/12345678901?pwd=abc"
    private val meetLink = "https://meet.google.com/abc-defg-hij"
    private val webexLink = "https://example.webex.com/meet/someone"

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
    fun `where shows Zoom and does not repeat it`() {
        assertEquals("Zoom", text.where(meeting(joinUrl = zoomLink).event))
        assertEquals("Zoom", text.where(meeting(joinUrl = zoomLink, location = "Zoom").event))
        assertEquals("Zoom", text.where(meeting(joinUrl = zoomLink, location = "Zoom Meeting").event))
        assertEquals("Zoom", text.where(meeting(joinUrl = zoomLink, location = zoomLink).event))
        assertEquals("Zoom · Boardroom 2", text.where(meeting(joinUrl = zoomLink, location = "Boardroom 2").event))
    }

    @Test
    fun `where shows Google Meet and the location`() {
        assertEquals("Google Meet", text.where(meeting(joinUrl = meetLink).event))
        assertEquals("Google Meet · Boardroom 2", text.where(meeting(joinUrl = meetLink, location = "Boardroom 2").event))
        assertEquals("Google Meet · Boardroom 2", text.where(meeting(joinUrl = meetLink, location = "  Boardroom 2  ").event))
        assertEquals("Google Meet", text.where(meeting(joinUrl = meetLink, location = "Google Meet").event))
        assertEquals("Google Meet", text.where(meeting(joinUrl = meetLink, location = "  ").event))
    }

    @Test
    fun `where does not repeat the Meet link that Outlook puts in the location`() {
        // An accepted Google invite in Outlook has the bare Meet link as its whole location, while the link
        // found in its description carries Outlook's hs query.
        val joinUrl = "https://meet.google.com/abc-defg-hij?hs=224"
        assertEquals("Google Meet", text.where(meeting(joinUrl = joinUrl, location = "https://meet.google.com/abc-defg-hij").event))
        assertEquals("Google Meet", text.where(meeting(joinUrl = joinUrl, location = "  https://meet.google.com/abc-defg-hij  ").event))
        // A location that is a join link of the same service is skipped whichever form of the link it holds.
        assertEquals("Google Meet", text.where(meeting(joinUrl = meetLink, location = joinUrl).event))
    }

    @Test
    fun `where shows Webex and the location`() {
        assertEquals("Webex", text.where(meeting(joinUrl = webexLink).event))
        assertEquals("Webex", text.where(meeting(joinUrl = webexLink, location = "Webex").event))
        assertEquals("Webex", text.where(meeting(joinUrl = webexLink, location = webexLink).event))
        assertEquals("Webex · Boardroom 2", text.where(meeting(joinUrl = webexLink, location = "Boardroom 2").event))
    }

    @Test
    fun `a location holding the service name in any case is not repeated`() {
        assertEquals("Zoom", text.where(meeting(joinUrl = zoomLink, location = "ZOOM MEETING").event))
        assertEquals("Google Meet", text.where(meeting(joinUrl = meetLink, location = "google meet").event))
        assertEquals("Webex", text.where(meeting(joinUrl = webexLink, location = "Cisco WebEx Meetings").event))
    }

    @Test
    fun `a link of no known service adds no name and leaves only the location`() {
        val other = "https://example.com/join/12345"
        assertEquals("Boardroom 2", text.where(meeting(joinUrl = other, location = "Boardroom 2").event))
        assertNull(text.where(meeting(joinUrl = other).event))
    }

    @Test
    fun `detail joins range and place`() {
        assertEquals("10:00–10:30 · Teams", text.detail(meeting(joinUrl = "https://teams.microsoft.com/l/meetup-join/abc").event))
        assertEquals("10:00–10:30", text.detail(meeting().event))
    }

    @Test
    fun `detail names the service of the link`() {
        assertEquals("10:00–10:30 · Zoom", text.detail(meeting(joinUrl = zoomLink).event))
        assertEquals("10:00–10:30 · Google Meet", text.detail(meeting(joinUrl = meetLink).event))
        assertEquals("10:00–10:30 · Webex", text.detail(meeting(joinUrl = webexLink).event))
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
