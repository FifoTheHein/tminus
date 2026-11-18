package io.github.fifothehein.tminus.quiet

import android.app.Application
import android.content.Context
import android.service.quicksettings.Tile
import androidx.work.Configuration
import androidx.work.ListenableWorker
import androidx.work.WorkManager
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
import org.junit.Assert.assertNull
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.shadows.ShadowAlarmManager

/**
 * Taps on the Mute today tile that come before the sync of the previous tap has finished (or has even
 * started). The tile and the next tap's action must follow the latest tap, not the state the last sync
 * left behind: after any mix of taps and syncs the tile shows what the latest tap asked for, and the next
 * tap asks for the opposite.
 *
 * The real tile service and the real `tminus_sync` channel run here. [FakeDart] stands in for the sync
 * in Dart: it takes the waiting request, applies it the way `SyncService` does and then calls `configure`
 * with the state it ended up in.
 */
@RunWith(RobolectricTestRunner::class)
class QuietTapSequenceTest {
    private val app: Application = RuntimeEnvironment.getApplication()

    /** Triggers of the sync runs WorkManager started; a run finishes at once when [runsFinish] is set. */
    private val started = mutableListOf<String>()
    private var runsFinish = false

    private lateinit var channel: SyncChannel
    private lateinit var service: QuietTileService
    private lateinit var tile: Tile
    private lateinit var dart: FakeDart

