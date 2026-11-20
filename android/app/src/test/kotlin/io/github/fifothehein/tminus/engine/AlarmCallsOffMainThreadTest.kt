package io.github.fifothehein.tminus.engine

import android.app.AlarmManager
import android.app.Application
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import androidx.work.Configuration
import androidx.work.ListenableWorker
import androidx.work.WorkerFactory
import androidx.work.WorkerParameters
import androidx.work.testing.SynchronousExecutor
import androidx.work.testing.WorkManagerTestInitHelper
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.github.fifothehein.tminus.sync.PreSyncScheduler
import io.github.fifothehein.tminus.sync.SyncChannel
import io.github.fifothehein.tminus.sync.SyncLock
import io.github.fifothehein.tminus.sync.SyncScheduler
import io.github.fifothehein.tminus.sync.SyncWorker
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.shadows.ShadowAlarmManager
import java.util.concurrent.Executor

/**
 * Every AlarmManager call and PendingIntent lookup the engine and the pre-sync scheduler make runs on the
 * AlarmCalls queue, never on the thread that asked for it, and an answer that depends on those calls waits
 * for the queue to drain. Each test holds the queue in its own hands: nothing runs until [runQueue], so
 * "nothing is armed yet" and "nothing has been answered yet" can be asserted. A call that ran inline, or an
 * answer that came before the drain, fails the assertion made before [runQueue].
 */
@RunWith(RobolectricTestRunner::class)
class AlarmCallsOffMainThreadTest {
    private val app: Application = RuntimeEnvironment.getApplication()
    private val context: Context = app
    private val alarmManager: AlarmManager = app.getSystemService(AlarmManager::class.java)
    private val queued = ArrayDeque<Runnable>()
    private lateinit var store: PlanStore
    private var workManagerStarted = false

    @Before
    fun setUp() {
        ShadowAlarmManager.setCanScheduleExactAlarms(true)
        AlarmCalls.executor = Executor { queued.add(it) }
        store = PlanStore(app).also { it.clear() }
        EventQueue(app).drain()
        RingingSession.clear()
    }

