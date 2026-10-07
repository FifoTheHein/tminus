package io.github.fifothehein.tminus

import android.content.Intent
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleRegistry
import io.github.fifothehein.tminus.engine.AlarmActivity
import io.github.fifothehein.tminus.engine.NOW
import io.github.fifothehein.tminus.engine.RingingSession
import io.github.fifothehein.tminus.engine.alert
import org.junit.After
import org.junit.Assert.assertEquals
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
}
