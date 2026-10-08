package io.github.fifothehein.tminus.engine

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

class RingingSessionTest {
    @Before
    fun reset() = RingingSession.clear()

    @Test
    fun `add skips ids already ringing and notifies listeners`() {
        val seen = mutableListOf<List<String>>()
        val stop = RingingSession.observe { seen.add(it.map { a -> a.id }) }
        RingingSession.add(listOf(alert("a", NOW)))
        RingingSession.add(listOf(alert("a", NOW), alert("b", NOW)))
        assertEquals(listOf(listOf("a"), listOf("a", "b")), seen)
        assertEquals(setOf("a", "b"), RingingSession.ids)
        stop()
        RingingSession.remove(listOf("a"))
        assertEquals(2, seen.size) // unsubscribed
        assertEquals(setOf("b"), RingingSession.ids)
    }

    @Test
    fun `removing ids that are not ringing does not notify`() {
        RingingSession.add(listOf(alert("a", NOW)))
        var calls = 0
        RingingSession.observe { calls++ }
        RingingSession.remove(listOf("zzz"))
        assertEquals(0, calls)
        RingingSession.remove(listOf("a"))
        assertEquals(1, calls)
        assertTrue(RingingSession.alerts.isEmpty())
    }
}
