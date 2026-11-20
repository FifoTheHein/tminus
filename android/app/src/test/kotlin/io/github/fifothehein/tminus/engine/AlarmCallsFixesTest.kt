package io.github.fifothehein.tminus.engine

import android.app.AlarmManager
import android.app.Application
import android.app.PendingIntent
import android.content.Context
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.github.fifothehein.tminus.LoggedErrors
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Implementation
import org.robolectric.annotation.Implements
import org.robolectric.shadows.ShadowAlarmManager
import java.util.concurrent.Executor

/**
 * An AlarmManager whose every arm call fails with an IllegalStateException. That is not a SecurityException,
 * so no caller of it falls back to a weaker alarm. The message holds [LoggedErrors.SECRET] the way Android's
 * messages hold a package name or a type. Use it with `@Config(shadows = [...])`.
 */
@Implements(AlarmManager::class)
class FailingAlarmManagerShadow : ShadowAlarmManager() {
    @Implementation
    override fun setAlarmClock(info: AlarmManager.AlarmClockInfo, operation: PendingIntent) {
        throw IllegalStateException("AlarmManager cannot arm: ${LoggedErrors.SECRET}")
    }

    @Implementation
    override fun setExactAndAllowWhileIdle(type: Int, triggerAtMillis: Long, operation: PendingIntent) {
        throw IllegalStateException("AlarmManager cannot arm: ${LoggedErrors.SECRET}")
    }

    @Implementation
    override fun setAndAllowWhileIdle(type: Int, triggerAtMillis: Long, operation: PendingIntent) {
        throw IllegalStateException("AlarmManager cannot arm: ${LoggedErrors.SECRET}")
    }
}

/**
 * How the engine orders and answers its alarm calls on the AlarmCalls queue. Each test that looks at the
 * order holds the queue in its own hands: nothing runs until [runQueue], so "armed at once" and "armed only
 * behind the queue" can be told apart. A call that moved the wrong way fails the assertion made before the
 * queue runs, or the one after it.
 */
@RunWith(RobolectricTestRunner::class)
class AlarmCallsFixesTest {
    private val app: Application = RuntimeEnvironment.getApplication()
    private val context: Context = app
    private val alarmManager: AlarmManager = app.getSystemService(AlarmManager::class.java)
    private val queued = ArrayDeque<Runnable>()
    private lateinit var store: PlanStore

    @Before
    fun setUp() {
        ShadowAlarmManager.setCanScheduleExactAlarms(true)
        store = PlanStore(app).also { it.clear() }
        EventQueue(app).drain()
        RingingSession.clear()
    }

    @After
    fun tearDown() {
        // What TestTMinusApplication installs: calls that run at once, and a hook that rethrows a failure.
        AlarmCalls.executor = Executor { it.run() }
        AlarmCalls.failureHook = { throw it }
    }

    /** From here on nothing AlarmCalls is given runs until [runQueue] (or a test takes an item off [queued]). */
    private fun holdQueue() {
        AlarmCalls.executor = Executor { queued.add(it) }
    }

    /** Runs every queued call, and the calls those queue in turn, in the order they were queued. */
    private fun runQueue() {
        while (queued.isNotEmpty()) queued.removeFirst().run()
    }

    /** The alert id inside the PendingIntent of each alarm AlarmManager holds (null for an alarm that has none). */
    private fun scheduledIds(): Set<String?> = shadowOf(alarmManager).scheduledAlarms
        .mapNotNull { it.operation }
        .map { shadowOf(it).savedIntent.getStringExtra(AlarmReceiver.EXTRA_ALERT_ID) }
        .toSet()

    /** The alarms AlarmManager holds for [alertId]. */
    private fun alarmsFor(alertId: String) = shadowOf(alarmManager).scheduledAlarms
        .filter { alarm -> alarm.operation?.let { shadowOf(it).savedIntent.getStringExtra(AlarmReceiver.EXTRA_ALERT_ID) } == alertId }

