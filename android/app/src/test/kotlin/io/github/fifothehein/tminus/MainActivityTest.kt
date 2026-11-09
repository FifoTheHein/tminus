package io.github.fifothehein.tminus

import android.content.Intent
import android.net.Uri
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleRegistry
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.android.FlutterActivityLaunchConfigs
import io.github.fifothehein.tminus.engine.AlarmActivity
import io.github.fifothehein.tminus.engine.NOW
import io.github.fifothehein.tminus.engine.RingingSession
import io.github.fifothehein.tminus.engine.alert
import io.github.fifothehein.tminus.sync.SyncNotifications
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf

/**
 * MainActivity's alarm screen route. A JVM test cannot start a Flutter engine, so the activity is not
 * created; its lifecycle (which FlutterActivity drives from onResume / onPause) is moved by hand.
 */
@RunWith(RobolectricTestRunner::class)
class MainActivityTest {
    @Before
    fun setUp() {
        RingingSession.clear()
    }

    @After
    fun tearDown() {
        RingingSession.clear()
    }

    @Test
    fun `resuming MainActivity while an alarm rings opens the alarm screen, and pausing stops that`() {
        val activity = Robolectric.buildActivity(MainActivity::class.java).get()
        val lifecycle = activity.lifecycle as LifecycleRegistry
        RingingSession.add(listOf(alert("a", NOW)))

        listOf(Lifecycle.Event.ON_CREATE, Lifecycle.Event.ON_START).forEach(lifecycle::handleLifecycleEvent)
        assertNull("opens only once resumed", shadowOf(activity).nextStartedActivity)
        lifecycle.handleLifecycleEvent(Lifecycle.Event.ON_RESUME)

        val started = shadowOf(activity).nextStartedActivity
        assertNotNull("alarm screen started", started)
        assertEquals(AlarmActivity::class.java.name, started.component!!.className)
        assertTrue(started.flags and Intent.FLAG_ACTIVITY_NEW_TASK != 0)

        lifecycle.handleLifecycleEvent(Lifecycle.Event.ON_PAUSE)
        RingingSession.clear()
        RingingSession.add(listOf(alert("b", NOW)))
        assertNull("a paused activity opens nothing", shadowOf(activity).nextStartedActivity)
    }

    // MainActivity is exported, so what an intent carries is chosen by any app. These build the activity
    // with a hostile intent and read the settings FlutterActivity would start the engine with. The
    // activity is not created: only the getters that start-up reads are called.
    private fun launchedWith(intent: Intent): MainActivity =
        Robolectric.buildActivity(MainActivity::class.java, intent).get()

    /** `getBackgroundMode` is protected: it is called through FlutterActivity, so the override answers. */
    private fun backgroundModeOf(activity: MainActivity): Any? =
        FlutterActivity::class.java.getDeclaredMethod("getBackgroundMode").apply { isAccessible = true }.invoke(activity)

    @Test
    fun `launch extras cannot change the entry point or crash start-up`() {
        val hostile = Intent()
            .putExtra("dart_entrypoint", "syncMain")
            .putExtra("dart_entrypoint_args", "not a list")
            .putExtra("cached_engine_id", "x")
            .putExtra("cached_engine_group_id", "g")
            .putExtra("background_mode", "nope")
            .putExtra("destroy_engine_with_activity", false)
        val activity = launchedWith(hostile)

        assertEquals("main", activity.getDartEntrypointFunctionName())
        assertNull(activity.getDartEntrypointArgs())
        assertNull(activity.getCachedEngineId())
        assertNull(activity.getCachedEngineGroupId())
        assertEquals(FlutterActivityLaunchConfigs.BackgroundMode.opaque, backgroundModeOf(activity))
        assertTrue(activity.shouldDestroyEngineWithHost())
    }

    @Test
    fun `only the source route reaches Flutter`() {
        val flutterOwn = Intent(Intent.ACTION_VIEW, Uri.parse("https://x/settings"))
            .putExtra("route", "/settings/developer")
        val foreign = launchedWith(flutterOwn)
        assertEquals("/", foreign.getInitialRoute())
        assertFalse(foreign.shouldHandleDeeplinking())

        val fix = launchedWith(Intent().putExtra(SyncNotifications.EXTRA_ROUTE, "/sources/ics-1"))
        assertEquals("/sources/ics-1", fix.getInitialRoute())
    }
}
