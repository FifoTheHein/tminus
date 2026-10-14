package io.github.fifothehein.tminus.sync

import android.app.AlarmManager
import android.app.Application
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.provider.CalendarContract
import androidx.work.Configuration
import androidx.work.ListenableWorker
import androidx.work.NetworkType
import androidx.work.WorkInfo
import androidx.work.WorkManager
import androidx.work.WorkerFactory
import androidx.work.WorkerParameters
import androidx.work.testing.SynchronousExecutor
import androidx.work.testing.TestListenableWorkerBuilder
import androidx.work.testing.WorkManagerTestInitHelper
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
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
class SyncSchedulingTest {
    private val app: Application = RuntimeEnvironment.getApplication()
    private val alarmManager: AlarmManager = app.getSystemService(AlarmManager::class.java)
    private lateinit var workManager: WorkManager
    private var now = 1_791_270_000_000L

    /** Queued SyncWorkers run at once in tests; this one records the trigger and never finishes. */
    private val started = mutableListOf<String>()
    private val factory = object : WorkerFactory() {
        override fun createWorker(context: Context, name: String, params: WorkerParameters): ListenableWorker? =
            if (name == SyncWorker::class.java.name) SyncWorker(context, params) { trigger, _ -> started += trigger; {} } else null
    }

    @Before
    fun setUp() {
        ShadowAlarmManager.setCanScheduleExactAlarms(true)
        WorkManagerTestInitHelper.initializeTestWorkManager(
            app,
            Configuration.Builder().setExecutor(SynchronousExecutor()).setWorkerFactory(factory).build(),
        )
        workManager = WorkManager.getInstance(app)
        app.getSharedPreferences(PreSyncScheduler.PREFS, Context.MODE_PRIVATE).edit().clear().commit()
    }

    private fun infos(name: String): List<WorkInfo> = workManager.getWorkInfosForUniqueWork(name).get()

    private fun preSyncAlarms() = shadowOf(alarmManager).scheduledAlarms
        .filter { shadowOf(it.operation).savedIntent.action == PreSyncScheduler.ACTION }

    /** Each test gets a new in-memory WorkManager database; close it so none leaks. */
    @After
    fun tearDown() {
        WorkManagerTestInitHelper.closeWorkDatabase()
    }

    @Test
    fun `periodic sync runs every 15 min with a network and is kept, not replaced`() {
        val scheduler = SyncScheduler(app, workManager)
        scheduler.ensurePeriodic()
        val first = infos(SyncScheduler.PERIODIC).single()
        scheduler.ensurePeriodic()
        val info = infos(SyncScheduler.PERIODIC).single()
        assertEquals(first.id, info.id)
        assertEquals(NetworkType.CONNECTED, info.constraints.requiredNetworkType)
        assertEquals(15 * 60_000L, info.periodicityInfo!!.repeatIntervalMillis)
    }

    @Test
    fun `runNow queues one sync per trigger with the trigger as input and no network condition`() {
        val scheduler = SyncScheduler(app, workManager)
        scheduler.runNow(SyncWorker.TRIGGER_PRE_ALARM, expedited = true)
        scheduler.runNow(SyncWorker.TRIGGER_PRE_ALARM, expedited = true)
        val info = infos(SyncScheduler.nowName(SyncWorker.TRIGGER_PRE_ALARM)).single()
        assertEquals(NetworkType.NOT_REQUIRED, info.constraints.requiredNetworkType)
        assertEquals(listOf(SyncWorker.TRIGGER_PRE_ALARM), started)
    }

    @Test
    fun `the calendar watch is a content trigger on Events and can be turned off`() {
        val scheduler = SyncScheduler(app, workManager)
        scheduler.setCalendarWatch(true)
        scheduler.setCalendarWatch(true)
        val info = infos(SyncScheduler.CALENDAR_WATCH).single()
        assertEquals(WorkInfo.State.ENQUEUED, info.state)
        val trigger = info.constraints.contentUriTriggers.single()
        assertEquals(CalendarContract.Events.CONTENT_URI, trigger.uri)
        assertTrue(trigger.isTriggeredForDescendants)
        scheduler.setCalendarWatch(false)
        assertEquals(WorkInfo.State.CANCELLED, infos(SyncScheduler.CALENDAR_WATCH).single().state)
    }