    /** An answer to a channel call. [replies] tells "no answer yet" apart from a success with no value. */
    private class Recorded : MethodChannel.Result {
        var replies = 0
        var value: Any? = null
        var errorCode: String? = null
        override fun success(result: Any?) {
            replies++
            value = result
        }
        override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
            replies++
            this.errorCode = errorCode
        }
        override fun notImplemented() {
            replies++
        }
    }

    /** A presenter that shows nothing: these tests look at the alarms, not at what rings. */
    private class QuietPresenter : AlertPresenter {
        override fun present(alerts: List<PlannedAlert>) = Unit
        override fun withdraw(alerts: List<PlannedAlert>) = Unit
        override fun missed(alerts: List<PlannedAlert>) = Unit
        override fun isShowing(alert: PlannedAlert) = false
        override fun silence(alertIds: Collection<String>) = Unit
    }

    private val engineChannel: AlarmEngineChannel by lazy {
        AlarmEngineChannel(app, store, AlarmScheduler(app, store) { NOW }) { NOW }
    }

    /** Calls the alarm_engine channel's testAlarm for an alarm that rings in five seconds. */
    private fun testAlarmOnChannel(): Recorded {
        val args = mapOf("strength" to "alarm", "delaySec" to 5)
        return Recorded().also { engineChannel.onMethodCall(MethodCall("testAlarm", args), it) }
    }

    @Test
    fun `testAlarm replies after the drain`() {
        holdQueue()

        val first = testAlarmOnChannel()
        assertEquals("the channel replied before the queue ran", 0, first.replies)
        assertTrue("the test alarm was armed before the queue ran", scheduledIds().isEmpty())
        // One call at a time: the answer must never come ahead of the alarm call it waits for.
        while (queued.isNotEmpty()) {
            queued.removeFirst().run()
            if (first.replies > 0) assertEquals("the channel replied before its alarm call ran", 1, alarmsFor("test-$NOW").size)
        }
        assertEquals(1, first.replies)
        assertNull(first.errorCode)
        assertNull("testAlarm answers with no value", first.value)
        val alarm = alarmsFor("test-$NOW").single()
        assertEquals(NOW + 5_000, alarm.triggerAtMs)
        assertNotNull("an alarm-strength test alert is an alarm clock", alarm.alarmClockInfo)

        // A failed call queued ahead of it fails the answer that waits behind the drain.
        AlarmCalls.run { throw IllegalStateException() }
        val failed = testAlarmOnChannel()
        assertEquals("the channel replied before the queue ran", 0, failed.replies)
        runQueue()
        assertEquals(1, failed.replies)
        assertEquals("engine_error", failed.errorCode)
        assertNull(failed.value)
    }

    @Test
    fun `a snooze from the alarm screen is armed at once, a notification snooze waits`() {
        holdQueue()
        val scheduler = AlarmScheduler(context, store) { NOW }
        val actions = EngineActions(context, QuietPresenter(), store, scheduler) { NOW }
        val snoozedFor = NOW + 5 * MINUTE_MS

        // From the alarm screen the snooze alarm exists the moment snooze returns, and the queue keeps it.
        store.write(EngineState(presented = listOf(alert("a", NOW, start = NOW + 10 * MINUTE_MS))))
        actions.snooze(listOf("a"), SnoozeOption.PLUS_5_MIN, armNow = true)
        assertEquals("the snooze alarm was not armed at once", 1, alarmsFor("a:s").size)
        runQueue()
        assertEquals("the queue lost or doubled the snooze alarm", snoozedFor, alarmsFor("a:s").single().triggerAtMs)

        // From a notification the arm waits behind the queue.
        store.write(EngineState(presented = listOf(alert("b", NOW, start = NOW + 10 * MINUTE_MS))))
        actions.snooze(listOf("b"), SnoozeOption.PLUS_5_MIN, armNow = false)
        assertTrue("the snooze alarm was armed before the queue ran", alarmsFor("b:s").isEmpty())
        runQueue()
        assertEquals(snoozedFor, alarmsFor("b:s").single().triggerAtMs)

        // A cancel queued ahead of the snooze, for the id the snooze reuses, must not leave it unarmed: the
        // alarm armed at once is cancelled when the queue reaches that cancel, so the queue arms it again.
        val ringing = alert("c:s", NOW, start = NOW + 10 * MINUTE_MS) // a snooze that came due; snoozing it keeps its id
        assertEquals("c:s", EngineReducer.snoozeIdFor(ringing.id))
        store.write(EngineState(presented = listOf(ringing)))
        scheduler.cancel("c:s")
        actions.snooze(listOf("c:s"), SnoozeOption.PLUS_5_MIN, armNow = true)
        assertEquals("the snooze alarm was not armed at once", 1, alarmsFor("c:s").size)
        runQueue()
        assertEquals("the cancel queued earlier left the snooze unarmed", 1, alarmsFor("c:s").size)
        assertEquals(snoozedFor, alarmsFor("c:s").single().triggerAtMs)
    }

    @Test
    fun `rearmAll posts the nearest alarms first`() {
        holdQueue()
        // EngineState.scheduled lists the plan before the snoozes, so a list that is not sorted starts with f1.
        store.write(
            EngineState(
                plan = listOf(alert("f1", NOW + 2 * HOUR)),
                snoozes = listOf(alert("s:s", NOW + 5 * MINUTE_MS)),
            ),
        )

        AlarmScheduler(context, store) { NOW }.rearmAll()

        assertTrue("rearmAll queued fewer than two calls, so there is no order to check", queued.size >= 2)
        assertTrue("an alarm was armed before the queue ran", scheduledIds().isEmpty())
        queued.removeFirst().run()
        assertEquals("the first call queued is not the nearest alarm", setOf("s:s"), scheduledIds())
        runQueue()
        assertEquals(setOf("f1", "s:s"), scheduledIds())
    }

    @Test
    fun `a failed alarm call fails the test that made it`() {
        // No queue is held here: the executor and hook are the ones TestTMinusApplication installed.
        assertThrows(IllegalStateException::class.java) { AlarmCalls.run { throw IllegalStateException() } }
    }
}
