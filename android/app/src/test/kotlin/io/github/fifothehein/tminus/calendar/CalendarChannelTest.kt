package io.github.fifothehein.tminus.calendar

import android.Manifest
import android.app.Application
import android.provider.CalendarContract
import android.provider.CalendarContract.Calendars
import android.provider.CalendarContract.Instances
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.github.fifothehein.tminus.engine.AlarmEngineChannel
import io.github.fifothehein.tminus.engine.AlarmScheduler
import io.github.fifothehein.tminus.engine.PlanStore
import org.junit.Assert.assertEquals
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf

/** The two calls Plan 4 adds to `alarm_engine` (roadmap §3). */
@RunWith(RobolectricTestRunner::class)
class CalendarChannelTest {
    private val app: Application = RuntimeEnvironment.getApplication()
    private lateinit var provider: FakeCalendarProvider
    private lateinit var channel: AlarmEngineChannel

    private class Recorded : MethodChannel.Result {
        var value: Any? = null
        var errorCode: String? = null
        override fun success(result: Any?) { value = result }
        override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) { this.errorCode = errorCode }
        override fun notImplemented() = throw AssertionError("not implemented")
    }

    private fun call(method: String, args: Any? = null): Recorded =
        Recorded().also { channel.onMethodCall(MethodCall(method, args), it) }

    @Before
    fun setUp() {
        provider = Robolectric.buildContentProvider(FakeCalendarProvider::class.java).create(CalendarContract.AUTHORITY).get()
        provider.calendars += mapOf(
            Calendars._ID to 3L,
            Calendars.CALENDAR_DISPLAY_NAME to "Work",
            Calendars.ACCOUNT_NAME to "me@example.com",
            Calendars.CALENDAR_COLOR to 0xFF6AA0F5.toInt(),
            Calendars.VISIBLE to 1,
        )
        provider.instances += mapOf(
            Instances.EVENT_ID to 10L,
            Instances.CALENDAR_ID to 3L,
            Instances.BEGIN to 1_000L,
            Instances.END to 2_000L,
            Instances.ALL_DAY to 0,
            Instances.TITLE to "Standup",
            Instances.AVAILABILITY to Instances.AVAILABILITY_BUSY,
            Instances.SELF_ATTENDEE_STATUS to 0,
        )
        val store = PlanStore(app).also { it.clear() }
        channel = AlarmEngineChannel(app, store, AlarmScheduler(app, store))
    }

    @Test
    fun `queryDeviceCalendars lists the calendars`() {
        shadowOf(app).grantPermissions(Manifest.permission.READ_CALENDAR)
        val calendars = call("queryDeviceCalendars").value as List<*>
        assertEquals("Work", (calendars.single() as Map<*, *>)["name"])
    }

    @Test
    fun `queryInstances passes the ids and window through`() {
        shadowOf(app).grantPermissions(Manifest.permission.READ_CALENDAR)
        val rows = call("queryInstances", mapOf("calendarIds" to listOf("3"), "fromUtcMs" to 0, "toUtcMs" to 5_000L)).value as List<*>
        assertEquals("Standup", (rows.single() as Map<*, *>)["title"])
        assertEquals(listOf("instances", "when", "0", "5000"), provider.instanceUris.single().pathSegments)
    }

    @Test
    fun `reader errors keep their code`() {
        shadowOf(app).denyPermissions(Manifest.permission.READ_CALENDAR)
        assertEquals("permission_denied", call("queryDeviceCalendars").errorCode)
        shadowOf(app).grantPermissions(Manifest.permission.READ_CALENDAR)
        val missing = call("queryInstances", mapOf("calendarIds" to listOf("99"), "fromUtcMs" to 0, "toUtcMs" to 1))
        assertEquals("calendar_missing", missing.errorCode)
    }

    @Test
    fun `bad queryInstances arguments are bad_args`() {
        shadowOf(app).grantPermissions(Manifest.permission.READ_CALENDAR)
        assertEquals("bad_args", call("queryInstances", mapOf("fromUtcMs" to 0, "toUtcMs" to 1)).errorCode)
        assertEquals("bad_args", call("queryInstances", mapOf("calendarIds" to emptyList<String>(), "fromUtcMs" to 0, "toUtcMs" to 1)).errorCode)
    }
}