    @Test
    fun `a calendar change queues a sync and the next watch`() {
        val worker = TestListenableWorkerBuilder<CalendarWatchWorker>(app).build()
        assertEquals(ListenableWorker.Result.success(), worker.startWork().get())
        assertEquals(listOf(SyncWorker.TRIGGER_CALENDAR_CHANGE), started)
        assertEquals(WorkInfo.State.ENQUEUED, infos(SyncScheduler.CALENDAR_WATCH).single().state)
    }

    private fun worker(trigger: String?, runAttemptCount: Int = 0, runner: SyncRunner): SyncWorker {
        val builder = TestListenableWorkerBuilder<SyncWorker>(app).setRunAttemptCount(runAttemptCount).setWorkerFactory(
            object : WorkerFactory() {
                override fun createWorker(context: Context, name: String, params: WorkerParameters) =
                    SyncWorker(context, params, runner)
            },
        )
        if (trigger != null) builder.setInputData(SyncWorker.input(trigger))
        return builder.build() as SyncWorker
    }

    @Test
    fun `the worker runs its trigger and maps the outcome`() {
        val seen = mutableListOf<String>()
        val outcomes = mapOf(
            SyncWorker.OUTCOME_OK to ListenableWorker.Result.success(),
            SyncWorker.OUTCOME_BUSY to ListenableWorker.Result.success(),
            SyncWorker.OUTCOME_RETRY to ListenableWorker.Result.retry(),
        )
        for ((outcome, expected) in outcomes) {
            val w = worker(SyncWorker.TRIGGER_PERIODIC) { trigger, done -> seen += trigger; done(outcome); {} }
            assertEquals(outcome, expected, w.startWork().get())
        }
        assertEquals(List(3) { SyncWorker.TRIGGER_PERIODIC }, seen)
    }

    @Test
    fun `a request that keeps failing stops retrying after two attempts`() {
        // Decision 25: a third retry would leave the request waiting minutes to hours, and runNow's
        // KEEP / APPEND_OR_REPLACE would hold every later sync of its trigger behind it.
        val results = (0..3).map { attempt ->
            worker(SyncWorker.TRIGGER_PRE_ALARM, runAttemptCount = attempt) { _, done -> done(SyncWorker.OUTCOME_RETRY); {} }
                .startWork().get()
        }
        assertEquals(
            listOf(
                ListenableWorker.Result.retry(),
                ListenableWorker.Result.retry(),
                ListenableWorker.Result.success(),
                ListenableWorker.Result.success(),
            ),
            results,
        )
    }

    private fun resultOf(trigger: String, outcome: String, runAttemptCount: Int = 0) =
        worker(trigger, runAttemptCount) { _, done -> done(outcome); {} }.startWork().get()

    @Test
    fun `a busy quietTile run is retried, a busy run of any other trigger is done`() {
        assertEquals(
            ListenableWorker.Result.retry(),
            resultOf(SyncWorker.TRIGGER_QUIET_TILE, SyncWorker.OUTCOME_BUSY),
        )
        val others = listOf(
            SyncWorker.TRIGGER_PERIODIC,
            SyncWorker.TRIGGER_CALENDAR_CHANGE,
            SyncWorker.TRIGGER_PRE_ALARM,
            SyncWorker.TRIGGER_MANUAL,
            SyncWorker.TRIGGER_TIME_CHANGE,
        )
        for (trigger in others) {
            assertEquals(trigger, ListenableWorker.Result.success(), resultOf(trigger, SyncWorker.OUTCOME_BUSY))
        }
        // A finished tile run is done.
        assertEquals(
            ListenableWorker.Result.success(),
            resultOf(SyncWorker.TRIGGER_QUIET_TILE, SyncWorker.OUTCOME_OK),
        )
    }

    @Test
    fun `a quietTile run that is busy every time stops retrying after two attempts`() {
        // The tap stays in the store for the next sync of any trigger; a run that kept retrying would also
        // hold every later tap behind it (APPEND_OR_REPLACE).
        val results = (0..3).map { attempt ->
            resultOf(SyncWorker.TRIGGER_QUIET_TILE, SyncWorker.OUTCOME_BUSY, runAttemptCount = attempt)
        }
        assertEquals(
            listOf(
                ListenableWorker.Result.retry(),
                ListenableWorker.Result.retry(),
                ListenableWorker.Result.success(),
                ListenableWorker.Result.success(),
            ),
            results,
        )
    }

