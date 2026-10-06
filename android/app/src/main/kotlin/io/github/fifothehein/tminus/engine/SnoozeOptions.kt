package io.github.fifothehein.tminus.engine

/** One minute in milliseconds. */
const val MINUTE_MS: Long = 60_000L

/** The four smart-snooze choices (spec §6). Pure Kotlin, so it runs in plain JUnit. */
enum class SnoozeOption(val label: String) {
    PLUS_1_MIN("+1 min"),
    PLUS_5_MIN("+5 min"),
    ONE_MIN_BEFORE_START("1 min before start"),
    AT_START("At start");

    /** The absolute UTC time this option snoozes until. */
    fun untilUtcMs(nowUtcMs: Long, startUtcMs: Long): Long = when (this) {
        PLUS_1_MIN -> nowUtcMs + MINUTE_MS
        PLUS_5_MIN -> nowUtcMs + 5 * MINUTE_MS
        ONE_MIN_BEFORE_START -> startUtcMs - MINUTE_MS
        AT_START -> startUtcMs
    }
}

object SnoozeOptions {
    /** Options whose time is still in the future, in display order (spec §6: past options are hidden). */
    fun visible(nowUtcMs: Long, startUtcMs: Long): List<SnoozeOption> =
        SnoozeOption.entries.filter { it.untilUtcMs(nowUtcMs, startUtcMs) > nowUtcMs }

    /**
     * The option behind a notification's single Snooze action (roadmap §5.1): +5 min;
     * At start if the meeting starts sooner than that; +1 min once it has started.
     */
    fun notificationDefault(nowUtcMs: Long, startUtcMs: Long): SnoozeOption = when {
        startUtcMs <= nowUtcMs -> SnoozeOption.PLUS_1_MIN
        startUtcMs < nowUtcMs + 5 * MINUTE_MS -> SnoozeOption.AT_START
        else -> SnoozeOption.PLUS_5_MIN
    }

    /** [option]'s time, or +1 min when that time is not in the future. */
    fun untilOrNextMinute(option: SnoozeOption, nowUtcMs: Long, startUtcMs: Long): Long {
        val until = option.untilUtcMs(nowUtcMs, startUtcMs)
        return if (until > nowUtcMs) until else nowUtcMs + MINUTE_MS
    }
}
