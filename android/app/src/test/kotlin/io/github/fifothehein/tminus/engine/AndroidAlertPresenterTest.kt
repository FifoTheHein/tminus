package io.github.fifothehein.tminus.engine

import android.app.Application
import android.app.NotificationManager
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
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
    fun `an alert is showing while it rings or its group's heads-up is posted`() {
        val presenter = AndroidAlertPresenter(app, store) { _, _ -> }
        val ringing = alert("r", NOW, group = "R")
        val posted = alert("h", NOW, strength = Strength.HEADS_UP, group = "H")
        val gone = alert("g", NOW, strength = Strength.HEADS_UP, group = "X")
        RingingSession.add(listOf(ringing))
        NotificationFactory(app).postHeadsUp(listOf(posted))

        assertTrue(presenter.isShowing(ringing))
        assertTrue(presenter.isShowing(posted))
        assertFalse(presenter.isShowing(gone))
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
        assertNull(shadowOf(manager).getNotification(NotificationFactory.HEADS_UP_SUMMARY_ID)) // its last child went
    }

    @Test
    fun `withdrawing one of two heads-ups keeps the group summary`() {
        val h = alert("h", NOW, strength = Strength.HEADS_UP, group = "H")
        val k = alert("k", NOW, strength = Strength.HEADS_UP, group = "K")
        NotificationFactory(app).postHeadsUp(listOf(h))
        NotificationFactory(app).postHeadsUp(listOf(k))
        store.write(EngineState(presented = listOf(k)))
        AndroidAlertPresenter(app, store).withdraw(listOf(h))
        assertNull(shadowOf(manager).getNotification(NotificationFactory.headsUpId("H")))
        assertNotNull(shadowOf(manager).getNotification(NotificationFactory.headsUpId("K")))
        assertNotNull(shadowOf(manager).getNotification(NotificationFactory.HEADS_UP_SUMMARY_ID))
    }

    @Test
    fun `an alarm absorbing the only heads-up cancels the heads-up summary too`() {
        val h = alert("h", NOW, strength = Strength.HEADS_UP, group = "G")
        val factory = NotificationFactory(app)
        factory.postHeadsUp(listOf(h))
        val a = alert("a", NOW + 2_000, group = "G")
        store.write(EngineState(presented = listOf(h, a)))
        AndroidAlertPresenter(app, store, factory) { _, _ -> }.present(listOf(a))
        assertTrue(shadowOf(manager).allNotifications.isEmpty())
    }

    @Test
    fun `an alarm firing into a group whose heads-up is showing rings it too and withdraws the heads-up`() {
        val h = alert("h", NOW, strength = Strength.HEADS_UP, group = "G")
        val other = alert("o", NOW, strength = Strength.HEADS_UP, group = "O")
        val factory = NotificationFactory(app)
        factory.postHeadsUp(listOf(h))
        factory.postHeadsUp(listOf(other))
        val a = alert("a", NOW + 2_000, group = "G")
        store.write(EngineState(presented = listOf(h, other, a))) // fire has moved a to presented
        val started = mutableListOf<List<String>>()

        AndroidAlertPresenter(app, store, factory) { _, ids -> started.add(ids) }.present(listOf(a))

        assertEquals(listOf(listOf("a", "h")), started)
        assertNull(shadowOf(manager).getNotification(NotificationFactory.headsUpId("G")))
        assertNotNull(shadowOf(manager).getNotification(NotificationFactory.headsUpId("O"))) // another group keeps its own
        assertNotNull(shadowOf(manager).getNotification(NotificationFactory.HEADS_UP_SUMMARY_ID)) // and the summary
    }

    @Test
    fun `a heads-up firing into a group that is ringing joins the session and posts no heads-up`() {
        val a = alert("a", NOW, group = "G")
        val h = alert("h", NOW + 2_000, strength = Strength.HEADS_UP, group = "G")
        val other = alert("o", NOW + 2_000, strength = Strength.HEADS_UP, group = "O")
        RingingSession.add(listOf(a))
        store.write(EngineState(presented = listOf(a, h, other))) // fire has moved h and o to presented
        val presenter = AndroidAlertPresenter(app, store, NotificationFactory(app)) { _, _ -> error("already ringing") }

        presenter.present(listOf(h))
        presenter.present(listOf(other))

        assertEquals(setOf("a", "h"), RingingSession.ids)
        assertNull(shadowOf(manager).getNotification(NotificationFactory.headsUpId("G")))
        assertNotNull(shadowOf(manager).getNotification(NotificationFactory.headsUpId("O"))) // a group that is not ringing
        assertTrue(presenter.isShowing(h))
    }

    @Test
    fun `if the ringing service cannot start the group's heads-up stays and lists the alarm`() {
        val h = alert("h", NOW, strength = Strength.HEADS_UP, group = "G")
        val factory = NotificationFactory(app)
        factory.postHeadsUp(listOf(h))
        val a = alert("a", NOW + 2_000, group = "G")
        store.write(EngineState(presented = listOf(h, a)))

        AndroidAlertPresenter(app, store, factory) { _, _ -> throw IllegalStateException("not allowed") }.present(listOf(a))

        val n = shadowOf(manager).getNotification(NotificationFactory.headsUpId("G"))
        assertNotNull(n)
        assertEquals("2 meetings starting", n.extras.getCharSequence(android.app.Notification.EXTRA_TITLE).toString())
    }
}
