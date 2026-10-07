package io.github.fifothehein.tminus.engine

import android.content.Intent
import android.app.Application
import androidx.activity.ComponentActivity
import org.robolectric.RuntimeEnvironment
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

@RunWith(RobolectricTestRunner::class)
class AlarmScreenRouteTest {
    @Before
    fun setUp() {
        RingingSession.clear()
    }

    private fun resumed(): ComponentActivity = Robolectric.buildActivity(ComponentActivity::class.java).setup().get()

    private fun assertOpensAlarmScreen(activity: ComponentActivity) {
        val started = shadowOf(activity).nextStartedActivity
        assertNotNull("nothing started", started)
        assertEquals(AlarmActivity::class.java.name, started.component!!.className)
        assertTrue(started.flags and Intent.FLAG_ACTIVITY_NEW_TASK != 0)
    }

    @Test
    fun `resuming while ringing opens the alarm screen`() {
        val activity = resumed()
        RingingSession.add(listOf(alert("a", NOW)))

        AlarmScreenRoute(activity).attach() // MainActivity.onResume

        assertOpensAlarmScreen(activity)
    }

    @Test
    fun `a ring that starts while resumed opens the alarm screen`() {
        val activity = resumed()
        AlarmScreenRoute(activity).attach()
        assertNull(shadowOf(activity).nextStartedActivity)

        RingingSession.add(listOf(alert("a", NOW)))

        assertOpensAlarmScreen(activity)
    }

    @Test
    fun `nothing opens when not ringing`() {
        val activity = resumed()
        AlarmScreenRoute(activity).attach()
        RingingSession.add(emptyList())
        assertNull(shadowOf(activity).nextStartedActivity)
    }

    @Test
    fun `a ring that starts after pausing opens nothing`() {
        val activity = resumed()
        val route = AlarmScreenRoute(activity)
        route.attach()
        route.detach() // MainActivity.onPause

        RingingSession.add(listOf(alert("a", NOW)))

        assertNull(shadowOf(activity).nextStartedActivity)
    }

    @Test
    fun `a cold start after a mid-ring crash opens the alarm screen`() {
        val app: Application = RuntimeEnvironment.getApplication()
        val store = PlanStore(app).also { it.clear() }
        store.write(EngineState(presented = listOf(alert("a", NOW - MINUTE_MS).let { it.copy(event = it.event.copy(endUtcMs = Long.MAX_VALUE)) })))
        val activity = resumed()

        // MainActivity.configureFlutterEngine, then onResume. RingingService has not run yet, and with
        // notifications blocked nothing else would show the alarm.
        EngineActions(app, AndroidAlertPresenter(app, store, NotificationFactory(app)) { _, _ -> }, store).recoverPresented()
        AlarmScreenRoute(activity).attach()

        assertOpensAlarmScreen(activity)
    }
}
