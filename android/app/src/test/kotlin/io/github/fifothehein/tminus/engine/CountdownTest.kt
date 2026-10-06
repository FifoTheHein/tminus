package io.github.fifothehein.tminus.engine

import org.junit.Assert.assertEquals
import org.junit.Test

class CountdownTest {
    private val now = 1_790_000_000_000L

    @Test
    fun `before the start minutes round up`() {
        assertEquals(Countdown.StartsIn(1), Countdown.of(now, now + MINUTE_MS))
        assertEquals(Countdown.StartsIn(1), Countdown.of(now, now + 30_000))
        assertEquals(Countdown.StartsIn(2), Countdown.of(now, now + MINUTE_MS + 1_000))
        assertEquals(Countdown.StartsIn(10), Countdown.of(now, now + 10 * MINUTE_MS))
    }

    @Test
    fun `the first minute after the start is Starting now`() {
        assertEquals(Countdown.StartingNow, Countdown.of(now, now))
        assertEquals(Countdown.StartingNow, Countdown.of(now, now - 59_000))
    }

    @Test
    fun `after a minute minutes round down`() {
        assertEquals(Countdown.StartedAgo(1), Countdown.of(now, now - MINUTE_MS))
        assertEquals(Countdown.StartedAgo(2), Countdown.of(now, now - 150_000))
    }

    @Test
    fun `sentences match the brief`() {
        assertEquals("Starts in 1 min", Countdown.StartsIn(1).sentence())
        assertEquals("Starting now", Countdown.StartingNow.sentence())
        assertEquals("Started 2 min ago", Countdown.StartedAgo(2).sentence())
    }

    @Test
    fun `short forms are for heads-up titles`() {
        assertEquals("In 10 min", Countdown.StartsIn(10).short())
        assertEquals("Now", Countdown.StartingNow.short())
        assertEquals("Started 2 min ago", Countdown.StartedAgo(2).short())
    }
}
