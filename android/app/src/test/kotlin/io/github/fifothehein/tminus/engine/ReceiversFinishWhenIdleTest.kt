package io.github.fifothehein.tminus.engine

import android.app.Application
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Looper
import androidx.work.Configuration
import androidx.work.ListenableWorker
import androidx.work.WorkerFactory
import androidx.work.WorkerParameters
import androidx.work.testing.SynchronousExecutor
import androidx.work.testing.WorkManagerTestInitHelper
import io.github.fifothehein.tminus.sync.PreSyncReceiver
import io.github.fifothehein.tminus.sync.PreSyncScheduler
import io.github.fifothehein.tminus.sync.SyncBootReceiver
import io.github.fifothehein.tminus.sync.SyncWorker
import org.junit.After
import org.junit.Assert.assertFalse
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
 * A receiver that causes alarm calls has to keep its broadcast open until they ran. Once the broadcast
 * is finished Android may freeze or kill the process, with the calls still queued on AlarmCalls' thread.
 *
 * Each test delivers a real broadcast, so the receiver gets the PendingResult the system would give
 * it (onReceive called directly gets none: goAsync() returns null), and runs the AlarmCalls queue by
 * hand. Each receiver is given work that makes an alarm call, so the queue holds that call and, behind
 * it, the idle-finish. The broadcast must stay open while anything is queued, and finish once the last
 * item ran.
 */
@RunWith(RobolectricTestRunner::class)
class ReceiversFinishWhenIdleTest {
    private val app: Application = RuntimeEnvironment.getApplication()
    private val now = System.currentTimeMillis() // the receivers use the real clock
    private lateinit var store: PlanStore
    private var workManagerStarted = false

    /** What AlarmCalls was handed and has not run yet. */
    private val queued = ArrayDeque<Runnable>()

    @Before
    fun setUp() {
        ShadowAlarmManager.setCanScheduleExactAlarms(true)
        // Robolectric registers every receiver of the manifest. Leave only the one under test, so that no
        // other receiver of the same action runs, or starts work of its own.
        shadowOf(app).clearRegisteredReceivers()
        store = PlanStore(app).also { it.clear() }
        EventQueue(app).drain()
        RingingSession.clear()
        AlarmCalls.executor = Executor { queued.add(it) }
        AlarmCalls.failureHook = { throw it } // after the executor: assigning it resets the hook
    }

    @After
    fun tearDown() {
        AlarmCalls.executor = Executor { it.run() }
        AlarmCalls.failureHook = { throw it }
        RingingSession.clear() // process-wide: the alarm AlarmReceiver rang must not reach another class
        if (workManagerStarted) WorkManagerTestInitHelper.closeWorkDatabase()
    }

    /**
     * The sync receivers queue a sync. This WorkManager keeps the request and never runs it: a real
     * SyncWorker would start a headless Flutter engine.
     */
    private fun startWorkManager() {
        val neverFinishes = object : WorkerFactory() {
            override fun createWorker(appContext: Context, workerClassName: String, workerParameters: WorkerParameters): ListenableWorker? =
                if (workerClassName == SyncWorker::class.java.name) SyncWorker(appContext, workerParameters) { _, _ -> {} } else null
        }
        WorkManagerTestInitHelper.initializeTestWorkManager(
            app,
            Configuration.Builder().setExecutor(SynchronousExecutor()).setWorkerFactory(neverFinishes).build(),
        )
        workManagerStarted = true
        app.getSharedPreferences(PreSyncScheduler.PREFS, Context.MODE_PRIVATE).edit().clear().commit()
    }

    private fun runQueue() {
        while (queued.isNotEmpty()) queued.removeFirst().run()
    }

    /**
     * Delivers [intent] to [receiver] as a broadcast and lets the main thread run it, which is what the
     * system does. The receiver is the only one registered for it.
     */
    private fun deliver(receiver: BroadcastReceiver, intent: Intent) {
        assertTrue("the set-up left alarm calls queued", queued.isEmpty())
        val filter = IntentFilter().apply { intent.action?.let(::addAction) }
        app.registerReceiver(receiver, filter, Context.RECEIVER_EXPORTED)
        app.sendBroadcast(intent)
        shadowOf(Looper.getMainLooper()).idle()
    }