    @Test
    fun `a worker without a trigger runs as manual, and stopping it cancels the run`() {
        var cancelled = false
        var trigger: String? = null
        val w = worker(null) { t, _ -> trigger = t; { cancelled = true } }
        w.startWork()
        assertEquals(SyncWorker.TRIGGER_MANUAL, trigger)
        w.onStopped()
        assertTrue(cancelled)
    }

    @Test
    fun `pre-sync keeps one alarm for the next future time`() {
        val pre = PreSyncScheduler(app) { now }
        pre.setTimes(listOf(now + 3 * MINUTE, now - MINUTE, now + MINUTE, now + MINUTE))
        assertEquals(listOf(now - MINUTE, now + MINUTE, now + 3 * MINUTE), pre.times())
        assertEquals(now + MINUTE, preSyncAlarms().single().triggerAtTime)

        now += 2 * MINUTE
        pre.armNext()
        assertEquals(now + MINUTE, preSyncAlarms().single().triggerAtTime)

        now += 2 * MINUTE
        pre.armNext()
        assertNull(pre.next())
        assertTrue(preSyncAlarms().isEmpty())
    }

    @Test
    fun `without exact-alarm access the pre-sync alarm is inexact, not dropped`() {
        ShadowAlarmManager.setCanScheduleExactAlarms(false)
        PreSyncScheduler(app) { now }.setTimes(listOf(now + MINUTE))
        assertEquals(now + MINUTE, preSyncAlarms().single().triggerAtTime)
    }

    @Test
    fun `the pre-sync alarm starts an expedited sync and arms the next one`() {
        val real = System.currentTimeMillis()
        PreSyncScheduler(app).setTimes(listOf(real - 1_000, real + HOUR))
        PreSyncReceiver().onReceive(app, Intent(PreSyncScheduler.ACTION))
        assertEquals(listOf(SyncWorker.TRIGGER_PRE_ALARM), started)
        assertEquals(real + HOUR, preSyncAlarms().single().triggerAtTime)
    }

    @Test
    fun `boot, update and clock changes re-arm the pre-sync alarm, and clock changes sync`() {
        val real = System.currentTimeMillis()
        val pre = PreSyncScheduler(app)
        for (action in SyncBootReceiver.ACTIONS) {
            pre.setTimes(listOf(real + HOUR))
            shadowOf(alarmManager).scheduledAlarms.mapNotNull { it.operation }.forEach(alarmManager::cancel)
            SyncBootReceiver().onReceive(app, Intent(action))
            assertEquals(action, real + HOUR, preSyncAlarms().single().triggerAtTime)
        }
        SyncBootReceiver().onReceive(app, Intent(Intent.ACTION_SCREEN_ON))
        // TIME_SET and TIMEZONE_CHANGED each ask for a timeChange sync; the first never finishes in this
        // test, so KEEP drops the second.
        assertEquals(listOf(SyncWorker.TRIGGER_TIME_CHANGE), started)
    }

    @Test
    fun `the manifest registers the sync receivers`() {
        val pm = app.packageManager
        for (action in SyncBootReceiver.ACTIONS) {
            val found = pm.queryBroadcastReceivers(Intent(action).setPackage(app.packageName), 0).map { it.activityInfo.name }
            assertTrue(action, SyncBootReceiver::class.java.name in found)
        }
        assertFalse(pm.getReceiverInfo(ComponentName(app, PreSyncReceiver::class.java), 0).exported)
    }

    @Test
    fun `a second quietTile request queues behind a running one instead of being dropped`() {
        val scheduler = SyncScheduler(app)
        scheduler.runNow(SyncWorker.TRIGGER_QUIET_TILE, expedited = true)
        scheduler.runNow(SyncWorker.TRIGGER_QUIET_TILE, expedited = true)
        assertEquals(2, infos(SyncScheduler.nowName(SyncWorker.TRIGGER_QUIET_TILE)).size)
        assertEquals(listOf("quietTile"), started) // the second waits for the first, which never finishes here
    }

    private companion object {
        const val MINUTE = 60_000L
        const val HOUR = 60 * MINUTE
    }
}
