package io.github.fifothehein.tminus.engine

import android.app.Application
import android.app.Notification
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.AudioManager
import android.os.Looper
import android.os.Vibrator
import android.provider.Settings
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
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
import org.robolectric.shadows.ShadowPowerManager
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

    private fun vibrating() = shadowOf(context.getSystemService(Vibrator::class.java)).isVibrating

    /** The ringing notification's Stop, as SystemUI sends it, carrying [ids]. */
    private fun stopFromNotification(vararg ids: String) = NotificationActionReceiver().onReceive(
        context,
        NotificationActionReceiver.intent(
            context,
            NotificationActionReceiver.ACTION_DISMISS,
            arrayListOf(*ids),
            NotificationActionReceiver.NO_NOTIFICATION_ID,
        ),
    )

    private fun assertSilenced(service: RingingService) {
        assertFalse("still sounding", service.isSounding)
        assertTrue("not stopped", shadowOf(service).isStoppedBySelf)
        assertNotNull("audio focus kept", shadowOf(context.getSystemService(AudioManager::class.java)).lastAbandonedAudioFocusRequest)
        assertFalse("still vibrating", vibrating())
        assertTrue("session not empty", RingingSession.alerts.isEmpty())
    }

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
    fun `ringing takes transient alarm audio focus and gives it back when it stops`() {
        val audio = shadowOf(context.getSystemService(AudioManager::class.java))
        startWith(alert("a", NOW))
        val request = audio.lastAudioFocusRequest
        assertNotNull(request)
        assertEquals(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT, request.durationHint)
        assertEquals(AudioAttributes.USAGE_ALARM, request.audioFocusRequest.audioAttributes.usage)
        assertNull(audio.lastAbandonedAudioFocusRequest)

        RingingSession.remove(listOf("a"))

        assertSame(request.audioFocusRequest, audio.lastAbandonedAudioFocusRequest)
    }

    @Test
    fun `an alarm denied audio focus still rings`() {
        shadowOf(context.getSystemService(AudioManager::class.java)).setNextFocusRequestResponse(AudioManager.AUDIOFOCUS_REQUEST_FAILED)
        val service = startWith(alert("a", NOW)).get()
        assertTrue(service.isSounding)
        assertEquals(listOf("a"), RingingSession.alerts.map { it.id })
    }

    @Test
    fun `stopping covers only the starts already handled, so a newly fired alarm still rings`() {
        val a = alert("a", NOW)
        val b = alert("b", NOW + 30_000, title = "Design review", group = "B")
        PlanStore(context).write(EngineState(presented = listOf(a, b)))
        fun ring(vararg ids: String) = Intent(context, RingingService::class.java)
            .putStringArrayListExtra(RingingService.EXTRA_ALERT_IDS, arrayListOf(*ids))
        val controller = Robolectric.buildService(RingingService::class.java, ring("a")).create().startCommand(0, 1)
        val service = controller.get()

        // b's alarm has called startForegroundService (start id 2 is queued) when the user stops a.
        RingingSession.remove(listOf("a"))
        // stopSelfResult(1) fails on a device while start 2 is pending; stopSelf() would not.
        assertEquals(1, shadowOf(service).stopSelfResultId)
        assertEquals(0, shadowOf(service).stopSelfId)

        controller.withIntent(ring("b")).startCommand(0, 2)

        assertEquals(listOf("b"), RingingSession.alerts.map { it.id })
        assertTrue(service.isSounding)
        assertTrue(shadowOf(service).lastForegroundNotification.title().endsWith("Design review"))
    }

    @Test
    fun `the ring timeout and wake lock restart from the newest alert's ringTimeoutSec`() {
        val a = alert("a", NOW) // ringTimeoutSec = 120
        val b = alert("b", NOW + 30_000, group = "B").let { it.copy(sound = it.sound.copy(ringTimeoutSec = 300)) }
        PlanStore(context).write(EngineState(presented = listOf(a, b)))
        fun ring(id: String) = Intent(context, RingingService::class.java)
            .putStringArrayListExtra(RingingService.EXTRA_ALERT_IDS, arrayListOf(id))
        val controller = Robolectric.buildService(RingingService::class.java, ring("a")).create().startCommand(0, 1)
        val looper = shadowOf(Looper.getMainLooper())
        looper.idleFor(Duration.ofSeconds(60))

        controller.withIntent(ring("b")).startCommand(0, 2) // b joins the session
        looper.idleFor(Duration.ofSeconds(200)) // past a's 120 s, inside b's 300 s

        assertTrue(EventQueue(context).peek().none { it.type == EngineEventType.MISSED })
        assertTrue(ShadowPowerManager.getLatestWakeLock().isHeld)
        looper.idleFor(Duration.ofSeconds(101))
        assertEquals(setOf("a", "b"), EventQueue(context).drain().filter { it.type == EngineEventType.MISSED }.map { it.alertId }.toSet())
    }

    @Test
    fun `a heads-up joining a ringing group restarts the ring timeout and wake lock from its own ringTimeoutSec`() {
        val a = alert("a", NOW, group = "G") // ringTimeoutSec = 120
        val h = alert("h", NOW + 2_000, strength = Strength.HEADS_UP, group = "G")
            .let { it.copy(sound = it.sound.copy(ringTimeoutSec = 300)) }
        PlanStore(context).write(EngineState(presented = listOf(a, h))) // fire has moved h to presented
        val app = context as Application
        val controller = Robolectric.buildService(
            RingingService::class.java,
            Intent(context, RingingService::class.java).putStringArrayListExtra(RingingService.EXTRA_ALERT_IDS, arrayListOf("a")),
        ).create().startCommand(0, 1)
        val looper = shadowOf(Looper.getMainLooper())
        looper.idleFor(Duration.ofSeconds(60))

        AndroidAlertPresenter(app).present(listOf(h)) // h fires into G while a rings: it joins the session
        controller.withIntent(shadowOf(app).nextStartedService).startCommand(0, 2)
        assertEquals(setOf("a", "h"), RingingSession.ids)

        looper.idleFor(Duration.ofSeconds(200)) // 140 s after the join: past a's 120 s, inside h's 300 s
        assertTrue(EventQueue(context).peek().none { it.type == EngineEventType.MISSED })
        assertTrue(ShadowPowerManager.getLatestWakeLock().isHeld) // a's lock (120 s + 30 s) would be over by now
        looper.idleFor(Duration.ofSeconds(161)) // 301 s after the join: past h's 300 s
        assertEquals(setOf("a", "h"), EventQueue(context).drain().filter { it.type == EngineEventType.MISSED }.map { it.alertId }.toSet())
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

    @Test
    fun `Stop silences even when the alert is no longer presented`() {
        val service = startWith(alert("a", NOW)).get()
        assertTrue(service.isSounding)
        assertTrue(vibrating())
        PlanStore(context).write(EngineState()) // pruned by applyPlan, or the state file was unreadable

        stopFromNotification("a")

        assertSilenced(service)
    }

    @Test
    fun `the ring timeout stops ringing even when the alert is no longer presented`() {
        val service = startWith(alert("a", NOW)).get() // ringTimeoutSec = 120
        PlanStore(context).write(EngineState())

        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofSeconds(121))

        assertSilenced(service)
    }

    @Test
    fun `ringing Stop with stale ids silences the whole session`() {
        val a = alert("a", NOW)
        val b = alert("b", NOW + 30_000, group = "B")
        PlanStore(context).write(EngineState(presented = listOf(a, b)))
        fun ring(id: String) = Intent(context, RingingService::class.java)
            .putStringArrayListExtra(RingingService.EXTRA_ALERT_IDS, arrayListOf(id))
        val controller = Robolectric.buildService(RingingService::class.java, ring("a")).create().startCommand(0, 1)
        controller.withIntent(ring("b")).startCommand(0, 2) // b joins after the Stop below was posted for a
        EventQueue(context).drain()

        stopFromNotification("a")

        assertSilenced(controller.get())
        assertEquals(setOf("a", "b"), EventQueue(context).drain().filter { it.type == EngineEventType.DISMISSED }.map { it.alertId }.toSet())
        assertTrue(PlanStore(context).read().presented.isEmpty())
    }

    @Test
    fun `removing the ringing notification while ringing posts it again`() {
        val service = startWith(alert("a", NOW)).get()
        val posted = shadowOf(service).lastForegroundNotification
        manager.cancel(NotificationFactory.RINGING_NOTIFICATION_ID) // the user swiped it away (Android 14+)
        assertNull(shadowOf(manager).getNotification(NotificationFactory.RINGING_NOTIFICATION_ID))

        posted.deleteIntent.send()
        shadowOf(Looper.getMainLooper()).idle()

        val again = shadowOf(manager).getNotification(NotificationFactory.RINGING_NOTIFICATION_ID)
        assertNotNull(again)
        assertEquals("Stop", again.actionTitles().first())
        assertTrue(service.isSounding)
    }

    @Test
    fun `a removed ringing notification is not posted again once nothing rings`() {
        val service = startWith(alert("a", NOW)).get()
        val posted = shadowOf(service).lastForegroundNotification
        RingingSession.clear()
        manager.cancel(NotificationFactory.RINGING_NOTIFICATION_ID)

        posted.deleteIntent.send()
        shadowOf(Looper.getMainLooper()).idle()

        assertNull(shadowOf(manager).getNotification(NotificationFactory.RINGING_NOTIFICATION_ID))
    }
}
