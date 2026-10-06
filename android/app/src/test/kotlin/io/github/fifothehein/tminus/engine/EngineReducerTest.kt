package io.github.fifothehein.tminus.engine

import org.junit.Assert.assertEquals
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test

class EngineReducerTest {
    @Test
    fun `fire moves the alert and its coalesce siblings to presented`() {
        val a = alert("a", NOW, start = NOW + MINUTE_MS, title = "Sprint planning", group = "G")
        val b = alert("b", NOW + 20_000, start = NOW + MINUTE_MS, title = "Architecture review", group = "G")
        val other = alert("c", NOW + 10 * MINUTE_MS)
        val t = EngineReducer.fire(EngineState(plan = listOf(a, other), snoozes = listOf(b)), "a")

        assertEquals(listOf("b", "a"), t.affected.map { it.id }) // same start, then by title
        assertEquals(listOf("b"), t.toCancel.map { it.id }) // the sibling's own alarm must not ring again
        assertEquals(listOf("c"), t.state.plan.map { it.id })
        assertTrue(t.state.snoozes.isEmpty())
        assertEquals(setOf("a", "b"), t.state.presented.map { it.id }.toSet())
    }

    @Test
    fun `fire also finds snoozes and test alerts`() {
        val test = alert("test-1", NOW, occurrenceKey = "test|1")
        val t = EngineReducer.fire(EngineState(tests = listOf(test)), "test-1")
        assertEquals(listOf(test), t.affected)
        assertTrue(t.state.tests.isEmpty())
    }

    @Test
    fun `firing an id that is gone changes nothing`() {
        val state = EngineState(plan = listOf(alert("a", NOW)))
        val t = EngineReducer.fire(state, "missing")
        assertSame(state, t.state)
        assertTrue(t.affected.isEmpty())
    }

    @Test
    fun `snooze creates a colon-s alert that keeps its strength`() {
        val a = alert("a", NOW, strength = Strength.HEADS_UP)
        val until = NOW + 5 * MINUTE_MS
        val t = EngineReducer.snooze(EngineState(presented = listOf(a)), listOf("a")) { until }

        val snooze = t.state.snoozes.single()
        assertEquals("a:s", snooze.id)
        assertEquals(until, snooze.fireAtUtcMs)
        assertEquals(CoalesceGroups.groupFor(until), snooze.coalesceGroup)
        assertEquals(Strength.HEADS_UP, snooze.strength)
        assertEquals(a.occurrenceKey, snooze.occurrenceKey)
        assertEquals(listOf(snooze), t.toArm)
        assertEquals(listOf(a), t.affected)
        assertEquals(listOf(a), t.withdrawn)
        assertTrue(t.state.presented.isEmpty())
    }

    @Test
    fun `snoozing a snooze keeps a single suffix and replaces the old one`() {
        assertEquals("a:s", EngineReducer.snoozeIdFor("a:s"))
        val presented = alert("a:s", NOW)
        val stale = alert("a:s", NOW - MINUTE_MS)
        val t = EngineReducer.snooze(EngineState(snoozes = listOf(stale), presented = listOf(presented)), listOf("a:s")) {
            NOW + MINUTE_MS
        }
        assertEquals(listOf(NOW + MINUTE_MS), t.state.snoozes.map { it.fireAtUtcMs })
    }

    @Test
    fun `a snoozed test alert stays with the test alerts`() {
        val test = alert("test-1", NOW, occurrenceKey = "test|1")
        val t = EngineReducer.snooze(EngineState(presented = listOf(test)), listOf("test-1")) { NOW + MINUTE_MS }
        assertEquals(listOf("test-1:s"), t.state.tests.map { it.id })
        assertTrue(t.state.snoozes.isEmpty())
    }

    @Test
    fun `dismiss records the alert and its fire time`() {
        val a = alert("a", NOW)
        val t = EngineReducer.dismiss(EngineState(presented = listOf(a)), listOf("a"))
        assertEquals(listOf(Dismissal("a", NOW)), t.state.dismissed)
        assertTrue(t.state.presented.isEmpty())
        assertEquals(listOf(a), t.withdrawn)
    }

    @Test
    fun `acknowledge acks the occurrence and cancels its remaining alerts at that start only`() {
        val start = NOW + 10 * MINUTE_MS
        val headsUp = alert("h", NOW, occurrenceKey = "K", start = start, strength = Strength.HEADS_UP)
        val later = alert("a1", start - MINUTE_MS, occurrenceKey = "K", start = start)
        val snooze = alert("x:s", NOW + MINUTE_MS, occurrenceKey = "K", start = start)
        val otherStart = alert("a2", start + HOUR - MINUTE_MS, occurrenceKey = "K", start = start + HOUR)
        val otherPresented = alert("h2", NOW, occurrenceKey = "K", start = start, strength = Strength.HEADS_UP)
        val state = EngineState(plan = listOf(later, otherStart), snoozes = listOf(snooze), presented = listOf(headsUp, otherPresented))

        val t = EngineReducer.acknowledge(state, listOf("h"))

        assertEquals(listOf(Ack("K", start)), t.state.acks)
        assertEquals(setOf("a1", "x:s"), t.toCancel.map { it.id }.toSet())
        assertEquals(listOf("a2"), t.state.plan.map { it.id })
        assertTrue(t.state.snoozes.isEmpty())
        assertEquals(listOf(headsUp), t.affected)
        assertEquals(setOf("h", "h2"), t.withdrawn.map { it.id }.toSet())
        assertTrue(t.state.presented.isEmpty())
    }

    @Test
    fun `missed removes the alerts without acking or dismissing`() {
        val a = alert("a", NOW)
        val t = EngineReducer.missed(EngineState(presented = listOf(a)), listOf("a"))
        assertTrue(t.state.presented.isEmpty())
        assertTrue(t.state.acks.isEmpty())
        assertTrue(t.state.dismissed.isEmpty())
        assertEquals(listOf(a), t.affected)
    }

    @Test
    fun `actions on alerts that are not presented do nothing`() {
        val state = EngineState(plan = listOf(alert("a", NOW)))
        assertSame(state, EngineReducer.dismiss(state, listOf("a")).state)
        assertSame(state, EngineReducer.acknowledge(state, listOf("a")).state)
        assertSame(state, EngineReducer.snooze(state, listOf("a")) { NOW }.state)
        assertSame(state, EngineReducer.missed(state, listOf("a")).state)
    }

    @Test
    fun `addTest schedules the test alert`() {
        val test = alert("test-1", NOW, occurrenceKey = "test|1")
        val t = EngineReducer.addTest(EngineState.EMPTY, test)
        assertEquals(listOf(test), t.state.tests)
        assertEquals(listOf(test), t.toArm)
    }

    @Test
    fun `prune drops acks and dismissals after 24 h and presented alerts an hour after the event ends`() {
        val day = 24 * HOUR
        val state = EngineState(
            acks = listOf(Ack("old", NOW - day - 1), Ack("fresh", NOW - day)),
            dismissed = listOf(Dismissal("old", NOW - day - 1), Dismissal("fresh", NOW)),
            presented = listOf(
                alert("ended", NOW - 2 * HOUR, start = NOW - 2 * HOUR), // ended 90 min ago
                alert("recent", NOW - MINUTE_MS),
            ),
        )
        val pruned = EngineReducer.prune(state, NOW)
        assertEquals(listOf("fresh"), pruned.acks.map { it.occurrenceKey })
        assertEquals(listOf("fresh"), pruned.dismissed.map { it.alertId })
        assertEquals(listOf("recent"), pruned.presented.map { it.id })
    }
}
