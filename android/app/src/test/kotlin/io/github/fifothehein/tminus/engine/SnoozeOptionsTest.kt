package io.github.fifothehein.tminus.engine

import org.junit.Assert.assertEquals
import org.junit.Test

class SnoozeOptionsTest {
    private val now = 1_790_000_000_000L

    @Test
    fun `all four options are visible ten minutes before start`() {
        assertEquals(SnoozeOption.entries.toList(), SnoozeOptions.visible(now, now + 10 * MINUTE_MS))
    }

    @Test
    fun `one minute before start hides 1 min before start`() {
        assertEquals(
            listOf(SnoozeOption.PLUS_1_MIN, SnoozeOption.PLUS_5_MIN, SnoozeOption.AT_START),
            SnoozeOptions.visible(now, now + MINUTE_MS),
        )
    }

    @Test
    fun `thirty seconds before start still offers At start`() {
        assertEquals(
            listOf(SnoozeOption.PLUS_1_MIN, SnoozeOption.PLUS_5_MIN, SnoozeOption.AT_START),
            SnoozeOptions.visible(now, now + 30_000),
        )
    }

    @Test
    fun `exactly at start only the relative options remain`() {
        assertEquals(listOf(SnoozeOption.PLUS_1_MIN, SnoozeOption.PLUS_5_MIN), SnoozeOptions.visible(now, now))
    }

    @Test
    fun `after start only the relative options remain`() {
        assertEquals(
            listOf(SnoozeOption.PLUS_1_MIN, SnoozeOption.PLUS_5_MIN),
            SnoozeOptions.visible(now, now - 2 * MINUTE_MS),
        )
    }

    @Test
    fun `each option snoozes until the right time`() {
        val start = now + 10 * MINUTE_MS
        assertEquals(now + MINUTE_MS, SnoozeOption.PLUS_1_MIN.untilUtcMs(now, start))
        assertEquals(now + 5 * MINUTE_MS, SnoozeOption.PLUS_5_MIN.untilUtcMs(now, start))
        assertEquals(start - MINUTE_MS, SnoozeOption.ONE_MIN_BEFORE_START.untilUtcMs(now, start))
        assertEquals(start, SnoozeOption.AT_START.untilUtcMs(now, start))
    }

    @Test
    fun `labels match the brief`() {
        assertEquals(
            listOf("+1 min", "+5 min", "1 min before start", "At start"),
            SnoozeOption.entries.map { it.label },
        )
    }

    @Test
    fun `notification default is plus 5 when the meeting is at least 5 min away`() {
        assertEquals(SnoozeOption.PLUS_5_MIN, SnoozeOptions.notificationDefault(now, now + 10 * MINUTE_MS))
        assertEquals(SnoozeOption.PLUS_5_MIN, SnoozeOptions.notificationDefault(now, now + 5 * MINUTE_MS))
    }

    @Test
    fun `notification default is At start when the meeting starts sooner than 5 min`() {
        assertEquals(SnoozeOption.AT_START, SnoozeOptions.notificationDefault(now, now + 3 * MINUTE_MS))
        assertEquals(SnoozeOption.AT_START, SnoozeOptions.notificationDefault(now, now + 5 * MINUTE_MS - 1))
    }

    @Test
    fun `notification default is plus 1 once the meeting has started`() {
        assertEquals(SnoozeOption.PLUS_1_MIN, SnoozeOptions.notificationDefault(now, now))
        assertEquals(SnoozeOption.PLUS_1_MIN, SnoozeOptions.notificationDefault(now, now - MINUTE_MS))
    }

    @Test
    fun `untilOrNextMinute turns a past option into plus 1 min`() {
        assertEquals(now + MINUTE_MS, SnoozeOptions.untilOrNextMinute(SnoozeOption.AT_START, now, now - MINUTE_MS))
        assertEquals(now + 3 * MINUTE_MS, SnoozeOptions.untilOrNextMinute(SnoozeOption.AT_START, now, now + 3 * MINUTE_MS))
    }
}
