package io.github.fifothehein.tminus.engine

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

@RunWith(RobolectricTestRunner::class)
class HeadsUpFlowTest {
    private val context: Context = RuntimeEnvironment.getApplication()
    private val manager: NotificationManager = context.getSystemService(NotificationManager::class.java)
    private val now = System.currentTimeMillis()
    private lateinit var store: PlanStore

    @Before
    fun setUp() {
        ShadowAlarmManager.setCanScheduleExactAlarms(true)
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
}
