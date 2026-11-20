package io.github.fifothehein.tminus.engine

import io.github.fifothehein.tminus.engine.MeetingService.GOOGLE_MEET
import io.github.fifothehein.tminus.engine.MeetingService.TEAMS
import io.github.fifothehein.tminus.engine.MeetingService.WEBEX
import io.github.fifothehein.tminus.engine.MeetingService.ZOOM
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class MeetingServiceTest {
    /** A link as Kotlin sees it (already found, unwrapped and decoded by Dart) and the service it names. */
    private data class Row(val url: String, val service: MeetingService?)

    /**
     * The 21 links that the Dart tests share, with invented ids: 5 Teams, 4 Google Meet, 5 Zoom, 3 Webex and
     * 4 that only look like join links. Dart unwraps Outlook Safe Links and Google redirect wrappers before a
     * link reaches Kotlin, so a wrapped row appears here as its decoded link.
     */
    private val table = listOf(
        Row("https://teams.microsoft.com/l/meetup-join/19%3ameeting_abc%40thread.v2/0", TEAMS),
        Row("https://teams.microsoft.com/meet/1234567890123", TEAMS),
        Row("https://teams.cloud.microsoft/meet/1234567890123", TEAMS),
        Row("https://teams.live.com/meet/1234567890123", TEAMS),
        // Decoded from a Safe Links wrapper: the percent-encoded context query stays as it is.
        Row(
            "https://teams.microsoft.com/l/meetup-join/19%3ameeting_def%40thread.v2/0" +
                "?context=%7b%22Tid%22%3a%2200000000-0000-0000-0000-000000000000%22%7d",
            TEAMS,
        ),

        Row("https://meet.google.com/abc-defg-hij", GOOGLE_MEET),
        Row("https://meet.google.com/abc-defg-hij?authuser=0", GOOGLE_MEET),
        // The form that an accepted Google invite has in Outlook.
        Row("https://meet.google.com/abc-defg-hij?hs=224", GOOGLE_MEET),
        // Decoded from a Google redirect (the url?q= wrapper).
        Row("https://meet.google.com/qrs-tuvw-xyz", GOOGLE_MEET),

        Row("https://us06web.zoom.us/j/12345678901?pwd=abc", ZOOM),
        Row("https://zoom.us/my/someone", ZOOM),
        Row("https://zoom.com/j/12345678901", ZOOM),
        Row("https://example.zoom.us/w/12345678901", ZOOM),
        // Decoded from a Safe Links wrapper.
        Row("https://us02web.zoom.us/j/98765432109?pwd=def456", ZOOM),

        Row("https://example.webex.com/example/j.php?MTID=m0123abcd", WEBEX),
        Row("https://example.webex.com/meet/someone", WEBEX),
        Row("https://example.webex.com/join/someone", WEBEX),

        Row("https://zoom.us/download", null),
        Row("https://www.webex.com/", null),
        Row("https://meet.google.com/", null),
        // The "more phone numbers" link that Google puts next to a Meet link.
        Row("https://tel.meet/abc-defg-hij?pin=1234", null),
    )

    private fun assertGives(rows: List<Row>, what: String) {
        val wrong = rows
            .filter { MeetingService.of(it.url) != it.service }
            .map { "${it.url} gave ${MeetingService.of(it.url)}, expected ${it.service}" }
        assertEquals(what, emptyList<String>(), wrong)
    }

    private fun assertTableGives(service: MeetingService?) =
        assertGives(table.filter { it.service == service }, "table rows that should give $service")

    private fun assertNoService(urls: List<String>, what: String) {
        val named = urls
            .filter { MeetingService.of(it) != null }
            .map { "$it gave ${MeetingService.of(it)}" }
        assertEquals(what, emptyList<String>(), named)
    }

    @Test
    fun `every Teams link in the table names Teams`() {
        assertTableGives(TEAMS)
    }

    @Test
    fun `every Meet link in the table names Google Meet`() {
        assertTableGives(GOOGLE_MEET)
    }

    @Test
    fun `every Zoom link in the table names Zoom`() {
        assertTableGives(ZOOM)
    }

    @Test
    fun `every Webex link in the table names Webex`() {
        assertTableGives(WEBEX)
    }

    @Test
    fun `links in the table that only look like join links name no service`() {
        assertTableGives(null)
    }

    @Test
    fun `each service has the name the app shows`() {
        assertEquals("Teams", TEAMS.label)
        assertEquals("Google Meet", GOOGLE_MEET.label)
        assertEquals("Zoom", ZOOM.label)
        assertEquals("Webex", WEBEX.label)
    }

    @Test
    fun `the host is matched ignoring case`() {
        assertGives(
            listOf(
                Row("https://TEAMS.MICROSOFT.COM/l/meetup-join/19%3ameeting_abc%40thread.v2/0", TEAMS),
                Row("https://Teams.Microsoft.com/meet/1234567890123", TEAMS),
                Row("https://TEAMS.CLOUD.MICROSOFT/meet/1234567890123", TEAMS),
                Row("https://Teams.Live.Com/meet/1234567890123", TEAMS),
                Row("https://MEET.GOOGLE.COM/abc-defg-hij", GOOGLE_MEET),
                Row("https://Meet.Google.com/abc-defg-hij?authuser=0", GOOGLE_MEET),
                Row("https://US06WEB.ZOOM.US/j/12345678901?pwd=abc", ZOOM),
                Row("https://Zoom.Com/my/someone", ZOOM),
                Row("https://EXAMPLE.WEBEX.COM/example/j.php?MTID=m0123abcd", WEBEX),
                Row("https://Example.Webex.com/join/someone", WEBEX),
            ),
            "mixed-case hosts that should still be recognised",
        )
    }

    @Test
    fun `a Teams meet link keeps its passcode query`() {
        assertEquals(TEAMS, MeetingService.of("https://teams.microsoft.com/meet/1234567890123?p=AbCdEf1234"))
    }

    @Test
    fun `a plain http version of a valid link is not a join link`() {
        val plain = table
            .filter { it.service != null }
            .map { it.url.replaceFirst("https://", "http://") }
        assertNoService(plain, "http versions of the valid table links")
    }

    @Test
    fun `a link without a scheme is not a join link`() {
        assertNoService(
            listOf(
                "teams.microsoft.com/meet/1234567890123",
                "meet.google.com/abc-defg-hij",
                "zoom.us/j/12345678901",
                "example.webex.com/meet/someone",
            ),
            "links written without https://",
        )
    }

    @Test
    fun `no link gives no service`() {
        assertNull(MeetingService.of(null))
        assertNull(MeetingService.of(""))
        assertNull(MeetingService.of("   "))
    }

    @Test
    fun `a look-alike host is not a join link`() {
        assertNoService(
            listOf(
                "https://evilzoom.us/j/123",
                "https://notzoom.com/j/12345678901",
                "https://zoom.us.evil.example/j/12345678901",
                "https://zoom.us@evil.example/j/12345678901",
                "https://evilwebex.com/meet/someone",
                "https://example.webex.com.evil.example/meet/someone",
                "https://meet.google.com.evil.example/abc-defg-hij",
                "https://evilmeet.google.com/abc-defg-hij",
                "https://teams.microsoft.com.evil.example/l/meetup-join/19%3ameeting_abc%40thread.v2/0",
                "https://evilteams.microsoft.com/meet/1234567890123",
                "https://teams.live.com.evil.example/meet/1234567890123",
            ),
            "look-alike hosts",
        )
    }

    @Test
    fun `other links on the four hosts are not join links`() {
        assertNoService(
            listOf(
                "https://zoom.us/",
                "https://zoom.us/j/",
                "https://example.webex.com/meet/",
                "https://meet.google.com/abcd-efgh-ijk",
                "https://meet.google.com/abc-defg-hijk",
                "https://meet.google.com/lookup/abc123",
                "https://teams.microsoft.com/l/channel/19%3aabc%40thread.tacv2/General",
            ),
            "links that only look like join links",
        )
    }

    @Test
    fun `a Webex join page link needs a non-empty MTID first in its query`() {
        // The grammar is .../j.php?MTID=<id>: the page alone, an empty id and an MTID that is not the first
        // query parameter are not join links.
        assertNoService(
            listOf(
                "https://example.webex.com/example/j.php",
                "https://example.webex.com/example/j.php?MTID=",
                "https://example.webex.com/example/j.php?x=1&MTID=m1",
            ),
            "Webex join page links without an MTID value in first place",
        )
    }

    @Test
    fun `edge forms decided for both Dart and Kotlin`() {
        // Kotlin and Dart must decide these forms the same way.
        assertGives(
            listOf(
                // Only a subdomain of webex.com counts, not the bare host.
                Row("https://webex.com/meet/someone", null),
                // A port is not part of any recognised link.
                Row("https://zoom.us:443/j/12345678901", null),
                // A link ends at its id: a trailing slash after it makes it something else.
                Row("https://meet.google.com/abc-defg-hij/", null),
                // A fragment is ignored.
                Row("https://zoom.us/j/12345678901#success", ZOOM),
            ),
            "edge forms",
        )
    }

    @Test
    fun `malformed text gives no service and never throws`() {
        assertNoService(
            listOf(
                "not a link",
                "%",
                "https://",
                "https:///j/12345678901",
                "https://[",
                "https://zoom.us/j/%zz",
            ),
            "malformed text",
        )
    }
}
