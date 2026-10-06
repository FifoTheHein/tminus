package io.github.fifothehein.tminus.engine

import android.app.Notification
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.os.Looper
import android.provider.Settings
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.android.controller.ServiceController
import org.robolectric.shadows.ShadowMediaPlayer
import org.robolectric.shadows.util.DataSource
import java.time.Duration

@RunWith(RobolectricTestRunner::class)
class RingingServiceTest {
    private val context: Context = RuntimeEnvironment.getApplication()
    private val manager: NotificationManager = context.getSystemService(NotificationManager::class.java)
    private val link = "https://teams.microsoft.com/l/meetup-join/abc"

    @Before
    fun setUp() {
        RingingSession.clear()
        PlanStore(context).clear()
        EventQueue(context).drain()
        // Robolectric's MediaPlayer only plays sources it has been told about.
        ShadowMediaPlayer.addMediaInfo(
            DataSource.toDataSource(context, Settings.System.DEFAULT_ALARM_ALERT_URI),
            ShadowMediaPlayer.MediaInfo(60_000, 0),
        )
    }

    private fun startWith(vararg alerts: PlannedAlert): ServiceController<RingingService> {
        PlanStore(context).write(EngineState(presented = alerts.toList()))
        val intent = Intent(context, RingingService::class.java)
            .putStringArrayListExtra(RingingService.EXTRA_ALERT_IDS, ArrayList(alerts.map { it.id }))
        return Robolectric.buildService(RingingService::class.java, intent).create().startCommand(0, 1)
    }

    private fun Notification.title() = extras.getCharSequence(Notification.EXTRA_TITLE).toString()
    private fun Notification.actionTitles() = actions?.map { it.title.toString() } ?: emptyList()

    @Test
    fun `ringing goes foreground with Stop, Snooze and Join when the event has a link`() {
        val service = startWith(alert("a", NOW, title = "Sprint planning", joinUrl = link)).get()
        val n = shadowOf(service).lastForegroundNotification
        assertEquals(NotificationFactory.CHANNEL_RINGING, n.channelId)
        assertEquals(Notification.CATEGORY_ALARM, n.category)
        assertNotNull(n.fullScreenIntent)
        assertEquals(listOf("Stop", "Snooze", "Join"), n.actionTitles())
        assertEquals(listOf("a"), RingingSession.alerts.map { it.id })
    }

    @Test
    fun `without a link the third action is Dismiss all`() {
        val service = startWith(alert("a", NOW)).get()
        assertEquals(listOf("Stop", "Snooze", "Dismiss all"), shadowOf(service).lastForegroundNotification.actionTitles())
    }

    @Test
    fun `a coalesced session reads N meetings starting with Stop, Snooze all and Dismiss all`() {
        val service = startWith(alert("a", NOW, group = "G", joinUrl = link), alert("b", NOW, group = "G")).get()
        val n = shadowOf(service).lastForegroundNotification
        assertEquals("2 meetings starting", n.title())
        assertEquals(listOf("Stop", "Snooze all", "Dismiss all"), n.actionTitles())
    }

    @Test
    fun `the service stops when the session empties`() {
        val service = startWith(alert("a", NOW)).get()
        RingingSession.remove(listOf("a"))
        assertTrue(shadowOf(service).isStoppedBySelf)
    }

    @Test
    fun `the ring timeout logs missed and posts a Missed notification`() {
        val service = startWith(alert("a", NOW, title = "Design review")).get() // ringTimeoutSec = 120
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofSeconds(121))
        assertEquals(listOf(EngineEventType.MISSED), EventQueue(context).drain().map { it.type })
        assertNotNull(shadowOf(manager).getNotification(NotificationFactory.missedId("a")))
        assertTrue(PlanStore(context).read().presented.isEmpty())
        assertTrue(shadowOf(service).isStoppedBySelf)
    }

    @Test
    fun `a broken custom tone still rings`() {
        // content://missing has no MediaInfo, so opening it throws and the default alarm tone is used.
        val service = startWith(alert("a", NOW, toneUri = "content://missing/tone")).get()
        assertNotNull(shadowOf(service).lastForegroundNotification)
        assertEquals(listOf("a"), RingingSession.alerts.map { it.id })
    }
}
