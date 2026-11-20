package io.github.fifothehein.tminus.engine

import android.app.AlarmManager
import android.app.Application
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.shadows.ShadowAlarmManager

/**
 * An alarm that falls due while the phone reboots, followed by the sync that boot starts. The
 * receivers use the real clock, so every time here is relative to [now].
 */
@RunWith(RobolectricTestRunner::class)
class BootRecoveryAcrossSyncTest {
    private val context: Context = RuntimeEnvironment.getApplication()
    private val app: Application = RuntimeEnvironment.getApplication()
    private val alarmManager: AlarmManager = context.getSystemService(AlarmManager::class.java)
    private val manager: NotificationManager = context.getSystemService(NotificationManager::class.java)
    private val now = System.currentTimeMillis()
    private lateinit var store: PlanStore

    // A meeting that began 28 s ago and runs for 30 min. Its alarm was due a minute before it began.
    private val meetingStart = now - 28_000
    private val alarm = alert("alarm", meetingStart - MINUTE_MS, occurrenceKey = "src|meeting", start = meetingStart)
    private val headsUp = alert("headsUp", meetingStart - 10 * MINUTE_MS, Strength.HEADS_UP, occurrenceKey = "src|meeting", start = meetingStart)
    private val later = alert("later", now + HOUR, occurrenceKey = "src|later")

    @Before
    fun setUp() {
        ShadowAlarmManager.setCanScheduleExactAlarms(true)
        store = PlanStore(context).also { it.clear() }
        EventQueue(context).drain()
        RingingSession.clear()
        manager.cancelAll()
        shadowOf(alarmManager).scheduledAlarms.toList().forEach { scheduled -> scheduled.operation?.let(alarmManager::cancel) }
        while (shadowOf(app).nextStartedService != null) Unit
    }

    /** The alarms AlarmManager holds that would ring [alertId]: its own alarm, or a retry of a refused start. */
    private fun alarmsThatRing(alertId: String) = shadowOf(alarmManager).scheduledAlarms.filter {
        val intent = shadowOf(it.operation).savedIntent
        when (intent.action) {
            AlarmReceiver.ACTION_FIRE -> intent.getStringExtra(AlarmReceiver.EXTRA_ALERT_ID) == alertId
            AlarmReceiver.ACTION_RETRY_RINGING -> alertId in intent.getStringArrayListExtra(AlarmReceiver.EXTRA_ALERT_IDS).orEmpty()
            else -> false
        }
    }

    /** What the headless sync runs: the alarm_engine channel's engine, whose service start Android refuses. */
    private fun syncEngineWhoseServiceStartIsRefused(): EngineActions {
        val presenter = AndroidAlertPresenter(context, store, NotificationFactory(context)) { _, _ ->
            throw IllegalStateException("not allowed") // what ForegroundServiceStartNotAllowedException extends
        }
        return EngineActions(context, presenter, store, AlarmScheduler(context, store))
    }

    @Test
    fun `an alarm due during a reboot still rings after a sync replaces the plan`() {
        store.write(EngineState(plan = listOf(alarm, later))) // armed before the reboot; AlarmManager lost it
        for (action in BootReceiver.BOOT_ACTIONS) BootReceiver().onReceive(context, Intent(action))
        val recovery = alarmsThatRing("alarm").single() // boot recovery holds it for the end of the window
        assertTrue(recovery.triggerAtMs >= now + EngineActions.RECOVERY_DELAY_MS)

        // The sync that boot starts replaces the plan. It lists the running meeting's alerts, past ones too.
        // It runs after the boot broadcast's FGS allow-list ended, so Android refuses its service start.
        syncEngineWhoseServiceStartIsRefused().applyPlan(listOf(headsUp, alarm, later)) {} // what it left armed is asserted below

        assertNotNull(shadowOf(manager).getNotification(NotificationFactory.headsUpId(alarm.coalesceGroup)))
        val left = alarmsThatRing("alarm")
        assertTrue("nothing is left to ring the alarm", left.isNotEmpty())
        AlarmReceiver().onReceive(context, shadowOf(left.minBy { it.triggerAtMs }.operation).savedIntent)
        val service = shadowOf(app).nextStartedService
        assertNotNull("the alarm never rang", service)
        assertEquals(RingingService::class.java.name, service.component!!.className)
        assertEquals(arrayListOf("alarm"), service.getStringArrayListExtra(RingingService.EXTRA_ALERT_IDS))
    }

    @Test
    fun `a ringing start that Android refuses is retried through AlarmManager`() {
        store.write(EngineState(presented = listOf(alarm))) // EngineActions.fire has moved it here before it presents it
        val presenter = AndroidAlertPresenter(context, store, NotificationFactory(context)) { _, _ ->
            throw IllegalStateException("not allowed")
        }

        presenter.present(listOf(alarm))

        assertNotNull(shadowOf(manager).getNotification(NotificationFactory.headsUpId(alarm.coalesceGroup)))
        val retry = alarmsThatRing("alarm").single()
        assertEquals(AlarmReceiver.ACTION_RETRY_RINGING, shadowOf(retry.operation).savedIntent.action)
        assertTrue("it retries after the boot window, at ${retry.triggerAtMs - now} ms", retry.triggerAtMs >= now + EngineActions.RECOVERY_DELAY_MS)
    }

    @Test
    fun `a retry that is refused too shows the heads-up and is not retried again`() {
        store.write(EngineState(presented = listOf(alarm)))
        val retrying = AndroidAlertPresenter(context, store, NotificationFactory(context), retryRefusedStart = false) { _, _ ->
            throw IllegalStateException("not allowed")
        }

        retrying.present(listOf(alarm))

        assertNotNull(shadowOf(manager).getNotification(NotificationFactory.headsUpId(alarm.coalesceGroup)))
        assertTrue(alarmsThatRing("alarm").isEmpty())
    }

    @Test
    fun `the retry AlarmReceiver makes is not retried when Android refuses it too`() {
        store.write(EngineState(presented = listOf(alarm)))
        AlarmReceiver.startRetry = { _, _ -> throw IllegalStateException("not allowed") }
        try {
            AlarmReceiver().onReceive(context, AlarmReceiver.retryRingingIntent(context, listOf("alarm")))
        } finally {
            AlarmReceiver.startRetry = AlarmReceiver.DEFAULT_START_RETRY
        }

        assertNotNull(shadowOf(manager).getNotification(NotificationFactory.headsUpId(alarm.coalesceGroup)))
        assertTrue(alarmsThatRing("alarm").isEmpty())
    }
}
