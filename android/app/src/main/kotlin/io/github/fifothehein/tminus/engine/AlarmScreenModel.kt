package io.github.fifothehein.tminus.engine

/** What the alarm screen shows, computed without Android types so it can be unit-tested. */
data class AlarmScreenModel(
    val chip: String,
    val headline: Headline,
    val subtitle: String?,
    val items: List<Item>,
    val snoozeOptions: List<SnoozeOption>,
) {
    val coalesced: Boolean get() = items.size > 1

    /** "Starts in" / "1" / "min", "Started" / "2" / "min ago", or just "Now". */
    data class Headline(val prefix: String?, val number: String, val unit: String?)

    data class Item(
        val alertId: String,
        val title: String,
        val range: String,
        val where: String?,
        val joinUrl: String?,
        val color: Long,
    )

    companion object {
        private const val MINUS = '−'

        fun of(alerts: List<PlannedAlert>, nowUtcMs: Long, text: AlertText): AlarmScreenModel? {
            if (alerts.isEmpty()) return null
            val sorted = alerts.sortedWith(compareBy({ it.event.startUtcMs }, { it.event.title }, { it.id }))
            val earliest = sorted.first().event.startUtcMs
            val lead = sorted.first()
            val chip = if (sorted.size > 1) {
                "${sorted.size} ALARMS"
            } else {
                "${if (lead.strength == Strength.ALARM) "ALARM" else "HEADS-UP"} $MINUS${lead.offsetMinutes}"
            }
            val subtitle = when {
                sorted.size == 1 -> null
                sorted.all { it.event.startUtcMs == earliest } -> "${sorted.size} meetings starting at ${text.time(earliest)}"
                else -> "${sorted.size} meetings starting"
            }
            return AlarmScreenModel(
                chip = chip,
                headline = headline(Countdown.of(nowUtcMs, earliest)),
                subtitle = subtitle,
                items = sorted.map {
                    Item(it.id, it.event.title, text.range(it.event), text.where(it.event), it.event.joinUrl, it.event.color)
                },
                snoozeOptions = SnoozeOptions.visible(nowUtcMs, earliest),
            )
        }

        private fun headline(c: Countdown): Headline = when (c) {
            is Countdown.StartsIn -> Headline("Starts in", c.minutes.toString(), "min")
            Countdown.StartingNow -> Headline(null, "Now", null)
            is Countdown.StartedAgo -> Headline("Started", c.minutes.toString(), "min ago")
        }
    }
}

/** Swaps a design-system calendar colour for its variant in the current theme; other colours pass through. */
object CalendarColors {
    fun forTheme(argb: Int, dark: Boolean, pairs: List<Pair<Int, Int>>): Int {
        val pair = pairs.firstOrNull { (d, l) -> sameRgb(argb, d) || sameRgb(argb, l) } ?: return argb
        return if (dark) pair.first else pair.second
    }

    private fun sameRgb(a: Int, b: Int) = (a and 0xFFFFFF) == (b and 0xFFFFFF)
}
