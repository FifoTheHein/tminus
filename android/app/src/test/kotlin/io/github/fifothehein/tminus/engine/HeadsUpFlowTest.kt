package io.github.fifothehein.tminus.engine

import android.app.Notification
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.shadows.ShadowAlarmManager
import org.robolectric.shadows.ShadowMediaPlayer
import org.robolectric.shadows.util.DataSource
import android.app.Application
import android.provider.Settings

@RunWith(RobolectricTestRunner::class)
class HeadsUpFlowTest {
    private val context: Context = RuntimeEnvironment.getApplication()
    private val manager: NotificationManager = context.getSystemService(NotificationManager::class.java)
    private val now = System.currentTimeMillis()
    private lateinit var store: PlanStore

    @Before
    fun setUp() {
        ShadowAlarmManager.setCanScheduleExactAlarms(true)
        RingingSession.clear() // in-process state another test class may have left ringing
        store = PlanStore(context).also { it.clear() }
        EventQueue(context).drain()
    }

    private fun fireHeadsUp(): PlannedAlert {
        val h = alert("h", now + MINUTE_MS, strength = Strength.HEADS_UP, start = now + 10 * MINUTE_MS)
        AlarmScheduler(context, store).applyPlan(listOf(h))
        AlarmReceiver().onReceive(context, AlarmReceiver.fireIntent(context, "h"))
        return h
    }

    private fun tap(action: String, h: PlannedAlert) = NotificationActionReceiver().onReceive(
        context,
        NotificationActionReceiver.intent(context, action, arrayListOf(h.id), NotificationFactory.headsUpId(h.coalesceGroup)),
    )

    @Test
    fun `a heads-up alarm posts a notification and queues fired`() {
        val h = fireHeadsUp()
        val n = shadowOf(manager).getNotification(NotificationFactory.headsUpId(h.coalesceGroup))
        assertNotNull(n)
        assertEquals(NotificationFactory.CHANNEL_HEADS_UP, n.channelId)
        assertEquals(listOf(EngineEventType.FIRED), EventQueue(context).drain().map { it.type })
        assertEquals(listOf("h"), store.read().presented.map { it.id })
    }

    @Test
    fun `Dismiss all from the notification acks the occurrence and removes the notification`() {
        val h = fireHeadsUp()
        EventQueue(context).drain()
        tap(NotificationActionReceiver.ACTION_DISMISS_ALL, h)
        assertNull(shadowOf(manager).getNotification(NotificationFactory.headsUpId(h.coalesceGroup)))
        assertEquals(listOf(EngineEventType.DISMISSED_ALL), EventQueue(context).drain().map { it.type })
        assertEquals(listOf(Ack(h.occurrenceKey, h.event.startUtcMs)), store.read().acks)
    }

    @Test
    fun `Snooze from the notification schedules the colon-s snooze`() {
        val h = fireHeadsUp()
        EventQueue(context).drain()
        tap(NotificationActionReceiver.ACTION_SNOOZE, h)
        assertEquals(listOf("h:s"), store.read().snoozes.map { it.id })
        assertNull(shadowOf(manager).getNotification(NotificationFactory.headsUpId(h.coalesceGroup)))
        assertEquals(listOf(EngineEventType.SNOOZED), EventQueue(context).drain().map { it.type })
    }

    private fun fireGroupOfTwo(): Pair<PlannedAlert, PlannedAlert> {
        val a = alert("a", now + MINUTE_MS, strength = Strength.HEADS_UP, start = now + 10 * MINUTE_MS, title = "Sprint planning", group = "G")
        val b = alert("b", now + MINUTE_MS + 20_000, strength = Strength.HEADS_UP, start = now + 10 * MINUTE_MS, title = "Call the bank", group = "G")
        AlarmScheduler(context, store).applyPlan(listOf(a, b))
        AlarmReceiver().onReceive(context, AlarmReceiver.fireIntent(context, "a"))
        AlarmReceiver().onReceive(context, AlarmReceiver.fireIntent(context, "b")) // b's own, later alarm
        return a to b
    }

    private fun Notification.title() = extras.getCharSequence(Notification.EXTRA_TITLE).toString()

    @Test
    fun `a heads-up firing into an already-presented group lists both`() {
        fireGroupOfTwo()
        val n = shadowOf(manager).getNotification(NotificationFactory.headsUpId("G"))
        assertEquals("2 meetings starting", n.title())
        assertEquals(1, shadowOf(manager).allNotifications.size)
    }

    @Test
    fun `Dismiss all on one alert of a group leaves a notification for the rest`() {
        val (a, b) = fireGroupOfTwo()
        tap(NotificationActionReceiver.ACTION_DISMISS_ALL, a)
        val n = shadowOf(manager).getNotification(NotificationFactory.headsUpId("G"))
        assertNotNull(n)
        assertTrue(n.title(), n.title().endsWith(b.event.title))
        assertEquals(listOf("b"), store.read().presented.map { it.id })
    }

    @Test
    fun `an alarm for an alert that is gone shows nothing`() {
        AlarmReceiver().onReceive(context, AlarmReceiver.fireIntent(context, "nope"))
        assertTrue(shadowOf(manager).allNotifications.isEmpty())
        assertTrue(EventQueue(context).drain().isEmpty())
    }

