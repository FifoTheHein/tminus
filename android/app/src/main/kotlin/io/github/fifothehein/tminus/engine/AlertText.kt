package io.github.fifothehein.tminus.engine

import android.content.Context
import android.text.format.DateFormat
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale

/** Every user-visible engine string, in the device's time zone and 12/24-hour setting. */
class AlertText(zone: ZoneId, is24Hour: Boolean, locale: Locale = Locale.getDefault()) {
    private val clockFormat = DateTimeFormatter.ofPattern(if (is24Hour) "HH:mm" else "h:mm a", locale).withZone(zone)

    fun time(utcMs: Long): String = clockFormat.format(Instant.ofEpochMilli(utcMs))

    /** "10:00–11:00" with an en dash. */
    fun range(e: EventSnapshot): String = "${time(e.startUtcMs)}–${time(e.endUtcMs)}"

    /** "Teams", "Boardroom 2" or "Teams · Boardroom 2"; a Teams location text is not repeated. */
    fun where(e: EventSnapshot): String? {
        val parts = mutableListOf<String>()
        if (e.joinUrl != null) parts += "Teams"
        val location = e.location?.trim().orEmpty()
        if (location.isNotEmpty() && !(e.joinUrl != null && location.contains("Teams", ignoreCase = true))) parts += location
        return parts.joinToString(" · ").ifEmpty { null }
    }

    fun detail(e: EventSnapshot): String = listOfNotNull(range(e), where(e)).joinToString(" · ")

    /** "In 10 min · Sprint planning" (brief §10). */
    fun headsUpTitle(a: PlannedAlert, nowUtcMs: Long): String =
        "${Countdown.of(nowUtcMs, a.event.startUtcMs).short()} · ${a.event.title}"

    /** "Starts in 1 min · Sprint planning" (mockup 6a). */
    fun ringingTitle(a: PlannedAlert, nowUtcMs: Long): String =
        "${Countdown.of(nowUtcMs, a.event.startUtcMs).sentence()} · ${a.event.title}"

    fun coalescedTitle(count: Int): String = "$count meetings starting"

    fun coalescedText(alerts: List<PlannedAlert>): String = alerts.joinToString(", ") { it.event.title }

    /** "Missed: Sprint planning (10:00)" (brief §10). */
    fun missedTitle(a: PlannedAlert): String = "Missed: ${a.event.title} (${time(a.event.startUtcMs)})"

    companion object {
        fun forDevice(context: Context) = AlertText(ZoneId.systemDefault(), DateFormat.is24HourFormat(context))
    }
}
