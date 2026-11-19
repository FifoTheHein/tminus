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

    /**
     * The join link's service, then the location: "Zoom", "Boardroom 2" or "Google Meet · Boardroom 2".
     * A location that already names the service ("Microsoft Teams Meeting"), or is itself a link of
     * that service (Outlook writes the bare Meet link into LOCATION), is not repeated. A link of no
     * known service adds nothing.
     */
    fun where(e: EventSnapshot): String? {
        val service = MeetingService.of(e.joinUrl)
        val parts = mutableListOf<String>()
        if (service != null) parts += service.label
        val location = e.location?.trim().orEmpty()
        val repeatsService = service != null &&
            (location.contains(service.label, ignoreCase = true) || MeetingService.of(location) == service)
        if (location.isNotEmpty() && !repeatsService) parts += location
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
