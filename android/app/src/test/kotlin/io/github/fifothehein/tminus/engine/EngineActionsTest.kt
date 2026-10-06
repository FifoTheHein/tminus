package io.github.fifothehein.tminus.engine

import android.content.Context
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.shadows.ShadowAlarmManager

@RunWith(RobolectricTestRunner::class)
class EngineActionsTest {
    private val context: Context = RuntimeEnvironment.getApplication()
    private var now = NOW
    private lateinit var store: PlanStore
    private lateinit var scheduler: AlarmScheduler
    private lateinit var presenter: FakePresenter
    private lateinit var actions: EngineActions

    private class FakePresenter : AlertPresenter {
        val presented = mutableListOf<List<PlannedAlert>>()
        val withdrawn = mutableListOf<PlannedAlert>()
        val missed = mutableListOf<PlannedAlert>()
        override fun present(alerts: List<PlannedAlert>) { presented.add(alerts) }
        override fun withdraw(alerts: List<PlannedAlert>) { withdrawn.addAll(alerts) }
        override fun missed(alerts: List<PlannedAlert>) { missed.addAll(alerts) }
    }

    @Before
    fun setUp() {
        ShadowAlarmManager.setCanScheduleExactAlarms(true)
        now = NOW
        store = PlanStore(context).also { it.clear() }
        EventQueue(context).drain()
        scheduler = AlarmScheduler(context, store) { now }
        presenter = FakePresenter()
        actions = EngineActions(context, presenter, store, scheduler) { now }
    }

    private fun events() = EventQueue(context).drain()

    @Test
    fun `fire presents the due coalesce group and queues fired events`() {
        val a = alert("a", NOW + MINUTE_MS, group = "G")
        val b = alert("b", NOW + MINUTE_MS + 20_000, group = "G")
        scheduler.applyPlan(listOf(a, b))
        now = NOW + MINUTE_MS + 20_000 // a's alarm arrives late: b is due as well

        assertEquals(listOf("a", "b"), actions.fire("a").map { it.id })

        assertEquals(listOf(listOf(a, b)), presenter.presented)
        assertFalse(scheduler.isArmed(b))
        val queued = events()
        assertEquals(listOf(EngineEventType.FIRED, EngineEventType.FIRED), queued.map { it.type })
        assertEquals(listOf("a", "b"), queued.map { it.alertId })
        assertEquals(listOf(now, now), queued.map { it.atUtcMs })
        assertEquals(setOf("a", "b"), store.read().presented.map { it.id }.toSet())
    }

    @Test
    fun `a later sibling is not collected and is still armed`() {
        val a = alert("a", NOW + MINUTE_MS, group = "G")
        val b = alert("b", NOW + MINUTE_MS + 20_000, group = "G")
        scheduler.applyPlan(listOf(a, b))
        now = NOW + MINUTE_MS

        assertEquals(listOf("a"), actions.fire("a").map { it.id })

        assertEquals(listOf(listOf(a)), presenter.presented)
        assertTrue(scheduler.isArmed(b))
        assertEquals(listOf("b"), store.read().plan.map { it.id })

        now = NOW + MINUTE_MS + 20_000 // b's own alarm
        assertEquals(listOf("b"), actions.fire("b").map { it.id })
        assertEquals(listOf(listOf(a), listOf(b)), presenter.presented)
        assertEquals(setOf("a", "b"), store.read().presented.map { it.id }.toSet())
    }

    @Test
    fun `firing an alert that is gone does nothing`() {
        assertTrue(actions.fire("nope").isEmpty())
        assertTrue(presenter.presented.isEmpty())
        assertTrue(events().isEmpty())
    }

    @Test
    fun `snooze with an option arms a snooze alarm and queues snoozed`() {
        val a = alert("a", NOW, start = NOW + 10 * MINUTE_MS)
        store.write(EngineState(presented = listOf(a)))

        actions.snooze(listOf("a"), SnoozeOption.PLUS_5_MIN)

        val snooze = store.read().snoozes.single()
        assertEquals("a:s", snooze.id)
        assertEquals(NOW + 5 * MINUTE_MS, snooze.fireAtUtcMs)
        assertTrue(scheduler.isArmed(snooze))
        val event = events().single()
        assertEquals(EngineEventType.SNOOZED, event.type)
        assertEquals("a", event.alertId)
        assertEquals(NOW + 5 * MINUTE_MS, event.snoozeUntilUtcMs)
        assertEquals(listOf(a), presenter.withdrawn)
    }

    @Test
    fun `snooze without an option uses the notification default`() {
        val start = NOW + 3 * MINUTE_MS // sooner than +5 min, so At start
        store.write(EngineState(presented = listOf(alert("a", NOW, start = start))))
        actions.snooze(listOf("a"), null)
        assertEquals(start, store.read().snoozes.single().fireAtUtcMs)
    }

    @Test
    fun `a past option snoozes for one minute instead`() {
        store.write(EngineState(presented = listOf(alert("a", NOW - 3 * MINUTE_MS, start = NOW - 2 * MINUTE_MS))))
        actions.snooze(listOf("a"), SnoozeOption.AT_START)
        assertEquals(NOW + MINUTE_MS, store.read().snoozes.single().fireAtUtcMs)
    }

    @Test
    fun `dismiss queues dismissed and records the dismissal`() {
        val a = alert("a", NOW)
        store.write(EngineState(presented = listOf(a)))
        actions.dismiss(listOf("a"))
        assertEquals(listOf(EngineEventType.DISMISSED), events().map { it.type })
        assertEquals(listOf(Dismissal("a", NOW)), store.read().dismissed)
        assertEquals(listOf(a), presenter.withdrawn)
    }

    @Test
    fun `dismissAll cancels the occurrence's later alarm and queues dismissedAll`() {
        val start = NOW + 10 * MINUTE_MS
        val headsUp = alert("h", NOW + MINUTE_MS, strength = Strength.HEADS_UP, occurrenceKey = "K", start = start)
        val alarm = alert("a1", NOW + 9 * MINUTE_MS, occurrenceKey = "K", start = start)
        scheduler.applyPlan(listOf(headsUp, alarm))
        now = NOW + MINUTE_MS
        actions.fire("h")
        events()

        actions.dismissAll(listOf("h"))

        assertFalse(scheduler.isArmed(alarm))
        assertEquals(listOf(Ack("K", start)), store.read().acks)
        assertEquals(listOf(EngineEventType.DISMISSED_ALL), events().map { it.type })
        assertTrue(presenter.withdrawn.any { it.id == "h" })
    }

    @Test
    fun `join returns the alert and queues joined`() {
        val j = alert("j", NOW, joinUrl = "https://teams.microsoft.com/l/meetup-join/abc")
        store.write(EngineState(presented = listOf(j)))
        assertEquals(j, actions.join("j"))
        assertEquals(listOf(EngineEventType.JOINED), events().map { it.type })
        assertEquals(listOf(Ack(j.occurrenceKey, j.event.startUtcMs)), store.read().acks)
        assertNull(actions.join("j"))
    }

    @Test
    fun `missed queues missed and hands the alerts to the presenter`() {
        val a = alert("a", NOW)
        store.write(EngineState(presented = listOf(a)))
        actions.missed(listOf("a"))
        assertEquals(listOf(EngineEventType.MISSED), events().map { it.type })
        assertEquals(listOf(a), presenter.missed)
        assertTrue(store.read().presented.isEmpty())
    }
}
