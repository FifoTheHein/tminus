package io.github.fifothehein.tminus.engine

import android.app.AlarmManager
import android.content.Context
import io.github.fifothehein.tminus.MainActivity
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.shadows.ShadowAlarmManager

@RunWith(RobolectricTestRunner::class)
class AlarmSchedulerTest {
    private val context: Context = RuntimeEnvironment.getApplication()
    private val alarmManager: AlarmManager = context.getSystemService(AlarmManager::class.java)
    private lateinit var store: PlanStore
    private lateinit var scheduler: AlarmScheduler

    @Before
    fun setUp() {
        ShadowAlarmManager.setCanScheduleExactAlarms(true)
        store = PlanStore(context).also { it.clear() }
        scheduler = AlarmScheduler(context, store) { NOW }
    }

    /** Scheduled alarms keyed by the alert id inside their PendingIntent. */
    private fun scheduled(): Map<String, ShadowAlarmManager.ScheduledAlarm> =
        shadowOf(alarmManager).scheduledAlarms.associateBy {
            shadowOf(it.operation).savedIntent.getStringExtra(AlarmReceiver.EXTRA_ALERT_ID)!!
        }

    @Test
    fun `alarms use setAlarmClock with a show intent and heads-ups use exact allow-while-idle`() {
        val alarm = alert("a", NOW + 10 * MINUTE_MS)
        val headsUp = alert("h", NOW + 5 * MINUTE_MS, strength = Strength.HEADS_UP)

        assertEquals(ApplyResult(armed = 2, cancelled = 0, kept = 0), scheduler.applyPlan(listOf(alarm, headsUp)))

        val s = scheduled()
        assertEquals(NOW + 10 * MINUTE_MS, s.getValue("a").triggerAtMs)
        val clock = s.getValue("a").alarmClockInfo
        assertNotNull(clock)
        assertEquals(MainActivity::class.java.name, shadowOf(clock!!.showIntent).savedIntent.component!!.className)
        assertEquals(NOW + 5 * MINUTE_MS, s.getValue("h").triggerAtMs)
        assertNull(s.getValue("h").alarmClockInfo)
        assertTrue(s.getValue("h").isAllowWhileIdle)
        assertEquals(AlarmManager.RTC_WAKEUP, s.getValue("h").type)
    }

    @Test
    fun `applying the same plan again keeps every alarm`() {
        val plan = listOf(alert("a", NOW + 10 * MINUTE_MS), alert("b", NOW + 20 * MINUTE_MS))
        scheduler.applyPlan(plan)
        assertEquals(ApplyResult(0, 0, 2), scheduler.applyPlan(plan))
        assertEquals(setOf("a", "b"), scheduled().keys)
    }

    @Test
    fun `new details at the same fire time keep the alarm and store the new snapshot`() {
        scheduler.applyPlan(listOf(alert("a", NOW + 10 * MINUTE_MS, title = "Old")))
        assertEquals(ApplyResult(0, 0, 1), scheduler.applyPlan(listOf(alert("a", NOW + 10 * MINUTE_MS, title = "New"))))
        assertEquals("New", store.read().plan.single().event.title)
    }

    @Test
    fun `alerts missing from the new plan are cancelled`() {
        val a = alert("a", NOW + 10 * MINUTE_MS)
        val b = alert("b", NOW + 20 * MINUTE_MS)
        scheduler.applyPlan(listOf(a, b))
        assertEquals(ApplyResult(0, 1, 1), scheduler.applyPlan(listOf(a)))
        assertEquals(setOf("a"), scheduled().keys)
        assertFalse(scheduler.isArmed(b))
    }

    @Test
    fun `a moved alert is re-armed at its new time`() {
        scheduler.applyPlan(listOf(alert("a", NOW + 10 * MINUTE_MS)))
        assertEquals(ApplyResult(1, 1, 0), scheduler.applyPlan(listOf(alert("a", NOW + 40 * MINUTE_MS))))
        assertEquals(1, shadowOf(alarmManager).scheduledAlarms.size)
        assertEquals(NOW + 40 * MINUTE_MS, scheduled().getValue("a").triggerAtMs)
    }

    @Test
    fun `past alerts are never armed`() {
        val result = scheduler.applyPlan(listOf(alert("p", NOW - MINUTE_MS), alert("n", NOW), alert("f", NOW + MINUTE_MS)))
        assertEquals(ApplyResult(1, 0, 0), result)
        assertEquals(setOf("f"), scheduled().keys)
        assertEquals(listOf("f"), store.read().plan.map { it.id })
    }

    @Test
    fun `acknowledged occurrences are skipped until their start time changes`() {
        val start = NOW + 30 * MINUTE_MS
        store.write(EngineState(acks = listOf(Ack("src|x|occ", start))))
        val sameStart = alert("x10", start - 10 * MINUTE_MS, occurrenceKey = "src|x|occ", start = start)
        val moved = alert("x1", start + HOUR - MINUTE_MS, occurrenceKey = "src|x|occ", start = start + HOUR)
        assertEquals(ApplyResult(1, 0, 0), scheduler.applyPlan(listOf(sameStart, moved)))
        assertEquals(setOf("x1"), scheduled().keys)
    }

    @Test
    fun `a dismissed alert is not re-armed at the same fire time`() {
        val fireAt = NOW + 10 * MINUTE_MS
        store.write(EngineState(dismissed = listOf(Dismissal("d", fireAt))))
        assertEquals(ApplyResult(0, 0, 0), scheduler.applyPlan(listOf(alert("d", fireAt))))
        assertEquals(ApplyResult(1, 0, 0), scheduler.applyPlan(listOf(alert("d", fireAt + 30 * MINUTE_MS))))
    }

