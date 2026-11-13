package io.github.fifothehein.tminus.calendar

import android.Manifest
import android.content.ContentResolver
import android.content.ContentUris
import android.content.Context
import android.content.pm.PackageManager
import android.database.Cursor
import android.provider.CalendarContract.Calendars
import android.provider.CalendarContract.Instances
import androidx.core.content.ContextCompat

/** A failure the Dart side maps to a source state; [code] becomes the PlatformException code. */
class DeviceCalendarException(val code: String, message: String) : Exception(message)

/**
 * Reads the phone's calendars and their expanded instances (spec §5 `DeviceCalendarSource`).
 * Android has already expanded recurrence in `CalendarContract.Instances`. READ_CALENDAR is asked
 * for by the UI (Plan 5); without it every call throws [PERMISSION_DENIED].
 */
class DeviceCalendarReader(
    context: Context,
    private val resolver: ContentResolver = context.applicationContext.contentResolver,
    private val hasPermission: () -> Boolean = {
        ContextCompat.checkSelfPermission(context, Manifest.permission.READ_CALENDAR) == PackageManager.PERMISSION_GRANTED
    },
) {
    /**
     * Every calendar on the phone, by display name, as ten keys: `{id, name, accountName, color,
     * visible, accountType, ownerAccount, accessLevel, syncEvents, primary}`.
     *
     * The last five are what the picker groups calendars by. A column the provider leaves empty gives
     * null (`accountType`, `ownerAccount`, `accessLevel`, `primary`), except `syncEvents`, which then
     * counts as true. `ownerAccount` is an email address: like `accountName`, it is never logged.
     */
    fun calendars(): List<Map<String, Any?>> {
        requirePermission()
        val rows = mutableListOf<Map<String, Any?>>()
        resolver.query(Calendars.CONTENT_URI, CALENDAR_COLUMNS, null, null, "${Calendars.CALENDAR_DISPLAY_NAME} ASC")?.use { c ->
            while (c.moveToNext()) {
                rows += mapOf(
                    "id" to c.getLong(0).toString(),
                    "name" to (c.getString(1) ?: ""),
                    "accountName" to c.getString(2),
                    "color" to opaque(c.getInt(3)),
                    "visible" to (c.getInt(4) != 0),
                    "accountType" to c.stringOrNull(5),
                    "ownerAccount" to c.stringOrNull(6),
                    "accessLevel" to c.intOrNull(7),
                    "syncEvents" to (c.intOrNull(8)?.let { it != 0 } ?: true),
                    "primary" to c.intOrNull(9)?.let { it != 0 },
                )
            }
        }
        return rows
    }

    /**
     * Instances of [calendarIds] overlapping [fromUtcMs, toUtcMs), by start. Throws
     * [CALENDAR_MISSING] if any calendar no longer exists, so the source turns red instead of
     * looking empty.
     */
    fun instances(calendarIds: List<String>, fromUtcMs: Long, toUtcMs: Long): List<Map<String, Any?>> {
        requirePermission()
        require(calendarIds.isNotEmpty()) { "calendarIds is empty" }
        val existing = calendars().map { it["id"] }.toSet()
        val missing = calendarIds.filterNot { it in existing }
        if (missing.isNotEmpty()) throw DeviceCalendarException(CALENDAR_MISSING, "Calendar ${missing.joinToString()} no longer exists")

        val uri = Instances.CONTENT_URI.buildUpon().also {
            ContentUris.appendId(it, fromUtcMs)
            ContentUris.appendId(it, toUtcMs)
        }.build()
        val selection = "${Instances.CALENDAR_ID} IN (${calendarIds.joinToString { "?" }})"
        val rows = mutableListOf<Map<String, Any?>>()
        resolver.query(uri, INSTANCE_COLUMNS, selection, calendarIds.toTypedArray(), "${Instances.BEGIN} ASC")?.use { c ->
            while (c.moveToNext()) rows += instance(c)
        }
        return rows
    }

    private fun instance(c: Cursor): Map<String, Any?> = mapOf(
        "eventId" to c.getLong(0).toString(),
        "calendarId" to c.getLong(1).toString(),
        "beginMs" to c.getLong(2),
        "endMs" to c.getLong(3),
        "allDay" to (c.getInt(4) != 0),
        "title" to c.getString(5),
        "location" to c.getString(6),
        "description" to c.getString(7),
        "organizer" to c.getString(8),
        "availability" to c.getInt(9),
        "selfAttendeeStatus" to c.getInt(10),
        "status" to if (c.isNull(11)) null else c.getInt(11),
        "originalId" to c.getString(12)?.takeIf { it.isNotEmpty() },
        "originalInstanceTimeMs" to if (c.isNull(13)) null else c.getLong(13),
        "recurring" to (!c.getString(14).isNullOrEmpty() || !c.getString(15).isNullOrEmpty()),
    )

    private fun requirePermission() {
        if (!hasPermission()) throw DeviceCalendarException(PERMISSION_DENIED, "READ_CALENDAR is not granted")
    }

    /** Calendar colours are ARGB ints; some providers leave alpha at 0. */
    private fun opaque(color: Int): Long = (color.toLong() and 0xFFFFFFL) or 0xFF000000L

    /** The column's text, or null when the provider left it empty. */
    private fun Cursor.stringOrNull(column: Int): String? = if (isNull(column)) null else getString(column)

    /** The column's int, or null when the provider left it empty: `getInt` would answer 0 there. */
    private fun Cursor.intOrNull(column: Int): Int? = if (isNull(column)) null else getInt(column)

    companion object {
        const val PERMISSION_DENIED = "permission_denied"
        const val CALENDAR_MISSING = "calendar_missing"

        val CALENDAR_COLUMNS = arrayOf(
            Calendars._ID,
            Calendars.CALENDAR_DISPLAY_NAME,
            Calendars.ACCOUNT_NAME,
            Calendars.CALENDAR_COLOR,
            Calendars.VISIBLE,
            Calendars.ACCOUNT_TYPE,
            Calendars.OWNER_ACCOUNT,
            Calendars.CALENDAR_ACCESS_LEVEL,
            Calendars.SYNC_EVENTS,
            Calendars.IS_PRIMARY,
        )

        val INSTANCE_COLUMNS = arrayOf(
            Instances.EVENT_ID,
            Instances.CALENDAR_ID,
            Instances.BEGIN,
            Instances.END,
            Instances.ALL_DAY,
            Instances.TITLE,
            Instances.EVENT_LOCATION,
            Instances.DESCRIPTION,
            Instances.ORGANIZER,
            Instances.AVAILABILITY,
            Instances.SELF_ATTENDEE_STATUS,
            Instances.STATUS,
            Instances.ORIGINAL_ID,
            Instances.ORIGINAL_INSTANCE_TIME,
            Instances.RRULE,
            Instances.RDATE,
        )
    }
}
