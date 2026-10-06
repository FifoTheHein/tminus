package io.github.fifothehein.tminus.engine

import android.app.Application
import android.app.NotificationManager
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf

@RunWith(RobolectricTestRunner::class)
class AndroidAlertPresenterTest {
    private val app: Application = RuntimeEnvironment.getApplication()
    private val manager: NotificationManager = app.getSystemService(NotificationManager::class.java)
    private lateinit var store: PlanStore

    @Before
    fun setUp() {
        RingingSession.clear()
        store = PlanStore(app).also { it.clear() }
    }

    @Test
    fun `a group with an alarm starts ringing with every id, heads-ups included`() {
        val started = mutableListOf<List<String>>()
        val presenter = AndroidAlertPresenter(app, store, NotificationFactory(app)) { _, ids -> started.add(ids) }
        presenter.present(listOf(alert("a", NOW, group = "G"), alert("h", NOW, strength = Strength.HEADS_UP, group = "G")))
        assertEquals(listOf(listOf("a", "h")), started)
        assertTrue(shadowOf(manager).allNotifications.isEmpty())
    }

    @Test
    fun `the default starter starts RingingService`() {
        AndroidAlertPresenter(app, store).present(listOf(alert("a", NOW)))
        val intent = shadowOf(app).nextStartedService
        assertEquals(RingingService::class.java.name, intent.component!!.className)
        assertEquals(arrayListOf("a"), intent.getStringArrayListExtra(RingingService.EXTRA_ALERT_IDS))
    }

    @Test
    fun `a heads-up group posts a heads-up notification`() {
        val h = alert("h", NOW, strength = Strength.HEADS_UP)
        AndroidAlertPresenter(app, store) { _, _ -> error("must not ring") }.present(listOf(h))
        assertNotNull(shadowOf(manager).getNotification(NotificationFactory.headsUpId(h.coalesceGroup)))
    }

    @Test
    fun `if the ringing service cannot start the alert is posted as a heads-up`() {
        val a = alert("a", NOW)
        val presenter = AndroidAlertPresenter(app, store, NotificationFactory(app)) { _, _ ->
            throw IllegalStateException("startForegroundService() not allowed") // what ForegroundServiceStartNotAllowedException extends
        }
        presenter.present(listOf(a))
        assertNotNull(shadowOf(manager).getNotification(NotificationFactory.headsUpId(a.coalesceGroup)))
    }

    @Test
    fun `withdraw stops ringing those alerts and clears a heads-up with nothing left`() {
        val a = alert("a", NOW)
        RingingSession.add(listOf(a, alert("b", NOW)))
        val h = alert("h", NOW, strength = Strength.HEADS_UP, group = "H")
        NotificationFactory(app).postHeadsUp(listOf(h))
        AndroidAlertPresenter(app, store).withdraw(listOf(a, h))
        assertEquals(setOf("b"), RingingSession.ids)
        assertNull(shadowOf(manager).getNotification(NotificationFactory.headsUpId("H")))
    }
}