    private class Recorded : MethodChannel.Result {
        var value: Any? = null
        override fun success(result: Any?) { value = result }
        override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) = Unit
        override fun notImplemented() = Unit
    }

    private fun call(method: String, args: Map<String, Any?>? = null): Recorded =
        Recorded().also { channel.onMethodCall(MethodCall(method, args), it) }

    /**
     * The sync in Dart as far as the tile can tell. [take] is `_applyQuietRequest`: it takes the waiting
     * request and applies it unless the app changed the quiet mode after the tap. [configure] is the call at
     * the end of a run, which reports the quiet mode the run ended in.
     */
    private inner class FakeDart {
        var muted = false
        private var changedAtMs: Long? = null

        fun take(): String? {
            val reply = call("takeQuietRequest").value as Map<*, *>? ?: return null
            val action = reply["action"] as String
            val atMs = reply["atMs"] as Long
            val changed = changedAtMs
            if (changed == null || changed <= atMs) {
                muted = action == QuietStore.MUTE
                changedAtMs = atMs
            }
            return action
        }

        fun configure() {
            val until = if (muted) System.currentTimeMillis() + HOUR else null
            call(
                "configure",
                mapOf(
                    "watchCalendars" to false,
                    "preSyncTimesMs" to emptyList<Long>(),
                    "quietUntilMs" to until,
                    "quietText" to if (muted) UNTIL_TEXT else null,
                ),
            )
        }
    }

    @Before
    fun setUp() {
        ShadowAlarmManager.setCanScheduleExactAlarms(true)
        // As in QuietTileServiceTest: a SyncWorker whose runner records the trigger and never boots Flutter.
        val factory = object : WorkerFactory() {
            override fun createWorker(appContext: Context, workerClassName: String, workerParameters: WorkerParameters): ListenableWorker? =
                if (workerClassName == SyncWorker::class.java.name) {
                    SyncWorker(appContext, workerParameters) { trigger, done ->
                        started += trigger
                        if (runsFinish) done(SyncWorker.OUTCOME_OK)
                        NOTHING_TO_CANCEL
                    }
                } else {
                    null
                }
        }
        WorkManagerTestInitHelper.initializeTestWorkManager(
            app,
            Configuration.Builder().setExecutor(SynchronousExecutor()).setWorkerFactory(factory).build(),
        )
        app.getSharedPreferences(QuietStore.PREFS, Context.MODE_PRIVATE).edit().clear().commit()
        channel = SyncChannel(app, null, SyncLock(), SyncScheduler(app), PreSyncScheduler(app))
        dart = FakeDart()
        service = Robolectric.setupService(QuietTileService::class.java)
        service.onStartListening()
        tile = service.qsTile
    }

    @After
    fun tearDown() = WorkManagerTestInitHelper.closeWorkDatabase()

    private fun stateOf(action: String) = if (action == QuietStore.MUTE) Tile.STATE_ACTIVE else Tile.STATE_INACTIVE

    @Test
    fun `two taps with no sync in between show muting first and ask to end the second time`() {
        service.onClick()
        assertEquals(Tile.STATE_ACTIVE, tile.state)
        assertEquals(QuietStore.MUTING, tile.subtitle)

        service.onClick()
        assertEquals(Tile.STATE_INACTIVE, tile.state)
        assertNull(tile.subtitle)
        // No sync has run, so the one request left waiting is the latest, and it ends the mute.
        assertEquals(QuietStore.END, QuietStore(app).take()?.action)
    }

    @Test
    fun `a tap on a tile that is not listening still draws the state it asked for`() {
        // A click while quick settings is closed binds the tile without starting to listen, so nothing redraws
        // it when the store changes: the tap must draw it itself.
        service.onStopListening()
        val idle = Robolectric.setupService(QuietTileService::class.java)
        val idleTile = idle.qsTile

        idle.onClick()
        assertEquals(Tile.STATE_ACTIVE, idleTile.state)
        assertEquals(QuietStore.MUTING, idleTile.subtitle)

        idle.onClick()
        assertEquals(Tile.STATE_INACTIVE, idleTile.state)
        assertNull(idleTile.subtitle)
    }

    @Test
    fun `three taps with no sync in between ask to mute, end and mute`() {
        service.onClick()
        assertEquals(Tile.STATE_ACTIVE, tile.state)
        service.onClick()
        assertEquals(Tile.STATE_INACTIVE, tile.state)
        service.onClick()
        assertEquals(Tile.STATE_ACTIVE, tile.state)
        assertEquals(QuietStore.MUTING, tile.subtitle)

        assertEquals(QuietStore.MUTE, QuietStore(app).take()?.action)
        // Every tap queued a run behind the one before it, so the latest tap is applied by a run that starts after it.
        val runs = WorkManager.getInstance(app).getWorkInfosForUniqueWork(SyncScheduler.nowName(SyncWorker.TRIGGER_QUIET_TILE)).get()
        assertEquals(3, runs.size)
        assertEquals(listOf(SyncWorker.TRIGGER_QUIET_TILE), started) // the others wait for the first, which never finishes here
    }

    @Test
    fun `a tap while the sync of the previous tap is applying it asks to end, and the sync finishing does not undo that`() {
        service.onClick() // mute
        assertEquals(QuietStore.MUTE, dart.take()) // the sync has taken it and Dart is applying it
        assertEquals(true, dart.muted)

        service.onClick() // the second tap comes before the sync has finished
        assertEquals(Tile.STATE_INACTIVE, tile.state)

        dart.configure() // the first sync finishes with the mute in place
        assertEquals(Tile.STATE_INACTIVE, tile.state) // the second tap is still waiting, so the tile still shows it
        assertNull(tile.subtitle)

        assertEquals(QuietStore.END, dart.take()) // the next sync applies it
        dart.configure()
        assertEquals(false, dart.muted)
        assertEquals(Tile.STATE_INACTIVE, tile.state)
        assertEquals(QuietStore.MUTE, QuietStore(app).actionForTap())
    }

    @Test
    fun `a tap after the sync of the previous tap has finished asks for the opposite of the state it left`() {
        service.onClick()
        dart.take()
        dart.configure()
        assertEquals(Tile.STATE_ACTIVE, tile.state)
        assertEquals(UNTIL_TEXT, tile.subtitle)

        service.onClick()
        assertEquals(Tile.STATE_INACTIVE, tile.state)
        dart.take()
        dart.configure()
        assertEquals(false, dart.muted)
        assertEquals(Tile.STATE_INACTIVE, tile.state)
        assertNull(tile.subtitle)
    }

    /**
     * Every order of taps and syncs in [STEPS] steps. A step is a tap or the next stage of a sync (a sync is
     * two stages, take and finish, and runs never overlap: the sync lock allows one at a time). After each
     * step the tile shows what the latest tap asked for; each tap asks for the opposite of the one before it;
     * and a last sync leaves Dart in the state of the latest tap.
     */
    @Test
    fun `after any order of taps and syncs the tile and the next tap follow the latest tap`() {
        runsFinish = true
        val workManager = WorkManager.getInstance(app)
        val store = QuietStore(app)
        var sequences = 0
        for (pattern in 0 until (1 shl STEPS)) {
            sequences++
            app.getSharedPreferences(QuietStore.PREFS, Context.MODE_PRIVATE).edit().clear().commit()
            workManager.pruneWork().result.get()
            dart = FakeDart()

            var latest: String? = null // what the latest tap asked for
            var waiting: String? = null // the request no sync has taken yet
            var syncRunning = false
            var taken: String? = null // what the running sync took
            val steps = StringBuilder()

            fun check(step: String) {
                steps.append(step).append(' ')
                val context = "pattern $pattern: $steps"
                val expected = latest ?: return
                assertEquals(context, stateOf(expected), tile.state)
                assertEquals(context, expected == QuietStore.MUTE, store.display().active)
                assertEquals(context, if (expected == QuietStore.MUTE) QuietStore.END else QuietStore.MUTE, store.actionForTap())
            }

            for (bit in 0 until STEPS) {
                if (((pattern shr bit) and 1) == 1) {
                    val expected = if (latest == QuietStore.MUTE) QuietStore.END else QuietStore.MUTE
                    service.onClick()
                    latest = expected
                    waiting = expected
                    check("tap(${expected})")
                } else if (!syncRunning) {
                    val got = dart.take()
                    assertEquals("pattern $pattern: $steps take", waiting, got)
                    taken = got
                    waiting = null
                    syncRunning = true
                    check("take(${got})")
                } else {
                    dart.configure()
                    syncRunning = false
                    check("finish(${taken})")
                }
            }

            // A last sync, after the one that may still be running: Dart ends in the state of the latest tap.
            if (syncRunning) dart.configure()
            dart.take()
            dart.configure()
            val last = latest
            if (last != null) {
                assertEquals("pattern $pattern: $steps last sync", last == QuietStore.MUTE, dart.muted)
                assertEquals("pattern $pattern: $steps last sync", stateOf(last), tile.state)
                assertEquals("pattern $pattern: $steps last sync", if (last == QuietStore.MUTE) UNTIL_TEXT else null, tile.subtitle)
            }
        }
        assertEquals(1 shl STEPS, sequences)
    }

    private companion object {
        const val HOUR = 3_600_000L
        const val UNTIL_TEXT = "Until 07:00"
        const val STEPS = 7
        val NOTHING_TO_CANCEL: () -> Unit = {}
    }
}
