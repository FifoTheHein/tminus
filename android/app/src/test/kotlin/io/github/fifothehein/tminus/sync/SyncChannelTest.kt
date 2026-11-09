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
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMethodCodec
import io.github.fifothehein.tminus.MainActivity
import io.github.fifothehein.tminus.quiet.QuietStore
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.shadows.ShadowAlarmManager
import java.io.File
import java.io.IOException
import java.nio.ByteBuffer
import java.nio.file.AccessDeniedException
import java.util.TimeZone
import java.util.concurrent.Callable
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference

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

    @Test
    fun `installId is stable and survives a new channel`() {
        val a = call("installId").value as String
        assertEquals(a, call("installId").value)
        assertEquals(a, InstallId(app).get())
    }

    @Test
    fun `takeQuietRequest returns the waiting request once`() {
        QuietStore(app) { now }.request(QuietStore.MUTE)
        assertEquals(mapOf("action" to "mute", "atMs" to now), call("takeQuietRequest").value)
        assertNull(call("takeQuietRequest").value)
    }

    @Test
    fun `configure stores the quiet mirror and treats missing quiet args as none`() {
        call("configure", mapOf("watchCalendars" to false, "preSyncTimesMs" to emptyList<Long>(),
            "quietUntilMs" to now + 60_000, "quietText" to "Until 07:00"))
        assertEquals(QuietStore.Display(true, "Until 07:00"), QuietStore(app) { now }.display())
        call("configure", mapOf("watchCalendars" to false, "preSyncTimesMs" to emptyList<Long>()))
        assertEquals(false, QuietStore(app) { now }.display().active)
    }

    @Test
    fun `an attached UI channel hears background syncs until it detaches`() {
        val sent = mutableListOf<MethodCall>()
        val messenger = RecordingMessenger(sent)
        val ui = SyncChannel.register(messenger, app)
        ui.attachUi()
        BackgroundSyncSignal.finished("periodic", "ok")
        assertEquals("syncFinished", sent.single().method)
        assertEquals(mapOf("trigger" to "periodic", "outcome" to "ok"), sent.single().arguments)
        ui.detach()
        BackgroundSyncSignal.finished("periodic", "ok")
        assertEquals(1, sent.size)
    }

    @Test
    fun `a bad quiet argument is bad_args and changes nothing`() {
        QuietStore(app) { now }.mirror(now + 60_000, "Until 07:00")
        val base = mapOf("watchCalendars" to true, "preSyncTimesMs" to listOf(now + 60_000))
        assertEquals("bad_args", call("configure", base + mapOf("quietUntilMs" to "soon")).errorCode)
        assertEquals("bad_args", call("configure", base + mapOf("quietText" to 7)).errorCode)

        val wm = WorkManager.getInstance(app)
        assertTrue(wm.getWorkInfosForUniqueWork(SyncScheduler.PERIODIC).get().isEmpty())
        assertTrue(shadowOf(app.getSystemService(AlarmManager::class.java)).scheduledAlarms.isEmpty())
        assertEquals(QuietStore.Display(true, "Until 07:00"), QuietStore(app) { now }.display()) // the mirror is untouched
    }

    @Test
    fun `an error reply carries no message`() {
        // A message can carry a link, a path or a row's values (Global Constraints).
        var message: String? = "not answered"
        val result = object : MethodChannel.Result {
            override fun success(result: Any?) = Unit
            override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) { message = errorMessage }
            override fun notImplemented() = Unit
        }
        channel.onMethodCall(MethodCall("acquireLock", mapOf("owner" to "a")), result) // leaseMs missing
        assertNull(message)
    }

    @Test
    fun `the install id lives in noBackupFilesDir`() {
        val id = InstallId(app).get()
        assertEquals(id, File(app.noBackupFilesDir, InstallId.FILE_NAME).readText())
        assertFalse(File(app.filesDir, InstallId.FILE_NAME).exists()) // filesDir is backed up
    }

    @Test
    fun `two InstallId instances agree while one is still writing`() {
        // The UI engine and a headless engine each make an InstallId in the one process.
        val slowIsMinting = CountDownLatch(1)
        val letSlowFinish = CountDownLatch(1)
        val slow = InstallId(app) {
            slowIsMinting.countDown()
            letSlowFinish.await(10, TimeUnit.SECONDS)
            "id-from-the-slow-instance"
        }
        val quick = InstallId(app) { "id-from-the-quick-instance" }
        val pool = Executors.newFixedThreadPool(2)
        try {
            val first = pool.submit(Callable { slow.get() })
            assertTrue(slowIsMinting.await(10, TimeUnit.SECONDS)) // the slow one is inside get() now
            val quickThread = AtomicReference<Thread>()
            val second = pool.submit(Callable { quickThread.set(Thread.currentThread()); quick.get() })
            // Wait until the quick one is either done (nothing held it back) or waiting for the slow one's lock.
            val deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(10)
            while (!second.isDone && quickThread.get()?.state != Thread.State.BLOCKED && System.nanoTime() < deadline) {
                Thread.sleep(5)
            }
            letSlowFinish.countDown()

            val a = first.get(10, TimeUnit.SECONDS)
            val b = second.get(10, TimeUnit.SECONDS)
            assertEquals(a, b)
            assertEquals(a, File(app.noBackupFilesDir, InstallId.FILE_NAME).readText())
        } finally {
            letSlowFinish.countDown()
            pool.shutdownNow()
        }
    }

    @Test
    fun `an install id file that cannot be read is an error and is kept`() {
        // The file is there and holds this phone's id, but reading it fails (a permission or I/O error).
        val path = File(app.noBackupFilesDir, InstallId.FILE_NAME)
        path.writeText("the-id-of-this-phone")

        val unreadable = InstallId(app, readBytes = { throw IOException("unreadable") })
        assertThrows(IOException::class.java) { unreadable.get() }
        assertEquals("the-id-of-this-phone", path.readText())
    }

    @Test
    fun `an install id file that access is denied to is an error and is kept`() {
        // Denied is not missing. Both are java.nio.file.FileSystemExceptions, but only a missing file may
        // start a new id: replacing a file that is there but off limits would make this phone look restored.
        // This is java.nio's AccessDeniedException, not Kotlin's kotlin.io one, which is not a
        // java.nio.file.FileSystemException and so would not tell the two apart.
        val path = File(app.noBackupFilesDir, InstallId.FILE_NAME)
        path.writeText("the-id-of-this-phone")

        val denied = InstallId(app, readBytes = { throw AccessDeniedException(it.path) })
        assertThrows(AccessDeniedException::class.java) { denied.get() }
        assertEquals("the-id-of-this-phone", path.readText())
    }

    @Test
    fun `a directory where the install id file belongs is a sync error on the channel and is kept`() {
        val path = File(app.noBackupFilesDir, InstallId.FILE_NAME)
        assertTrue(path.mkdir())

        assertThrows(IOException::class.java) { InstallId(app).get() }
        // On the channel it is a sync error, which Dart's restore guard logs before starting normally.
        val reply = call("installId")
        assertEquals("sync_error", reply.errorCode)
        assertNull(reply.value)
        assertTrue(path.isDirectory)
    }

    @Test
    fun `an install id file with no id in it is an error and is kept`() {
        val path = File(app.noBackupFilesDir, InstallId.FILE_NAME)
        path.writeText("  \n")

        assertThrows(IOException::class.java) { InstallId(app).get() }
        assertEquals("sync_error", call("installId").errorCode)
        assertEquals("  \n", path.readText())
    }

    @Test
    fun `a new install id is written to a temporary file and renamed into place`() {
        // With a directory in the temporary file's place the write cannot start, and no id file appears.
        // Written straight to the real file it would have succeeded.
        val temp = File(app.noBackupFilesDir, InstallId.TEMP_NAME)
        assertTrue(temp.mkdir())
        assertThrows(IOException::class.java) { InstallId(app).get() }
        assertFalse(File(app.noBackupFilesDir, InstallId.FILE_NAME).exists())

        temp.delete()
        val id = InstallId(app).get()
        assertEquals(id, File(app.noBackupFilesDir, InstallId.FILE_NAME).readText())
        assertFalse(temp.exists()) // renamed, not copied
    }

    private fun setInstallTimes(first: Long, last: Long) {
        val info = shadowOf(app.packageManager).getInternalMutablePackageInfo(app.packageName)
        info.firstInstallTime = first
        info.lastUpdateTime = last
    }

    @Test
    fun `neverUpdated is true when the install time and the update time are the same`() {
        setInstallTimes(first = now, last = now)
        assertEquals(true, call("neverUpdated").value)
    }

    @Test
    fun `neverUpdated is false once the app was updated`() {
        setInstallTimes(first = now, last = now + 60_000)
        assertEquals(false, call("neverUpdated").value)
    }

    @Test
    fun `neverUpdated is false when the package cannot be read`() {
        shadowOf(app.packageManager).removePackage(app.packageName)
        assertEquals(false, call("neverUpdated").value)
    }
}

/** A messenger that records the method calls sent to Dart and ignores handlers. */
private class RecordingMessenger(private val sent: MutableList<MethodCall>) : BinaryMessenger {
    override fun send(channel: String, message: ByteBuffer?) = send(channel, message, null)

    override fun send(channel: String, message: ByteBuffer?, callback: BinaryMessenger.BinaryReply?) {
        // The encoded buffer's position is at its end.
        message!!.rewind()
        sent += StandardMethodCodec.INSTANCE.decodeMethodCall(message)
    }

    override fun setMessageHandler(channel: String, handler: BinaryMessenger.BinaryMessageHandler?) = Unit
}
