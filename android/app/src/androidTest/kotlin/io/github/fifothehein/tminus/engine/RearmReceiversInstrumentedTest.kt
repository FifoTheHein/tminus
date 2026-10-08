package io.github.fifothehein.tminus.engine

import android.content.Context
import android.content.Intent
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class RearmReceiversInstrumentedTest {
    private val context: Context = InstrumentationRegistry.getInstrumentation().targetContext
    private val store = PlanStore(context)
    private val scheduler = AlarmScheduler(context, store)
    private lateinit var saved: EngineState

    @Before
    fun saveAndClear() {
        saved = store.read()
        saved.scheduled.forEach { scheduler.cancel(it.id) }
        store.clear()
    }

    @After
    fun restore() {
        store.read().scheduled.forEach { scheduler.cancel(it.id) }
        store.write(saved)
        scheduler.rearmAll()
    }

    private fun alertAt(id: String, fireAt: Long, strength: Strength) = PlannedAlert(
        id = id,
        occurrenceKey = "instrumented|$id",
        fireAtUtcMs = fireAt,
        offsetMinutes = 1,
        strength = strength,
        sound = Sound.DEFAULT,
        event = EventSnapshot("Instrumented $id", fireAt + MINUTE_MS, fireAt + 31 * MINUTE_MS, null, null, 0xFF6AA0F5L),
        coalesceGroup = CoalesceGroups.groupFor(fireAt),
    )

    private fun seed(): Triple<PlannedAlert, PlannedAlert, PlannedAlert> {
        val now = System.currentTimeMillis()
        val alarm = alertAt("rearm-alarm", now + 2 * HOUR_MS, Strength.ALARM)
        val headsUp = alertAt("rearm-headsup", now + 3 * HOUR_MS, Strength.HEADS_UP)
        val past = alertAt("rearm-past", now - HOUR_MS, Strength.ALARM)
        store.write(EngineState(plan = listOf(alarm, headsUp, past)))
        assertFalse(scheduler.isArmed(alarm))
        return Triple(alarm, headsUp, past)
    }

    private fun assertRearmed(action: String, deliver: (Intent) -> Unit) {
        val (alarm, headsUp, past) = seed()
        deliver(Intent(action))
        assertTrue(action, scheduler.isArmed(alarm))
        assertTrue(action, scheduler.isArmed(headsUp))
        assertFalse(action, scheduler.isArmed(past))
        assertEquals(action, listOf(alarm.id, headsUp.id), store.read().plan.map { it.id })
        listOf(alarm, headsUp).forEach { scheduler.cancel(it.id) }
    }

    @Test
    fun lockedBootCompletedRearmsFromDeviceProtectedStorage() {
        assertRearmed(Intent.ACTION_LOCKED_BOOT_COMPLETED) { BootReceiver().onReceive(context, it) }
    }

    @Test
    fun bootCompletedAndPackageReplacedRearm() {
        assertRearmed(Intent.ACTION_BOOT_COMPLETED) { BootReceiver().onReceive(context, it) }
        assertRearmed(Intent.ACTION_MY_PACKAGE_REPLACED) { BootReceiver().onReceive(context, it) }
    }

    @Test
    fun timeZoneChangeRearmsFutureAlertsAndDropsPastOnes() {
        assertRearmed(Intent.ACTION_TIMEZONE_CHANGED) { TimeChangeReceiver().onReceive(context, it) }
    }

    @Test
    fun timeSetAndExactAlarmPermissionChangeRearm() {
        assertRearmed(Intent.ACTION_TIME_CHANGED) { TimeChangeReceiver().onReceive(context, it) }
        assertRearmed(TimeChangeReceiver.ACTION_EXACT_ALARM_PERMISSION_CHANGED) { TimeChangeReceiver().onReceive(context, it) }
    }

    private companion object {
        const val HOUR_MS = 60 * MINUTE_MS
    }
}
