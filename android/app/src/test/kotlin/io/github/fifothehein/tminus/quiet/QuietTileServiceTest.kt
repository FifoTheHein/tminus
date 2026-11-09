package io.github.fifothehein.tminus.quiet

import android.Manifest
import android.app.Application
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import androidx.work.Configuration
import androidx.work.ListenableWorker
import androidx.work.WorkerFactory
import androidx.work.WorkerParameters
import androidx.work.testing.SynchronousExecutor
import androidx.work.testing.WorkManagerTestInitHelper
import io.github.fifothehein.tminus.sync.SyncWorker
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import java.lang.ref.WeakReference

@RunWith(RobolectricTestRunner::class)
class QuietTileServiceTest {
    private val app: Application = RuntimeEnvironment.getApplication()

    private val started = mutableListOf<String>()

    @Before
    fun setUp() {
        // As in SyncSchedulingTest: a SyncWorker whose runner records the trigger and never boots Flutter.
        val factory = object : WorkerFactory() {
            override fun createWorker(context: Context, name: String, params: WorkerParameters): ListenableWorker? =
                if (name == SyncWorker::class.java.name) SyncWorker(context, params) { t, _ -> started += t; {} } else null
        }
        WorkManagerTestInitHelper.initializeTestWorkManager(
            app,
            Configuration.Builder().setExecutor(SynchronousExecutor()).setWorkerFactory(factory).build(),
        )
        app.getSharedPreferences(QuietStore.PREFS, Context.MODE_PRIVATE).edit().clear().commit()
    }

    @After
    fun tearDown() = WorkManagerTestInitHelper.closeWorkDatabase()

    // The keyguard of a Robolectric phone is not showing, so the tap goes straight to the toggle.
    @Test
    fun `a tap stores the request and queues a quietTile run`() {
        val service = Robolectric.setupService(QuietTileService::class.java)
        service.onClick()
        assertEquals(listOf(SyncWorker.TRIGGER_QUIET_TILE), started)
        assertEquals(QuietStore.MUTE, QuietStore(app).take()?.action)
    }

    @Test
    fun `the tile is exported, but only System UI may bind it`() {
        val info = app.packageManager.getServiceInfo(ComponentName(app, QuietTileService::class.java), 0)
        assertTrue(info.exported)
        assertEquals(Manifest.permission.BIND_QUICK_SETTINGS_TILE, info.permission)
        val tiles = app.packageManager.queryIntentServices(Intent(TileService.ACTION_QS_TILE).setPackage(app.packageName), 0)
        assertTrue(tiles.any { it.serviceInfo.name == QuietTileService::class.java.name })
    }

    @Test
    fun `a tap on a locked phone asks for an unlock first`() {
        val service = Robolectric.setupService(QuietTileService::class.java)
        shadowOf(service).setLocked(true)
        // Whether the phone was still locked each time the quiet store was written.
        val lockedAtWrite = mutableListOf<Boolean>()
        val watcher = SharedPreferences.OnSharedPreferenceChangeListener { _, _ -> lockedAtWrite += service.isLocked }
        val prefs = app.getSharedPreferences(QuietStore.PREFS, Context.MODE_PRIVATE)
        prefs.registerOnSharedPreferenceChangeListener(watcher)
        try {
            service.onClick()
        } finally {
            prefs.unregisterOnSharedPreferenceChangeListener(watcher)
        }

        // Robolectric's unlockAndRun unlocks the phone and only then runs what it was given.
        assertFalse(service.isLocked)
        assertEquals(QuietStore.MUTE, QuietStore(app).take()?.action)
        assertEquals(listOf(SyncWorker.TRIGGER_QUIET_TILE), started)
        assertTrue(lockedAtWrite.isNotEmpty())
        assertTrue("the request was stored before the unlock", lockedAtWrite.none { it })
    }

    @Test
    fun `a store change while listening redraws the tile`() {
        val service = Robolectric.setupService(QuietTileService::class.java)
        val inOneHour = System.currentTimeMillis() + 3_600_000
        QuietStore(app).mirror(inOneHour, "Until 07:00")
        service.onStartListening()
        val tile = service.qsTile
        // A new tile starts out inactive, so this is the tile drawing itself as it starts listening.
        assertEquals(Tile.STATE_ACTIVE, tile.state)
        assertEquals("Until 07:00", tile.subtitle)

        // SharedPreferences holds its listeners weakly: the tile must hold its own.
        collectGarbage()

        // A sync that finished in the background leaves a new state in the store.
        QuietStore(app).mirror(null, null)
        assertEquals(Tile.STATE_INACTIVE, tile.state)
        assertNull(tile.subtitle)

        // Once the tile stops listening nobody redraws it.
        service.onStopListening()
        QuietStore(app).mirror(inOneHour, "Until 07:00")
        assertEquals(Tile.STATE_INACTIVE, tile.state)
    }

    /** Runs the garbage collector until it has demonstrably cleared a weakly reachable object. */
    private fun collectGarbage() {
        val probe = WeakReference(Any())
        var tries = 0
        while (probe.get() != null && tries++ < 20) {
            System.gc()
            Thread.sleep(10)
        }
    }
}