    @Test
    fun `Join records the join, opens the link and finishes`() {
        val j = alert("j", now, joinUrl = "https://teams.microsoft.com/l/meetup-join/abc")
        store.write(EngineState(presented = listOf(j)))
        val activity = Robolectric.buildActivity(JoinActivity::class.java, JoinActivity.intent(context, "j")).create().get()
        val opened: Intent = shadowOf(activity).nextStartedActivity
        assertEquals(Intent.ACTION_VIEW, opened.action)
        assertEquals("https://teams.microsoft.com/l/meetup-join/abc", opened.dataString)
        assertTrue(activity.isFinishing)
        assertEquals(listOf(EngineEventType.JOINED), EventQueue(context).drain().map { it.type })
    }

    @Test
    fun `Join for an alert that is gone just finishes`() {
        val activity = Robolectric.buildActivity(JoinActivity::class.java, JoinActivity.intent(context, "gone")).create().get()
        assertNull(shadowOf(activity).nextStartedActivity)
        assertTrue(activity.isFinishing)
    }

    @Test
    fun `an alarm firing into a group whose heads-up is showing absorbs it into one ringing session`() {
        ShadowMediaPlayer.addMediaInfo(
            DataSource.toDataSource(context, Settings.System.DEFAULT_ALARM_ALERT_URI),
            ShadowMediaPlayer.MediaInfo(60_000, 0),
        )
        val start = now + 10 * MINUTE_MS
        val h = alert("h", now + MINUTE_MS, strength = Strength.HEADS_UP, start = start, title = "Call the bank", group = "G")
        val a = alert("a", now + MINUTE_MS + 2_000, start = start, title = "Sprint planning", group = "G")
        AlarmScheduler(context, store).applyPlan(listOf(h, a))
        AlarmReceiver().onReceive(context, AlarmReceiver.fireIntent(context, "h"))
        assertNotNull(shadowOf(manager).getNotification(NotificationFactory.headsUpId("G")))

        AlarmReceiver().onReceive(context, AlarmReceiver.fireIntent(context, "a")) // a's own, later alarm
        val ring = shadowOf(context as Application).nextStartedService
        Robolectric.buildService(RingingService::class.java, ring).create().startCommand(0, 1)

        assertEquals(setOf("a", "h"), RingingSession.ids)
        assertNull(shadowOf(manager).getNotification(NotificationFactory.headsUpId("G")))
        val ringing = shadowOf(manager).getNotification(NotificationFactory.RINGING_NOTIFICATION_ID)
        assertEquals("2 meetings starting", ringing.title())
        assertEquals(listOf("Stop", "Snooze all", "Dismiss all"), ringing.actions.map { it.title.toString() })

        // Snooze all on the session snoozes both.
        EngineActions.create(context).snooze(RingingSession.ids, null)
        assertEquals(setOf("a:s", "h:s"), store.read().snoozes.map { it.id }.toSet())
        assertTrue(RingingSession.ids.isEmpty())
    }

    @Test
    fun `a heads-up firing into a group that is ringing joins the ringing session`() {
        ShadowMediaPlayer.addMediaInfo(
            DataSource.toDataSource(context, Settings.System.DEFAULT_ALARM_ALERT_URI),
            ShadowMediaPlayer.MediaInfo(60_000, 0),
        )
        val start = now + 10 * MINUTE_MS
        val a = alert("a", now + MINUTE_MS, start = start, title = "Sprint planning", group = "G")
        val h = alert("h", now + MINUTE_MS + 2_000, strength = Strength.HEADS_UP, start = start, title = "Call the bank", group = "G")
        AlarmScheduler(context, store).applyPlan(listOf(a, h))
        AlarmReceiver().onReceive(context, AlarmReceiver.fireIntent(context, "a"))
        val ring = shadowOf(context as Application).nextStartedService
        Robolectric.buildService(RingingService::class.java, ring).create().startCommand(0, 1)
        assertEquals(setOf("a"), RingingSession.ids)

        AlarmReceiver().onReceive(context, AlarmReceiver.fireIntent(context, "h")) // h's own, later alarm

        assertEquals(setOf("a", "h"), RingingSession.ids)
        assertNull(shadowOf(manager).getNotification(NotificationFactory.headsUpId("G")))
        val ringing = shadowOf(manager).getNotification(NotificationFactory.RINGING_NOTIFICATION_ID)
        assertEquals("2 meetings starting", ringing.title())
        assertEquals(listOf("Stop", "Snooze all", "Dismiss all"), ringing.actions.map { it.title.toString() })
        assertEquals(listOf(EngineEventType.FIRED, EngineEventType.FIRED), EventQueue(context).drain().map { it.type })

        // Stop on the session dismisses both.
        EngineActions.create(context).dismiss(RingingSession.ids)
        assertTrue(RingingSession.ids.isEmpty())
        assertTrue(store.read().presented.isEmpty())
        assertNull(shadowOf(manager).getNotification(NotificationFactory.headsUpId("G")))
    }
}
