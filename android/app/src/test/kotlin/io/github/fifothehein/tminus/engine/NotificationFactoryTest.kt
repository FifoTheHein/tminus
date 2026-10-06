package io.github.fifothehein.tminus.engine

import android.app.Notification
import android.app.NotificationManager
import android.content.Context
import android.media.AudioAttributes
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import java.time.Instant
import java.time.ZoneId
import java.util.Locale

@RunWith(RobolectricTestRunner::class)
class NotificationFactoryTest {
    private val context: Context = RuntimeEnvironment.getApplication()
    private val manager: NotificationManager = context.getSystemService(NotificationManager::class.java)
    private val start = Instant.parse("2026-10-06T08:00:00Z").toEpochMilli()
    private val factory = NotificationFactory(
        context,
        AlertText(ZoneId.of("Africa/Johannesburg"), is24Hour = true, locale = Locale.US),
    ) { start - 10 * MINUTE_MS }
    private val link = "https://teams.microsoft.com/l/meetup-join/abc"

    private fun meeting(id: String = "a", joinUrl: String? = null, location: String? = null, title: String = "Sprint planning") =
        alert(id, start - 10 * MINUTE_MS, strength = Strength.HEADS_UP, start = start, title = title, joinUrl = joinUrl, location = location)

    private fun Notification.title() = extras.getCharSequence(Notification.EXTRA_TITLE).toString()
    private fun Notification.body() = extras.getCharSequence(Notification.EXTRA_TEXT).toString()
    private fun Notification.actionTitles() = actions?.map { it.title.toString() } ?: emptyList()

    @Test
    fun `channels have the importance and sound the spec asks for`() {
        factory.ensureChannels()
        val headsUp = manager.getNotificationChannel(NotificationFactory.CHANNEL_HEADS_UP)
        assertEquals(NotificationManager.IMPORTANCE_HIGH, headsUp.importance)
        assertNotNull(headsUp.sound) // a notification sound, so silent mode silences it
        assertEquals(AudioAttributes.USAGE_NOTIFICATION_EVENT, headsUp.audioAttributes.usage)
        val ringing = manager.getNotificationChannel(NotificationFactory.CHANNEL_RINGING)
        assertEquals(NotificationManager.IMPORTANCE_HIGH, ringing.importance)
        assertNull(ringing.sound) // RingingService plays the alarm itself
        assertEquals(NotificationManager.IMPORTANCE_DEFAULT, manager.getNotificationChannel(NotificationFactory.CHANNEL_MISSED).importance)
    }

    @Test
    fun `heads-up with a link offers Join, Snooze and Dismiss all`() {
        val n = factory.headsUp(listOf(meeting(joinUrl = link)))
        assertEquals(NotificationFactory.CHANNEL_HEADS_UP, n.channelId)
        assertEquals("In 10 min · Sprint planning", n.title())
        assertEquals("10:00–10:30 · Teams", n.body())
        assertEquals(listOf("Join", "Snooze", "Dismiss all"), n.actionTitles())
        assertTrue(shadowOf(n.actions[0].actionIntent).isActivityIntent) // no trampoline
    }

    @Test
    fun `heads-up without a link offers Snooze and Dismiss all`() {
        val n = factory.headsUp(listOf(meeting(location = "Boardroom 2")))
        assertEquals("10:00–10:30 · Boardroom 2", n.body())
        assertEquals(listOf("Snooze", "Dismiss all"), n.actionTitles())
    }

    @Test
    fun `a coalesced heads-up reads N meetings starting`() {
        val n = factory.headsUp(listOf(meeting("a", joinUrl = link), meeting("b", title = "Call the bank")))
        assertEquals("2 meetings starting", n.title())
        assertEquals("Sprint planning, Call the bank", n.body())
        assertEquals(listOf("Dismiss", "Snooze all", "Dismiss all"), n.actionTitles())
    }

    @Test
    fun `swiping a heads-up away sends a single Dismiss`() {
        val n = factory.headsUp(listOf(meeting()))
        assertEquals(NotificationActionReceiver.ACTION_DISMISS, shadowOf(n.deleteIntent).savedIntent.action)
    }

    @Test
    fun `postHeadsUp posts under the coalesce group's id`() {
        val a = meeting()
        factory.postHeadsUp(listOf(a))
        assertNotNull(shadowOf(manager).getNotification(NotificationFactory.headsUpId(a.coalesceGroup)))
        factory.cancelHeadsUp(a.coalesceGroup)
        assertNull(shadowOf(manager).getNotification(NotificationFactory.headsUpId(a.coalesceGroup)))
    }

    @Test
    fun `missed reads Missed title and start time with an Open action`() {
        val d = alert("d", start - MINUTE_MS, start = start + 4 * HOUR, title = "Design review")
        factory.postMissed(d)
        val n = shadowOf(manager).getNotification(NotificationFactory.missedId("d"))
        assertEquals(NotificationFactory.CHANNEL_MISSED, n.channelId)
        assertEquals("Missed: Design review (14:00)", n.title())
        assertEquals(listOf("Open"), n.actionTitles())
    }