    @Test
    fun `an alert already on screen is not armed again`() {
        // A coalesce sibling can fire up to a minute early; a plan arriving meanwhile must not re-arm it.
        val sibling = alert("s", NOW + 30_000)
        store.write(EngineState(presented = listOf(sibling)))
        assertEquals(ApplyResult(0, 0, 0), scheduler.applyPlan(listOf(sibling)))
    }

    @Test
    fun `snoozes survive while their occurrence is still planned`() {
        val planned = alert("a", NOW + 20 * MINUTE_MS, occurrenceKey = "src|m|occ")
        val snooze = alert("z:s", NOW + 5 * MINUTE_MS, occurrenceKey = "src|m|occ")
        store.write(EngineState(snoozes = listOf(snooze)))
        scheduler.arm(snooze)

        assertEquals(ApplyResult(1, 0, 0), scheduler.applyPlan(listOf(planned)))
        assertEquals(listOf(snooze), store.read().snoozes)
        assertTrue(scheduler.isArmed(snooze))
    }

    @Test
    fun `a snooze survives when the plan lists only its occurrence's past alerts`() {
        // Roadmap §3: the plan keeps every alert of an occurrence until it ends, past ones included.
        val start = NOW - MINUTE_MS // the meeting has started; its -1 alarm fired 2 min ago
        val pastAlarm = alert("m1", start - MINUTE_MS, occurrenceKey = "src|m|occ", start = start)
        val snooze = alert("m1:s", NOW + 4 * MINUTE_MS, occurrenceKey = "src|m|occ", start = start)
        store.write(EngineState(snoozes = listOf(snooze)))
        scheduler.arm(snooze)

        assertEquals(ApplyResult(0, 0, 0), scheduler.applyPlan(listOf(pastAlarm)))
        assertEquals(listOf(snooze), store.read().snoozes)
        assertTrue(scheduler.isArmed(snooze))
        assertTrue(store.read().plan.isEmpty()) // the past alert is never armed
    }

    @Test
    fun `snoozes of a cancelled meeting are dropped`() {
        val snooze = alert("z:s", NOW + 5 * MINUTE_MS, occurrenceKey = "src|gone|occ")
        store.write(EngineState(snoozes = listOf(snooze)))
        scheduler.arm(snooze)

        assertEquals(ApplyResult(1, 1, 0), scheduler.applyPlan(listOf(alert("other", NOW + HOUR))))
        assertTrue(store.read().snoozes.isEmpty())
        assertFalse(scheduler.isArmed(snooze))
    }

    @Test
    fun `snoozes of an acknowledged occurrence are dropped`() {
        val start = NOW + 10 * MINUTE_MS
        val snooze = alert("z:s", NOW + 5 * MINUTE_MS, occurrenceKey = "src|m|occ", start = start)
        store.write(EngineState(snoozes = listOf(snooze), acks = listOf(Ack("src|m|occ", start))))
        scheduler.arm(snooze)

        scheduler.applyPlan(listOf(alert("m1", start - MINUTE_MS, occurrenceKey = "src|m|occ", start = start)))
        assertTrue(store.read().snoozes.isEmpty())
        assertFalse(scheduler.isArmed(snooze))
    }

    @Test
    fun `a kept alert whose alarm vanished is armed again`() {
        val a = alert("a", NOW + 10 * MINUTE_MS)
        scheduler.applyPlan(listOf(a))
        scheduler.cancel("a") // what a force stop does to the app's alarms and PendingIntents
        assertEquals(ApplyResult(1, 0, 0), scheduler.applyPlan(listOf(a)))
        assertTrue(scheduler.isArmed(a))
        assertEquals(setOf("a"), scheduled().keys)
    }

    @Test
    fun `duplicate ids in one plan arm once`() {
        val a = alert("a", NOW + 10 * MINUTE_MS)
        assertEquals(ApplyResult(1, 0, 0), scheduler.applyPlan(listOf(a, a.copy(offsetMinutes = 99))))
    }

    @Test
    fun `rearmAll arms every future alert and drops past ones`() {
        store.write(
            EngineState(
                plan = listOf(alert("f", NOW + MINUTE_MS), alert("p", NOW - MINUTE_MS)),
                snoozes = listOf(alert("s:s", NOW + 2 * MINUTE_MS)),
                tests = listOf(alert("test-1", NOW + 5_000, occurrenceKey = "test|1")),
            ),
        )
        assertEquals(3, scheduler.rearmAll())
        assertEquals(setOf("f", "s:s", "test-1"), scheduled().keys)
        assertEquals(listOf("f"), store.read().plan.map { it.id })
    }

    @Test
    fun `without exact-alarm access alerts still get an inexact alarm`() {
        ShadowAlarmManager.setCanScheduleExactAlarms(false)
        scheduler.applyPlan(listOf(alert("a", NOW + 10 * MINUTE_MS)))
        val a = scheduled().getValue("a")
        assertNull(a.alarmClockInfo)
        assertTrue(a.isAllowWhileIdle)
        assertFalse(scheduler.canScheduleExactAlarms())
    }

    @Test
    fun `upcoming lists the next five scheduled alerts in time order`() {
        val alerts = (1..7).map { alert("a$it", NOW + (8 - it) * MINUTE_MS) }
        scheduler.applyPlan(alerts)
        assertEquals(listOf("a7", "a6", "a5", "a4", "a3"), scheduler.upcoming().map { it.id })
    }
}
