package io.github.fifothehein.tminus.sync

import android.app.AlarmManager
import android.app.Application
import android.app.NotificationManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import androidx.work.Configuration
import androidx.work.ListenableWorker
import androidx.work.WorkManager
import androidx.work.WorkerFactory
import androidx.work.WorkerParameters
import androidx.work.testing.SynchronousExecutor
import androidx.work.testing.WorkManagerTestInitHelper
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.github.fifothehein.tminus.MainActivity
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
import java.util.TimeZone

@RunWith(RobolectricTestRunner::class)
class SyncChannelTest {
    private val app: Application = RuntimeEnvironment.getApplication()
    private val notifications: NotificationManager = app.getSystemService(NotificationManager::class.java)
    private var now = 1_791_270_000_000L
    private val lock = SyncLock { now }
    private val finished = mutableListOf<String>()
    private val started = mutableListOf<String>()
    private lateinit var channel: SyncChannel

    private class Recorded : MethodChannel.Result {
        var value: Any? = null
        var errorCode: String? = null
        var notImplemented = false
        override fun success(result: Any?) { value = result }
        override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) { this.errorCode = errorCode }
        override fun notImplemented() { notImplemented = true }
    }

    private fun call(method: String, args: Map<String, Any?>? = null): Recorded =
        Recorded().also { channel.onMethodCall(MethodCall(method, args), it) }

    @Before
    fun setUp() {
        ShadowAlarmManager.setCanScheduleExactAlarms(true)
        val factory = object : WorkerFactory() {
            override fun createWorker(context: Context, name: String, params: WorkerParameters): ListenableWorker? =
                if (name == SyncWorker::class.java.name) SyncWorker(context, params) { t, _ -> started += t; {} } else null
        }
        WorkManagerTestInitHelper.initializeTestWorkManager(
            app,
            Configuration.Builder().setExecutor(SynchronousExecutor()).setWorkerFactory(factory).build(),
        )
        app.getSharedPreferences(PreSyncScheduler.PREFS, Context.MODE_PRIVATE).edit().clear().commit()
        channel = SyncChannel(app, { finished += it }, lock, SyncScheduler(app), PreSyncScheduler(app) { now })
    }

    /** Each test gets a new in-memory WorkManager database; close it so none leaks. */
    @After
    fun tearDown() {
        WorkManagerTestInitHelper.closeWorkDatabase()
    }

    @Test
    fun `deviceZone is the default zone's IANA id`() {
        assertEquals(TimeZone.getDefault().id, call("deviceZone").value)
    }

    @Test
    fun `the lock admits one owner until it is released or its lease runs out`() {
        assertEquals(true, call("acquireLock", mapOf("owner" to "a", "leaseMs" to 60_000)).value)
        assertEquals(false, call("acquireLock", mapOf("owner" to "b", "leaseMs" to 60_000)).value)
        assertEquals(true, call("acquireLock", mapOf("owner" to "a", "leaseMs" to 60_000)).value) // renew
        call("releaseLock", mapOf("owner" to "b")) // not the owner: no effect
        assertFalse(lock.acquire("b", 60_000))
        call("releaseLock", mapOf("owner" to "a"))
        assertTrue(lock.acquire("b", 60_000))
        now += 60_000
        assertTrue(lock.acquire("c", 60_000)) // b's lease ran out
    }

    @Test
    fun `detach releases the locks this engine took`() {
        call("acquireLock", mapOf("owner" to "a", "leaseMs" to 600_000))
        channel.detach()
        assertTrue(lock.acquire("b", 1_000))
    }

    @Test
    fun `configure schedules the periodic sync, the calendar watch and the pre-sync alarm`() {
        call("configure", mapOf("watchCalendars" to true, "preSyncTimesMs" to listOf(now + 60_000, now + 120_000L)))
        val wm = WorkManager.getInstance(app)
        assertEquals(1, wm.getWorkInfosForUniqueWork(SyncScheduler.PERIODIC).get().size)
        assertFalse(wm.getWorkInfosForUniqueWork(SyncScheduler.CALENDAR_WATCH).get().single().state.isFinished)
        val alarm = shadowOf(app.getSystemService(AlarmManager::class.java)).scheduledAlarms.single()
        assertEquals(now + 60_000, alarm.triggerAtTime)

        call("configure", mapOf("watchCalendars" to false, "preSyncTimesMs" to emptyList<Long>()))
        assertTrue(wm.getWorkInfosForUniqueWork(SyncScheduler.CALENDAR_WATCH).get().single().state.isFinished)
        assertTrue(shadowOf(app.getSystemService(AlarmManager::class.java)).scheduledAlarms.isEmpty())
    }

    @Test
    fun `a stale notice offers Sync now and a broken one offers Fix that opens the source`() {
        call("postSourceNotice", mapOf("kind" to "stale", "sourceId" to "work", "title" to "Calendar hasn't synced for 2 h — alarms may be outdated", "text" to "Work Outlook"))
        call("postSourceNotice", mapOf("kind" to "broken", "sourceId" to "home", "title" to "Home feed link stopped working", "text" to "Link no longer works (HTTP 404)."))

        val stale = shadowOf(notifications).getNotification(SyncNotifications.id("stale", "work"))
        assertEquals("Sync now", stale.actions.single().title)
        assertEquals(SyncNotifications.CHANNEL_STATUS, stale.channelId)
        assertTrue(stale.flags and android.app.Notification.FLAG_ONLY_ALERT_ONCE != 0)
        val sync = shadowOf(stale.actions.single().actionIntent).savedIntent
        SyncActionReceiver().onReceive(app, sync)
        assertEquals(listOf(SyncWorker.TRIGGER_MANUAL), started)

        val broken = shadowOf(notifications).getNotification(SyncNotifications.id("broken", "home"))
        assertEquals("Fix", broken.actions.single().title)
        val fix = shadowOf(broken.actions.single().actionIntent).savedIntent
        assertEquals(MainActivity::class.java.name, fix.component!!.className)
        assertEquals("/sources/home", fix.getStringExtra(SyncNotifications.EXTRA_ROUTE))
    }

    @Test
    fun `cancelling the last notice also removes the group summary`() {
        call("postSourceNotice", mapOf("kind" to "stale", "sourceId" to "work", "title" to "t", "text" to "x"))
        call("postSourceNotice", mapOf("kind" to "broken", "sourceId" to "work", "title" to "t", "text" to "x"))
        call("cancelSourceNotice", mapOf("kind" to "stale", "sourceId" to "work"))
        assertNull(shadowOf(notifications).getNotification(SyncNotifications.id("stale", "work")))
        assertEquals(2, notifications.activeNotifications.size) // broken + summary
        call("cancelSourceNotice", mapOf("kind" to "broken", "sourceId" to "work"))
        assertEquals(0, notifications.activeNotifications.size)
    }

    @Test
    fun `requestSync queues a background sync through WorkManager`() {
        call("requestSync", mapOf("trigger" to "manual"))
        assertEquals(listOf("manual"), started)
    }

    @Test
    fun `finished hands the outcome to the runner`() {
        call("finished", mapOf("outcome" to "retry"))
        assertEquals(listOf("retry"), finished)
    }

    @Test
    fun `bad arguments and unknown methods are reported`() {
        assertEquals("bad_args", call("acquireLock", mapOf("owner" to "a")).errorCode)
        assertEquals("bad_args", call("postSourceNotice", mapOf("kind" to "other", "sourceId" to "w", "title" to "t", "text" to "x")).errorCode)
        assertEquals("bad_args", call("configure", mapOf("watchCalendars" to true)).errorCode)
        assertTrue(call("nope").notImplemented)
    }

    @Test
    fun `arguments of the wrong type are bad_args, not a sync error`() {
        assertEquals("bad_args", call("acquireLock", mapOf("owner" to 5, "leaseMs" to 60_000)).errorCode)
        assertEquals("bad_args", call("acquireLock", mapOf("owner" to "a", "leaseMs" to "soon")).errorCode)
        assertEquals("bad_args", call("requestSync", mapOf("trigger" to true)).errorCode)
        assertTrue(started.isEmpty())
        assertTrue(lock.acquire("b", 1_000)) // none of the calls took the lock
    }

    @Test
    fun `a bad configure call is bad_args and changes nothing`() {
        val bad = listOf(
            mapOf("watchCalendars" to true), // preSyncTimesMs missing
            mapOf("preSyncTimesMs" to listOf(now + 60_000)), // watchCalendars missing
            mapOf("watchCalendars" to true, "preSyncTimesMs" to listOf(now + 60_000, "soon")), // an element is not a number
            mapOf("watchCalendars" to true, "preSyncTimesMs" to "soon"), // not a list
            mapOf("watchCalendars" to "yes", "preSyncTimesMs" to listOf(now + 60_000)), // not a bool
        )
        for (args in bad) assertEquals(args.toString(), "bad_args", call("configure", args).errorCode)

        val wm = WorkManager.getInstance(app)
        assertTrue(wm.getWorkInfosForUniqueWork(SyncScheduler.PERIODIC).get().isEmpty())
        assertTrue(wm.getWorkInfosForUniqueWork(SyncScheduler.CALENDAR_WATCH).get().isEmpty())
        assertTrue(shadowOf(app.getSystemService(AlarmManager::class.java)).scheduledAlarms.isEmpty())
        assertTrue(PreSyncScheduler(app) { now }.times().isEmpty())
    }

    @Test
    fun `Sync now ignores other actions and is not exported`() {
        SyncActionReceiver().onReceive(app, Intent("other"))
        assertTrue(started.isEmpty())
        assertFalse(app.packageManager.getReceiverInfo(ComponentName(app, SyncActionReceiver::class.java), 0).exported)
    }
}