    /**
     * [receiver] has been delivered a broadcast and made an alarm call. It must hold the broadcast open
     * while anything is queued on AlarmCalls, and finish it once the last item ran.
     */
    private fun assertFinishesOnlyAfterTheAlarmCallsRan(receiver: BroadcastReceiver) {
        val shadow = shadowOf(receiver)
        assertTrue("the receiver never went async, so the system finishes the broadcast at once", shadow.wentAsync())
        val finished = shadowOf(shadow.originalPendingResult).future
        assertTrue("nothing was queued on AlarmCalls, so the receiver is not waiting for it", queued.isNotEmpty())
        // The receiver's alarm call, and behind it the idle-finish. One item is the idle-finish alone.
        assertTrue("only one item was queued on AlarmCalls, not an alarm call and the idle-finish behind it", queued.size > 1)

        while (queued.isNotEmpty()) {
            assertFalse("the broadcast finished with ${queued.size} items still queued on AlarmCalls", finished.isDone)
            queued.removeFirst().run()
        }
        shadowOf(Looper.getMainLooper()).idle()

        assertTrue("the broadcast never finished after the alarm calls ran", finished.isDone)
    }

    @Test
    fun `TimeChangeReceiver finishes only after the alarm calls ran`() {
        store.write(EngineState(plan = listOf(alert("f", now + HOUR))))
        val receiver = TimeChangeReceiver()

        deliver(receiver, Intent(TimeChangeReceiver.ACTIONS.first()))

        assertFinishesOnlyAfterTheAlarmCallsRan(receiver)
    }

    @Test
    fun `BootReceiver finishes only after the alarm calls ran`() {
        store.write(EngineState(plan = listOf(alert("f", now + HOUR))))
        val receiver = BootReceiver()

        deliver(receiver, Intent(Intent.ACTION_BOOT_COMPLETED))

        assertFinishesOnlyAfterTheAlarmCallsRan(receiver)
    }

    @Test
    fun `AlarmReceiver finishes only after the alarm calls ran`() {
        // Firing an alert collects the siblings of its coalesce group that are due too, and cancels their
        // alarms: that is the receiver's alarm call. Both alarms are armed while both are still ahead (the
        // scheduler's clock is a minute behind). The first one then arrives late, with the second due as well.
        val first = alert("first", now - 40_000, group = "G")
        val second = alert("second", now - 20_000, group = "G")
        AlarmScheduler(app, store) { now - MINUTE_MS }.applyPlan(listOf(first, second))
        runQueue() // the alarm calls of the set-up, not of the receiver
        val receiver = AlarmReceiver()

        deliver(receiver, AlarmReceiver.fireIntent(app, "first"))

        assertFinishesOnlyAfterTheAlarmCallsRan(receiver)
    }

    @Test
    fun `NotificationActionReceiver finishes only after the alarm calls ran`() {
        val heads = alert("h", now - MINUTE_MS, strength = Strength.HEADS_UP, start = now + 10 * MINUTE_MS)
        store.write(EngineState(presented = listOf(heads)))
        val receiver = NotificationActionReceiver()
        val snooze = NotificationActionReceiver.intent(
            app,
            NotificationActionReceiver.ACTION_SNOOZE,
            arrayListOf(heads.id),
            NotificationFactory.headsUpId(heads.coalesceGroup),
        )

        deliver(receiver, snooze)

        assertFinishesOnlyAfterTheAlarmCallsRan(receiver)
    }

    @Test
    fun `PreSyncReceiver finishes only after the alarm calls ran`() {
        startWorkManager()
        PreSyncScheduler(app).setTimes(listOf(now + HOUR))
        runQueue() // the alarm calls of the set-up, not of the receiver
        val receiver = PreSyncReceiver()

        deliver(receiver, Intent(PreSyncScheduler.ACTION))

        assertFinishesOnlyAfterTheAlarmCallsRan(receiver)
    }

    @Test
    fun `SyncBootReceiver finishes only after the alarm calls ran`() {
        startWorkManager()
        PreSyncScheduler(app).setTimes(listOf(now + HOUR))
        runQueue() // the alarm calls of the set-up, not of the receiver
        val receiver = SyncBootReceiver()

        deliver(receiver, Intent(SyncBootReceiver.ACTIONS.first()))

        assertFinishesOnlyAfterTheAlarmCallsRan(receiver)
    }
}
