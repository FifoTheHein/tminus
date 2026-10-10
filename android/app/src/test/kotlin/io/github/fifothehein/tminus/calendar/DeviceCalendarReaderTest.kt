package io.github.fifothehein.tminus.calendar

import android.Manifest
import android.app.Application
import android.content.ContentProvider
import android.content.ContentValues
import android.database.Cursor
import android.database.MatrixCursor
import android.net.Uri
import android.provider.CalendarContract
import android.provider.CalendarContract.Calendars
import android.provider.CalendarContract.Instances
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf

/** Stands in for the calendar provider: rows keyed by column name, filtered like the real one. */
class FakeCalendarProvider : ContentProvider() {
    val calendars = mutableListOf<Map<String, Any?>>()
    val instances = mutableListOf<Map<String, Any?>>()
    val instanceUris = mutableListOf<Uri>()

    override fun onCreate() = true

    override fun query(uri: Uri, projection: Array<String>?, selection: String?, args: Array<String>?, sort: String?): Cursor {
        val columns = projection!!
        val rows = when (uri.pathSegments.first()) {
            "calendars" -> calendars
            "instances" -> {
                instanceUris += uri
                val ids = args!!.toSet()
                instances.filter { it[Instances.CALENDAR_ID].toString() in ids }
            }
            else -> emptyList()
        }
        return MatrixCursor(columns).apply { rows.forEach { row -> addRow(columns.map { row[it] }) } }
    }

    override fun getType(uri: Uri): String? = null
    override fun insert(uri: Uri, values: ContentValues?): Uri? = null
    override fun delete(uri: Uri, selection: String?, args: Array<String>?) = 0
    override fun update(uri: Uri, values: ContentValues?, selection: String?, args: Array<String>?) = 0
}

@RunWith(RobolectricTestRunner::class)
class DeviceCalendarReaderTest {
    private val app: Application = RuntimeEnvironment.getApplication()
    private lateinit var provider: FakeCalendarProvider
    private lateinit var reader: DeviceCalendarReader

    @Before
    fun setUp() {
        provider = Robolectric.buildContentProvider(FakeCalendarProvider::class.java).create(CalendarContract.AUTHORITY).get()
        shadowOf(app).grantPermissions(Manifest.permission.READ_CALENDAR)
        reader = DeviceCalendarReader(app)
        provider.calendars += mapOf(
            Calendars._ID to 3L,
            Calendars.CALENDAR_DISPLAY_NAME to "Work",
            Calendars.ACCOUNT_NAME to "me@example.com",
            Calendars.CALENDAR_COLOR to 0x6AA0F5, // no alpha, as some providers store it
            Calendars.VISIBLE to 1,
        )
    }

    private fun instance(
        eventId: Long,
        calendarId: Long = 3,
        originalId: String? = null,
        originalInstanceTime: Long? = null,
        rrule: String? = null,
        status: Int? = null,
    ) = mapOf(
        Instances.EVENT_ID to eventId,
        Instances.CALENDAR_ID to calendarId,
        Instances.BEGIN to 1_791_000_000_000L,
        Instances.END to 1_791_001_800_000L,
        Instances.ALL_DAY to 0,
        Instances.TITLE to "Sprint planning",
        Instances.EVENT_LOCATION to "Room 4",
        Instances.DESCRIPTION to "Join: https://teams.microsoft.com/l/meetup-join/abc",
        Instances.ORGANIZER to "thandi@example.com",
        Instances.AVAILABILITY to Instances.AVAILABILITY_TENTATIVE,
        Instances.SELF_ATTENDEE_STATUS to CalendarContract.Attendees.ATTENDEE_STATUS_DECLINED,
        Instances.STATUS to status,
        Instances.ORIGINAL_ID to originalId,
        Instances.ORIGINAL_INSTANCE_TIME to originalInstanceTime,
        Instances.RRULE to rrule,
        Instances.RDATE to null,
    )

    @Test
    fun `calendars are listed with an opaque ARGB colour`() {
        assertEquals(
            listOf(mapOf("id" to "3", "name" to "Work", "accountName" to "me@example.com", "color" to 0xFF6AA0F5L, "visible" to true)),
            reader.calendars(),
        )
    }

    @Test
    fun `instances come back with every field the Dart mapping needs`() {
        provider.instances += instance(10, status = Instances.STATUS_CANCELED)
        val row = reader.instances(listOf("3"), 1_790_000_000_000L, 1_792_000_000_000L).single()
        assertEquals(
            mapOf(
                "eventId" to "10",
                "calendarId" to "3",
                "beginMs" to 1_791_000_000_000L,
                "endMs" to 1_791_001_800_000L,
                "allDay" to false,
                "title" to "Sprint planning",
                "location" to "Room 4",
                "description" to "Join: https://teams.microsoft.com/l/meetup-join/abc",
                "organizer" to "thandi@example.com",
                "availability" to Instances.AVAILABILITY_TENTATIVE,
                "selfAttendeeStatus" to CalendarContract.Attendees.ATTENDEE_STATUS_DECLINED,
                "status" to Instances.STATUS_CANCELED,
                "originalId" to null,
                "originalInstanceTimeMs" to null,
                "recurring" to false,
            ),
            row,
        )
    }

    @Test
    fun `the window goes into the instances uri and only the asked calendars come back`() {
        provider.calendars += mapOf(
            Calendars._ID to 4L,
            Calendars.CALENDAR_DISPLAY_NAME to "Home",
            Calendars.ACCOUNT_NAME to null,
            Calendars.CALENDAR_COLOR to 0xFF33AA66.toInt(),
            Calendars.VISIBLE to 1,
        )
        provider.instances += instance(10)
        provider.instances += instance(11, calendarId = 4)
        val rows = reader.instances(listOf("3"), 100L, 200L)
        assertEquals(listOf("10"), rows.map { it["eventId"] })
        assertEquals(listOf("instances", "when", "100", "200"), provider.instanceUris.single().pathSegments)
    }

    @Test
    fun `series instances and moved exceptions are marked`() {
        provider.instances += instance(10, rrule = "FREQ=WEEKLY")
        provider.instances += instance(12, originalId = "10", originalInstanceTime = 1_790_990_000_000L)
        val (series, moved) = reader.instances(listOf("3"), 0L, Long.MAX_VALUE)
        assertEquals(true, series["recurring"])
        assertEquals(null, series["originalId"])
        assertEquals("10", moved["originalId"])
        assertEquals(1_790_990_000_000L, moved["originalInstanceTimeMs"])
    }

    @Test
    fun `a calendar that no longer exists is an error, not an empty list`() {
        val e = assertThrows(DeviceCalendarException::class.java) { reader.instances(listOf("3", "99"), 0L, 1L) }
        assertEquals(DeviceCalendarReader.CALENDAR_MISSING, e.code)
    }

    @Test
    fun `without READ_CALENDAR every call is refused`() {
        val denied = DeviceCalendarReader(app, hasPermission = { false })
        assertEquals(DeviceCalendarReader.PERMISSION_DENIED, assertThrows(DeviceCalendarException::class.java) { denied.calendars() }.code)
        assertEquals(
            DeviceCalendarReader.PERMISSION_DENIED,
            assertThrows(DeviceCalendarException::class.java) { denied.instances(listOf("3"), 0L, 1L) }.code,
        )
    }
}
