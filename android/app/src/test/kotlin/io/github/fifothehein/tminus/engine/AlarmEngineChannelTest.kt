package io.github.fifothehein.tminus.engine

import android.app.AlarmManager
import android.app.Application
import android.content.Intent
import android.os.Looper
import android.provider.Settings
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
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
import org.robolectric.shadows.ShadowAlarmManager

@RunWith(RobolectricTestRunner::class)
class AlarmEngineChannelTest {
    private val app: Application = RuntimeEnvironment.getApplication()
    private lateinit var store: PlanStore
    private lateinit var channel: AlarmEngineChannel

    private class Recorded : MethodChannel.Result {
        var value: Any? = null
        var errorCode: String? = null
        var notImplemented = false
        override fun success(result: Any?) { value = result }
        override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) { this.errorCode = errorCode }
        override fun notImplemented() { notImplemented = true }
    }

    private fun call(method: String, args: Any? = null): Recorded =
        Recorded().also { channel.onMethodCall(MethodCall(method, args), it) }

    private fun dartAlert(id: String, fireAt: Long): Map<String, Any?> = mapOf(
        "id" to id,
        "occurrenceKey" to "src|$id|occ",
        "fireAtUtcMs" to fireAt,
        "offsetMinutes" to 1,
        "strength" to "alarm",
        "sound" to mapOf("toneUri" to null, "vibrate" to true, "gradualVolume" to true, "ringTimeoutSec" to 120),
        "event" to mapOf(
            "title" to "Meeting $id",
            "startUtcMs" to fireAt + MINUTE_MS,
            "endUtcMs" to fireAt + HOUR,
            "location" to null,
            "joinUrl" to null,
            "color" to 4285178101L,
        ),
        "coalesceGroup" to CoalesceGroups.groupFor(fireAt),
    )

    @Before
    fun setUp() {
        ShadowAlarmManager.setCanScheduleExactAlarms(true)
        store = PlanStore(app).also { it.clear() }
        EventQueue(app).drain()
        channel = AlarmEngineChannel(app, store, AlarmScheduler(app, store) { NOW }) { NOW }
    }

    @Test
    fun `applyPlan returns the counts map and stores the plan`() {
        val r = call("applyPlan", mapOf("version" to 1, "alerts" to listOf(dartAlert("a", NOW + HOUR), dartAlert("b", NOW + 2 * HOUR))))
        assertEquals(mapOf("armed" to 2, "cancelled" to 0, "kept" to 0), r.value)
        assertEquals(listOf("a", "b"), store.read().plan.map { it.id })
    }

    @Test
    fun `a bad plan is rejected and the old plan stays`() {
        call("applyPlan", mapOf("version" to 1, "alerts" to listOf(dartAlert("a", NOW + HOUR))))
        assertEquals("bad_args", call("applyPlan", mapOf("version" to 99, "alerts" to emptyList<Any>())).errorCode)
        assertEquals("bad_args", call("applyPlan", null).errorCode)
        assertEquals(listOf("a"), store.read().plan.map { it.id })
    }

    @Test
    fun `getHealth reports every field and at most five upcoming alerts`() {
        call("applyPlan", mapOf("version" to 1, "alerts" to (1..6).map { dartAlert("a$it", NOW + it * MINUTE_MS) }))
        @Suppress("UNCHECKED_CAST")
        val health = call("getHealth").value as Map<String, Any?>
        val flags = listOf("notificationsEnabled", "canUseFullScreenIntent", "canScheduleExactAlarms", "ignoringBatteryOptimizations", "alarmStreamMuted")
        assertEquals((flags + "upcoming").toSet(), health.keys)
        flags.forEach { assertTrue(it, health[it] is Boolean) }
        @Suppress("UNCHECKED_CAST")
        val upcoming = health["upcoming"] as List<Map<String, Any?>>
        assertEquals(listOf("a1", "a2", "a3", "a4", "a5"), upcoming.map { it["id"] })
        assertEquals(mapOf("id" to "a1", "fireAtUtcMs" to NOW + MINUTE_MS, "strength" to "alarm", "title" to "Meeting a1"), upcoming.first())
    }

    @Test
    fun `testAlarm schedules a test alert after the delay`() {
        val r = call("testAlarm", mapOf("strength" to "alarm", "delaySec" to 5))
        assertNull(r.value)
        assertNull(r.errorCode)
        val test = store.read().tests.single()
        assertEquals("test-$NOW", test.id)
        assertEquals("test|$NOW", test.occurrenceKey)
        assertEquals(NOW + 5_000, test.fireAtUtcMs)
        assertEquals(Strength.ALARM, test.strength)
        assertEquals("Test alarm", test.event.title)
        assertEquals(NOW + 5_000 + MINUTE_MS, test.event.startUtcMs)
        val alarm = shadowOf(app.getSystemService(AlarmManager::class.java)).scheduledAlarms.single()
        assertEquals(NOW + 5_000, alarm.triggerAtMs)
        assertNotNull(alarm.alarmClockInfo)
    }

    @Test
    fun `testAlarm for a heads-up uses the heads-up title`() {
        call("testAlarm", mapOf("strength" to "headsUp", "delaySec" to 60))
        assertEquals("Test heads-up", store.read().tests.single().event.title)
        assertEquals("bad_args", call("testAlarm", mapOf("strength" to "loud", "delaySec" to 5)).errorCode)
    }

    @Test
    fun `openPermissionSettings opens the right screen for each kind`() {
        val expected = mapOf(
            "notifications" to Settings.ACTION_APP_NOTIFICATION_SETTINGS,
            "fullScreenIntent" to Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT, // SDK 34 under Robolectric
            "exactAlarm" to Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM,
            "batteryOptimization" to Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS,
            "alarmVolume" to Settings.ACTION_SOUND_SETTINGS,
        )
        for ((kind, action) in expected) {
            call("openPermissionSettings", mapOf("kind" to kind))
            val started: Intent = shadowOf(app).nextStartedActivity
            assertEquals(kind, action, started.action)
            assertTrue(kind, started.flags and Intent.FLAG_ACTIVITY_NEW_TASK != 0)
        }
        assertEquals("bad_args", call("openPermissionSettings", mapOf("kind" to "camera")).errorCode)
    }

    @Test
    fun `drainEvents returns queued events as maps and clears the queue`() {
        val event = EngineEvent(EngineEventType.FIRED, "a", "src|a|occ", NOW + MINUTE_MS, NOW)
        EventQueue(app).append(event)
        assertEquals(listOf(event.toMap()), call("drainEvents").value)
        assertEquals(emptyList<Any>(), call("drainEvents").value)
    }

    private class Sink : EventChannel.EventSink {
        val received = mutableListOf<Any?>()
        override fun success(event: Any?) { received.add(event) }
        override fun error(errorCode: String?, errorMessage: String?, errorDetails: Any?) = Unit
        override fun endOfStream() = Unit
    }

    @Test
    fun `live events reach every registered engine and cancelling one keeps the other`() {
        val other = AlarmEngineChannel(app, store, AlarmScheduler(app, store) { NOW }) { NOW } // e.g. Plan 4's headless engine
        val mine = Sink()
        val theirs = Sink()
        channel.onListen(null, mine)
        other.onListen(null, theirs)
        val first = EngineEvent(EngineEventType.FIRED, "a", "src|a|occ", NOW + MINUTE_MS, NOW)
        val second = first.copy(type = EngineEventType.DISMISSED)

        EngineEvents.emit(app, first)
        shadowOf(Looper.getMainLooper()).idle()
        assertEquals(listOf<Any?>(first.toMap()), mine.received)
        assertEquals(listOf<Any?>(first.toMap()), theirs.received)

        other.onCancel(null)
        EngineEvents.emit(app, second)
        shadowOf(Looper.getMainLooper()).idle()
        assertEquals(listOf<Any?>(first.toMap(), second.toMap()), mine.received)
        assertEquals(listOf<Any?>(first.toMap()), theirs.received)
        channel.onCancel(null)
    }

    @Test
    fun `unknown methods are not implemented`() {
        assertTrue(call("queryDeviceCalendars").notImplemented)
    }
}