    @Test
    fun `the ringing notification is colorized so Android 16 never force-groups and silences it`() {
        // Android 16 force-groups an app's notifications and sets FLAG_SILENT on each one it groups,
        // and SystemUI then suppresses that notification's full-screen intent. A colorized
        // foreground-service notification is exempt from force grouping (GroupHelper).
        val alarm = meeting().copy(strength = Strength.ALARM)
        listOf(factory.ringing(listOf(alarm)), factory.ringing(emptyList())).forEach { n ->
            assertTrue(n.extras.getBoolean(Notification.EXTRA_COLORIZED))
            assertFalse(n.flags and FLAG_SILENT != 0)
            assertEquals(Notification.GROUP_ALERT_ALL, n.groupAlertBehavior)
            assertNotNull(n.fullScreenIntent)
        }
        assertEquals(alarm.event.color.toInt(), factory.ringing(listOf(alarm)).color) // the calendar colour fills it
        assertNull(factory.ringing(listOf(alarm)).group) // outside the heads-up and missed groups
    }

    private fun Notification.isSummary() = flags and Notification.FLAG_GROUP_SUMMARY != 0

    private fun assertChildWithSummary(child: Notification, group: String, summaryId: Int, channel: String) {
        // Android 16 force-groups (and marks FLAG_SILENT) an app's ungrouped notifications, and a group
        // child without a posted summary. An app group with its summary is left alone.
        assertEquals(group, child.group)
        assertFalse(child.isSummary())
        assertEquals(Notification.GROUP_ALERT_CHILDREN, child.groupAlertBehavior) // the child alerts
        val summary = shadowOf(manager).getNotification(summaryId)
        assertNotNull("summary posted", summary)
        assertEquals(group, summary.group)
        assertTrue(summary.isSummary())
        assertEquals(Notification.GROUP_ALERT_CHILDREN, summary.groupAlertBehavior) // the summary never alerts
        assertEquals(channel, summary.channelId)
        assertFalse(summary.flags and FLAG_SILENT != 0)
        assertFalse(child.flags and FLAG_SILENT != 0)
    }

    @Test
    fun `a heads-up is a child of the heads-up group and the group's summary is posted`() {
        val a = meeting()
        factory.postHeadsUp(listOf(a))
        val n = shadowOf(manager).getNotification(NotificationFactory.headsUpId(a.coalesceGroup))
        assertChildWithSummary(n, NotificationFactory.GROUP_HEADS_UP, NotificationFactory.HEADS_UP_SUMMARY_ID, NotificationFactory.CHANNEL_HEADS_UP)
        assertEquals(NotificationFactory.CHANNEL_HEADS_UP, n.channelId)
        assertEquals(listOf("Snooze", "Dismiss all"), n.actionTitles()) // still at most 3 actions
        assertEquals(NotificationActionReceiver.ACTION_DISMISS, shadowOf(n.deleteIntent).savedIntent.action)
    }

    @Test
    fun `a silent re-post stays in the heads-up group`() {
        val a = meeting()
        factory.postHeadsUp(listOf(a), silent = true)
        val n = shadowOf(manager).getNotification(NotificationFactory.headsUpId(a.coalesceGroup))
        assertEquals(NotificationFactory.GROUP_HEADS_UP, n.group)
        assertNotNull(shadowOf(manager).getNotification(NotificationFactory.HEADS_UP_SUMMARY_ID))
    }

    @Test
    fun `a missed notification is a child of the missed group and the group's summary is posted`() {
        val d = alert("d", start - MINUTE_MS, start = start + 4 * HOUR, title = "Design review")
        factory.postMissed(d)
        val n = shadowOf(manager).getNotification(NotificationFactory.missedId("d"))
        assertChildWithSummary(n, NotificationFactory.GROUP_MISSED, NotificationFactory.MISSED_SUMMARY_ID, NotificationFactory.CHANNEL_MISSED)
    }

    @Test
    fun `cancelling the last heads-up cancels the group summary`() {
        val a = alert("a", start - 10 * MINUTE_MS, strength = Strength.HEADS_UP, start = start, group = "A")
        val b = alert("b", start - 10 * MINUTE_MS, strength = Strength.HEADS_UP, start = start, group = "B")
        factory.postHeadsUp(listOf(a))
        factory.postHeadsUp(listOf(b))
        factory.postMissed(alert("d", start - MINUTE_MS, start = start + 4 * HOUR))

        factory.cancelHeadsUp("A")
        assertNotNull(shadowOf(manager).getNotification(NotificationFactory.HEADS_UP_SUMMARY_ID)) // b is still showing

        factory.cancelHeadsUp("B")
        assertNull(shadowOf(manager).getNotification(NotificationFactory.HEADS_UP_SUMMARY_ID))
        assertNotNull(shadowOf(manager).getNotification(NotificationFactory.MISSED_SUMMARY_ID)) // the missed group is separate
    }

    @Test
    fun `cancelling several heads-ups at once cancels the summary when none is left`() {
        val a = alert("a", start - 10 * MINUTE_MS, strength = Strength.HEADS_UP, start = start, group = "A")
        val b = alert("b", start - 10 * MINUTE_MS, strength = Strength.HEADS_UP, start = start, group = "B")
        factory.postHeadsUp(listOf(a))
        factory.postHeadsUp(listOf(b))
        factory.cancelHeadsUpNotifications(listOf(NotificationFactory.headsUpId("A"), NotificationFactory.headsUpId("B")))
        assertTrue(shadowOf(manager).allNotifications.isEmpty())
    }

    private companion object {
        /** Notification.FLAG_SILENT (API 36, hidden on the SDK the tests run on). */
        const val FLAG_SILENT = 1 shl 17
    }
}
