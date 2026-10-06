package io.github.fifothehein.tminus.engine

import android.app.AlarmManager
import android.app.Application
import android.app.NotificationManager
import android.content.BroadcastReceiver
import android.content.ComponentName
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

@RunWith(RobolectricTestRunner::class)
class RearmReceiversTest {
    private val context: Context = RuntimeEnvironment.getApplication()
    private val alarmManager: AlarmManager = context.getSystemService(AlarmManager::class.java)
    private val app: Application = RuntimeEnvironment.getApplication()
    private val manager: NotificationManager = context.getSystemService(NotificationManager::class.java)
    private val now = System.currentTimeMillis() // the receivers use the real clock
    private lateinit var store: PlanStore

    @Before
    fun setUp() {
        ShadowAlarmManager.setCanScheduleExactAlarms(true)
        store = PlanStore(context).also { it.clear() }
    }

    private fun scheduledIds(): Set<String?> = shadowOf(alarmManager).scheduledAlarms
        .map { shadowOf(it.operation).savedIntent.getStringExtra(AlarmReceiver.EXTRA_ALERT_ID) }
        .toSet()

    private fun assertRearms(receiver: BroadcastReceiver, action: String) {
        val scheduler = AlarmScheduler(context, store)
        listOf("f", "s:s", "p").forEach(scheduler::cancel)
        store.write(
            EngineState(
                plan = listOf(alert("f", now + HOUR), alert("p", now - HOUR)),
                snoozes = listOf(alert("s:s", now + 5 * MINUTE_MS)),
            ),
        )
        receiver.onReceive(context, Intent(action))
        assertEquals(action, setOf("f", "s:s"), scheduledIds())
        assertEquals(action, listOf("f"), store.read().plan.map { it.id })
    }

    @Test
    fun `every boot trigger re-arms future alerts and drops past ones`() {
        BootReceiver.ACTIONS.forEach { assertRearms(BootReceiver(), it) }
    }

    @Test
    fun `every time trigger re-arms future alerts and drops past ones`() {
        TimeChangeReceiver.ACTIONS.forEach { assertRearms(TimeChangeReceiver(), it) }
    }

    @Test
    fun `after a reboot or an update an overdue alarm rings and one whose event ended is reported missed`() {
        for (action in BootReceiver.ACTIONS) {
            store.clear()
            EventQueue(context).drain()
            RingingSession.clear()
            manager.cancelAll()
            while (shadowOf(app).nextStartedService != null) Unit
            val due = alert("due", now - MINUTE_MS) // the phone was off when it was due; the event runs until now + 30 min
            val ended = alert("ended", now - HOUR)
            store.write(EngineState(plan = listOf(due, ended)))

            BootReceiver().onReceive(context, Intent(action))

            assertEquals(action, listOf("due"), store.read().presented.map { it.id })
            val ringing = shadowOf(app).nextStartedService
            assertEquals(action, RingingService::class.java.name, ringing.component!!.className)
            assertEquals(action, arrayListOf("due"), ringing.getStringArrayListExtra(RingingService.EXTRA_ALERT_IDS))
            assertNotNull(action, shadowOf(manager).getNotification(NotificationFactory.missedId("ended")))
            assertEquals(
                action,
                listOf(EngineEventType.MISSED to "ended", EngineEventType.FIRED to "due"),
                EventQueue(context).drain().map { it.type to it.alertId },
            )
            assertTrue(action, store.read().scheduled.isEmpty())
        }
    }

    @Test
    fun `after a reboot or an update a presented alarm rings again and one whose event ended is reported missed`() {
        for (action in BootReceiver.ACTIONS) {
            store.clear()
            EventQueue(context).drain()
            RingingSession.clear()
            manager.cancelAll()
            while (shadowOf(app).nextStartedService != null) Unit
            val ringing = alert("ringing", now - MINUTE_MS) // was ringing when the phone went off; the event runs until now + 30 min
            val ended = alert("ended", now - HOUR)
            store.write(EngineState(presented = listOf(ringing, ended)))

            BootReceiver().onReceive(context, Intent(action))

            val service = shadowOf(app).nextStartedService
            assertNotNull(action, service)
            assertEquals(action, arrayListOf("ringing"), service.getStringArrayListExtra(RingingService.EXTRA_ALERT_IDS))
            assertNotNull(action, shadowOf(manager).getNotification(NotificationFactory.missedId("ended")))
            assertEquals(action, listOf(EngineEventType.MISSED to "ended"), EventQueue(context).drain().map { it.type to it.alertId })
            assertEquals(action, listOf("ringing"), store.read().presented.map { it.id })
        }
    }

    @Test
    fun `other broadcasts are ignored`() {
        store.write(EngineState(plan = listOf(alert("f", now + HOUR))))
        BootReceiver().onReceive(context, Intent(Intent.ACTION_SCREEN_ON))
        TimeChangeReceiver().onReceive(context, Intent(Intent.ACTION_SCREEN_ON))
        assertTrue(scheduledIds().isEmpty())
    }

    @Test
    fun `the manifest registers every trigger and the engine components are direct-boot aware`() {
        val pm = context.packageManager
        val triggers = BootReceiver.ACTIONS.associateWith { BootReceiver::class.java } +
            TimeChangeReceiver.ACTIONS.associateWith { TimeChangeReceiver::class.java }
        for ((action, receiver) in triggers) {
            val found = pm.queryBroadcastReceivers(Intent(action).setPackage(context.packageName), 0).map { it.activityInfo.name }
            assertTrue(action, receiver.name in found)
        }
        listOf(BootReceiver::class.java, TimeChangeReceiver::class.java, AlarmReceiver::class.java, NotificationActionReceiver::class.java)
            .forEach { assertTrue(it.simpleName, pm.getReceiverInfo(ComponentName(context, it), 0).directBootAware) }
        assertTrue(pm.getServiceInfo(ComponentName(context, RingingService::class.java), 0).directBootAware)
        assertTrue(pm.getActivityInfo(ComponentName(context, AlarmActivity::class.java), 0).directBootAware)
    }
}
