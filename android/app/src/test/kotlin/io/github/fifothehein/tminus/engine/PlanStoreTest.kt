package io.github.fifothehein.tminus.engine

import android.content.Context
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import java.io.File

@RunWith(RobolectricTestRunner::class)
class PlanStoreTest {
    private val context: Context = RuntimeEnvironment.getApplication()
    private lateinit var store: PlanStore

    @Before
    fun setUp() {
        store = PlanStore(context)
        store.clear()
    }

    @Test
    fun `a fresh store reads as the empty state`() {
        assertEquals(EngineState.EMPTY, store.read())
    }

    @Test
    fun `state round-trips through a new store instance`() {
        val state = EngineState(
            plan = listOf(
                alert("a", NOW + 10 * MINUTE_MS, joinUrl = "https://teams.microsoft.com/l/meetup-join/x"),
                alert("b", NOW + 20 * MINUTE_MS, strength = Strength.HEADS_UP, location = null),
            ),
            snoozes = listOf(alert("c:s", NOW + 5 * MINUTE_MS)),
            tests = listOf(alert("test-1", NOW + 5_000, occurrenceKey = "test|1")),
            presented = listOf(alert("d", NOW - MINUTE_MS, toneUri = "content://media/internal/audio/media/7")),
            acks = listOf(Ack("src|e|occ", NOW + HOUR)),
            dismissed = listOf(Dismissal("f", NOW - MINUTE_MS)),
        )
        store.write(state)
        assertEquals(state, PlanStore(context).read())
    }

    @Test
    fun `the file lives in device-protected storage`() {
        store.write(EngineState.EMPTY)
        val protectedDir = context.createDeviceProtectedStorageContext().filesDir.canonicalPath
        assertTrue(store.stateFile.canonicalPath.startsWith(protectedDir))
        assertTrue(store.stateFile.exists())
    }

    @Test
    fun `write replaces the file and leaves no temp file`() {
        store.write(EngineState(plan = listOf(alert("a", NOW + MINUTE_MS))))
        store.write(EngineState(plan = listOf(alert("b", NOW + MINUTE_MS))))
        assertEquals(listOf("b"), store.read().plan.map { it.id })
        assertFalse(store.tempFile.exists())
    }

    @Test
    fun `a half-written temp file from a crash is ignored`() {
        val good = EngineState(plan = listOf(alert("a", NOW + MINUTE_MS)))
        store.write(good)
        store.tempFile.writeText("{\"version\":1,\"plan\":[{\"id\":") // the process died mid-write
        assertEquals(good, store.read())
        store.write(EngineState.EMPTY) // the next write still succeeds over the stale temp file
        assertEquals(EngineState.EMPTY, store.read())
        assertFalse(store.tempFile.exists())
    }

    @Test
    fun `a corrupt file reads as the empty state and is kept for diagnosis`() {
        store.stateFile.parentFile!!.mkdirs()
        store.stateFile.writeText("not json at all")
        assertEquals(EngineState.EMPTY, store.read())
        assertTrue(File(store.stateFile.parentFile, "state.json.corrupt").exists())
    }

    @Test
    fun `valid JSON with a missing field also reads as empty`() {
        store.stateFile.parentFile!!.mkdirs()
        store.stateFile.writeText("{\"version\":1,\"plan\":[]}")
        assertEquals(EngineState.EMPTY, store.read())
    }

    @Test
    fun `update persists the new state and returns the block result`() {
        val result = store.update { s -> s.copy(acks = listOf(Ack("k", 1L))) to "done" }
        assertEquals("done", result)
        assertEquals(listOf(Ack("k", 1L)), PlanStore(context).read().acks)
    }

    @Test
    fun `scheduled is plan plus snoozes plus tests`() {
        val s = EngineState(
            plan = listOf(alert("p", NOW)),
            snoozes = listOf(alert("s:s", NOW)),
            tests = listOf(alert("test-1", NOW, occurrenceKey = "test|1")),
            presented = listOf(alert("x", NOW)),
        )
        assertEquals(listOf("p", "s:s", "test-1"), s.scheduled.map { it.id })
        assertEquals(listOf("p"), s.withoutScheduled(setOf("s:s", "test-1")).scheduled.map { it.id })
    }

    @Test
    fun `coalesce groups match the Dart format`() {
        assertEquals("2026-09-21T14:13Z", CoalesceGroups.groupFor(NOW))
    }
}
