package io.github.fifothehein.tminus.engine

/** How far an event's start is from now, worded as the alarm screen and notifications show it. */
sealed interface Countdown {
    data class StartsIn(val minutes: Long) : Countdown
    data object StartingNow : Countdown
    data class StartedAgo(val minutes: Long) : Countdown

    /** "Starts in 1 min" · "Starting now" · "Started 2 min ago". */
    fun sentence(): String = when (this) {
        is StartsIn -> "Starts in $minutes min"
        StartingNow -> "Starting now"
        is StartedAgo -> "Started $minutes min ago"
    }

    /** Heads-up form: "In 10 min" · "Now" · "Started 2 min ago". */
    fun short(): String = when (this) {
        is StartsIn -> "In $minutes min"
        StartingNow -> "Now"
        is StartedAgo -> "Started $minutes min ago"
    }

    companion object {
        /** Rounds up before the start (30 s → 1 min) and down after it. */
        fun of(nowUtcMs: Long, startUtcMs: Long): Countdown {
            val delta = startUtcMs - nowUtcMs
            return when {
                delta > 0 -> StartsIn((delta + MINUTE_MS - 1) / MINUTE_MS)
                delta > -MINUTE_MS -> StartingNow
                else -> StartedAgo(-delta / MINUTE_MS)
            }
        }
    }
}