    @After
    fun tearDown() {
        AlarmCalls.executor = Executor { it.run() }
        if (workManagerStarted) WorkManagerTestInitHelper.closeWorkDatabase()
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

    private fun alarmsFor(alertId: String) = shadowOf(alarmManager).scheduledAlarms
        .filter { shadowOf(it.operation).savedIntent.getStringExtra(AlarmReceiver.EXTRA_ALERT_ID) == alertId }

    private fun preSyncAlarms() = shadowOf(alarmManager).scheduledAlarms
        .filter { shadowOf(it.operation).savedIntent.action == PreSyncScheduler.ACTION }

    /** Takes every alarm and its PendingIntent away, as a reboot does, without going through the code under test. */
    private fun clearAlarms() {
        shadowOf(alarmManager).scheduledAlarms.toList().mapNotNull { it.operation }.forEach { operation ->
            alarmManager.cancel(operation)
            operation.cancel()
        }
    }

    /** An answer to a channel call. [replies] tells "no answer yet" apart from a success with no value. */
    private class Recorded : MethodChannel.Result {
        var replies = 0
        var value: Any? = null
        var errorCode: String? = null
        var errorMessage: String? = null
        override fun success(result: Any?) {
            replies++
            value = result
        }
        override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
            replies++
            this.errorCode = errorCode
            this.errorMessage = errorMessage
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

    /** An alert as the Dart side sends it over the channel. */
    private fun dartAlert(id: String, fireAt: Long): Map<String, Any?> = mapOf(
        "id" to id,
        "occurrenceKey" to "src|$id|occ",
        "fireAtUtcMs" to fireAt,
        "offsetMinutes" to 1,
        "strength" to "alarm",
        "sound" to mapOf("toneUri" to null, "vibrate" to true, "gradualVolume" to true, "ringTimeoutSec" to 120),
        "event" to mapOf(
            "title" to "Meeting $id",
            "startUtcMs" to fireAt + MINUTE_MS,
            "endUtcMs" to fireAt + HOUR,
            "location" to null,
            "joinUrl" to null,
            "color" to 4285178101L,
        ),
        "coalesceGroup" to CoalesceGroups.groupFor(fireAt),
    )

    private val engineChannel: AlarmEngineChannel by lazy {
        AlarmEngineChannel(app, store, AlarmScheduler(app, store) { NOW }) { NOW }
    }

    /** Calls the alarm_engine channel's applyPlan with an alert for each of [fireAts] (id to fire time). */
    private fun applyPlanOnChannel(vararg fireAts: Pair<String, Long>): Recorded {
        val plan = mapOf("version" to 1, "alerts" to fireAts.map { (id, fireAt) -> dartAlert(id, fireAt) })
        return Recorded().also { engineChannel.onMethodCall(MethodCall("applyPlan", plan), it) }
    }

    private fun assertRearmWaitsForTheQueue(receiver: BroadcastReceiver, action: String) {
        clearAlarms()
        val now = System.currentTimeMillis() // the receivers use the real clock
        store.write(
            EngineState(
                plan = listOf(alert("f1", now + HOUR), alert("f2", now + 2 * HOUR)),
                snoozes = listOf(alert("s:s", now + 5 * MINUTE_MS)),
            ),
        )

        receiver.onReceive(context, Intent(action))

        assertTrue("$action armed an alarm before the queue ran", shadowOf(alarmManager).scheduledAlarms.isEmpty())
        runQueue()
        assertEquals(action, setOf("f1", "f2", "s:s"), scheduledIds())
    }

    @Test
    fun `rearm receivers make no alarm call until the queue runs`() {
        BootReceiver.ACTIONS.forEach { assertRearmWaitsForTheQueue(BootReceiver(), it) }
        TimeChangeReceiver.ACTIONS.forEach { assertRearmWaitsForTheQueue(TimeChangeReceiver(), it) }
    }

    @Test
    fun `applyPlan arms and reports only when the queue runs`() {
        val actions = EngineActions(context, QuietPresenter(), store, AlarmScheduler(context, store) { NOW }) { NOW }
        val alarm = alert("a", NOW + 10 * MINUTE_MS)
        val headsUp = alert("h", NOW + 5 * MINUTE_MS, strength = Strength.HEADS_UP)
        val answers = mutableListOf<Result<ApplyResult>>()

        actions.applyPlan(listOf(alarm, headsUp)) { answers += it }

        assertTrue("an alarm was armed before the queue ran", scheduledIds().isEmpty())
        assertTrue("applyPlan answered before the queue ran", answers.isEmpty())

        runQueue()

        assertEquals(setOf("a", "h"), scheduledIds())
        assertEquals(ApplyResult(armed = 2, cancelled = 0, kept = 0), answers.single().getOrThrow())
    }

    @Test
    fun `applyPlan channel replies after the drain`() {
        val first = applyPlanOnChannel("a" to NOW + HOUR, "b" to NOW + 2 * HOUR, "c" to NOW + 3 * HOUR)
        assertEquals("the channel replied before the queue ran", 0, first.replies)
        runQueue()
        assertEquals(1, first.replies)
        assertNull(first.errorCode)
        assertEquals(mapOf("armed" to 3, "cancelled" to 0, "kept" to 0), first.value)
        assertEquals(setOf("a", "b", "c"), scheduledIds())

        // a stays, b and c are dropped, d, e and f are new: every count differs.
        val second = applyPlanOnChannel("a" to NOW + HOUR, "d" to NOW + 4 * HOUR, "e" to NOW + 5 * HOUR, "f" to NOW + 6 * HOUR)
        assertEquals("the channel replied before the queue ran", 0, second.replies)
        assertEquals("the plan changed the alarms before the queue ran", setOf("a", "b", "c"), scheduledIds())
        runQueue()
        assertEquals(1, second.replies)
        assertNull(second.errorCode)
        assertEquals(mapOf("armed" to 3, "cancelled" to 2, "kept" to 1), second.value)
        assertEquals(setOf("a", "d", "e", "f"), scheduledIds())
    }

    @Test
    fun `a failed alarm call fails that applyPlan only`() {
        // The queue keeps the first failure and hands it to the next marker, which clears it.
        val first = IllegalStateException("first")
        val reported = mutableListOf<Throwable?>()
        var laterCallRan = false
        AlarmCalls.run { throw first }
        AlarmCalls.run { throw IllegalArgumentException("second") }
        AlarmCalls.run { laterCallRan = true }
        AlarmCalls.whenIdle { reported += it }
        AlarmCalls.whenIdle { reported += it }
        runQueue()
        assertTrue("a failed call stopped the calls after it", laterCallRan)
        assertEquals(2, reported.size)
        assertNotNull("the failed call went unreported", reported[0])
        assertSame("the first failure is the one reported", first, reported[0])
        assertNull("a failure is reported once", reported[1])

        // On the channel the failure answers the applyPlan whose reply waits behind it, and no later one.
        AlarmCalls.run { throw IllegalStateException() }
        val failed = applyPlanOnChannel("a" to NOW + HOUR)
        assertEquals("the channel replied before the queue ran", 0, failed.replies)
        runQueue()
        assertEquals(1, failed.replies)
        assertEquals("engine_error", failed.errorCode)
        assertNull(failed.value)

        val next = applyPlanOnChannel("a" to NOW + HOUR, "b" to NOW + 2 * HOUR)
        assertEquals("the channel replied before the queue ran", 0, next.replies)
        runQueue()
        assertEquals(1, next.replies)
        assertNull("the earlier failure was reported again", next.errorCode)
        assertNotNull(next.value)
        assertEquals(setOf("a", "b"), scheduledIds())
    }

    @Test
    fun `alarm calls run in the order they were issued`() {
        val scheduler = AlarmScheduler(context, store) { NOW }
        val x = alert("x", NOW + 10 * MINUTE_MS)

        scheduler.cancel(x.id)
        scheduler.arm(x)
        assertTrue("armed before the queue ran", scheduledIds().isEmpty())
        runQueue()
        assertEquals("the cancel ran after the arm", setOf("x"), scheduledIds())

        scheduler.arm(x)
        scheduler.cancel(x.id)
        assertEquals("cancelled before the queue ran", setOf("x"), scheduledIds())
        runQueue()
        assertTrue("the arm ran after the cancel", scheduledIds().isEmpty())

        scheduler.arm(x)
        scheduler.cancel(x.id)
        assertTrue("armed before the queue ran", scheduledIds().isEmpty())
        runQueue()
        assertTrue("the arm ran after the cancel", scheduledIds().isEmpty())
    }

    private fun startWorkManager() {
        val factory = object : WorkerFactory() {
            override fun createWorker(context: Context, name: String, params: WorkerParameters): ListenableWorker? =
                if (name == SyncWorker::class.java.name) SyncWorker(context, params) { _, _ -> {} } else null
        }
        WorkManagerTestInitHelper.initializeTestWorkManager(
            app,
            Configuration.Builder().setExecutor(SynchronousExecutor()).setWorkerFactory(factory).build(),
        )
        workManagerStarted = true
        app.getSharedPreferences(PreSyncScheduler.PREFS, Context.MODE_PRIVATE).edit().clear().commit()
    }

    @Test
    fun `pre-sync alarm and configure reply wait for the queue`() {
        startWorkManager()
        PreSyncScheduler(app) { NOW }.setTimes(listOf(NOW + MINUTE_MS))
        assertTrue("the pre-sync alarm was armed before the queue ran", preSyncAlarms().isEmpty())
        runQueue()
        assertEquals(NOW + MINUTE_MS, preSyncAlarms().single().triggerAtMs)

        val channel = SyncChannel(app, { }, SyncLock { NOW }, SyncScheduler(app), PreSyncScheduler(app) { NOW })
        val reply = Recorded()
        val args = mapOf("watchCalendars" to false, "preSyncTimesMs" to listOf(NOW + 2 * MINUTE_MS))
        channel.onMethodCall(MethodCall("configure", args), reply)
        assertEquals("configure replied before the queue ran", 0, reply.replies)
        assertEquals("the pre-sync alarm moved before the queue ran", NOW + MINUTE_MS, preSyncAlarms().single().triggerAtMs)
        runQueue()
        assertEquals(1, reply.replies)
        assertNull(reply.errorCode)
        assertEquals(NOW + 2 * MINUTE_MS, preSyncAlarms().single().triggerAtMs)
    }

    @Test
    fun `after a boot an alert due inside the window is armed at the window end`() {
        val now = System.currentTimeMillis() // the receiver uses the real clock
        val soon = alert("soon", now + 10_000) // due before the boot window ends; its event runs on
        store.write(EngineState(plan = listOf(soon)))

        BootReceiver().onReceive(context, Intent(Intent.ACTION_BOOT_COMPLETED))

        assertTrue("an alarm was armed before the queue ran", shadowOf(alarmManager).scheduledAlarms.isEmpty())
        runQueue()

        val alarm = alarmsFor("soon").single()
        assertNotEquals("armed at its own time", soon.fireAtUtcMs, alarm.triggerAtMs)
        assertTrue(
            "armed ${alarm.triggerAtMs - now} ms after the boot",
            alarm.triggerAtMs in now + EngineActions.RECOVERY_DELAY_MS..System.currentTimeMillis() + 2 * EngineActions.RECOVERY_DELAY_MS,
        )
        assertEquals(listOf("soon"), store.read().plan.map { it.id }) // still scheduled, just later
    }
}
