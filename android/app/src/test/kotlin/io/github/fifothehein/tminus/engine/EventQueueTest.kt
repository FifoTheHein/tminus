package io.github.fifothehein.tminus.engine

import android.content.Context
import android.os.Looper
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf

@RunWith(RobolectricTestRunner::class)
class EventQueueTest {
    private val context: Context = RuntimeEnvironment.getApplication()
    private lateinit var queue: EventQueue
    private var removeListener: (() -> Unit)? = null

    private fun event(n: Int, type: EngineEventType = EngineEventType.FIRED, snoozeUntil: Long? = null) =
        EngineEvent(type, "a$n", "src|a$n|occ", NOW + MINUTE_MS, NOW + n, snoozeUntil)

    @Before
    fun setUp() {
        queue = EventQueue(context)
        queue.drain()
    }

    @After
    fun tearDown() {
        removeListener?.invoke()
    }

    @Test
    fun `drain returns events in order and empties the queue`() {
        queue.append(event(1))
        queue.append(event(2, EngineEventType.SNOOZED, snoozeUntil = NOW + 5 * MINUTE_MS))
        assertEquals(listOf(event(1), event(2, EngineEventType.SNOOZED, NOW + 5 * MINUTE_MS)), queue.drain())
        assertTrue(queue.drain().isEmpty())
    }

    @Test
    fun `an unreadable line is skipped`() {
        queue.append(event(1))
        queue.file.appendText("{\"type\":\"fired\",\"alertId\"\n") // torn write
        queue.append(event(2))
        assertEquals(listOf("a1", "a2"), queue.drain().map { it.alertId })
    }

    @Test
    fun `an event appended after an unterminated torn line is still drained intact`() {
        queue.append(event(1))
        queue.file.appendText("{\"type\":\"fired\",\"alertId\"") // crash mid-append: no trailing newline
        queue.append(event(2))
        assertEquals(listOf("a1", "a2"), queue.drain().map { it.alertId })
    }

    @Test
    fun `good lines on both sides of a garbage line all survive`() {
        queue.append(event(1))
        queue.file.appendBytes(byteArrayOf(0xFF.toByte(), 0xFE.toByte(), 0x00, 0x7B, 0x80.toByte(), '\n'.code.toByte()))
        queue.append(event(2))
        queue.file.appendBytes(byteArrayOf(0x00, 0x00, 0xC3.toByte())) // unterminated garbage at the end of the file
        queue.append(event(3))
        assertEquals(listOf(event(1), event(2), event(3)), queue.peek())
        assertEquals(listOf(event(1), event(2), event(3)), queue.drain())
    }

    @Test
    fun `the queue keeps only the newest events`() {
        repeat(EventQueue.MAX_EVENTS + 5) { queue.append(event(it)) }
        val events = queue.peek()
        assertEquals(EventQueue.MAX_EVENTS, events.size)
        assertEquals("a5", events.first().alertId)
        assertEquals("a${EventQueue.MAX_EVENTS + 4}", events.last().alertId)
    }

    @Test
    fun `the queue file lives in device-protected storage`() {
        queue.append(event(1))
        val protectedDir = context.createDeviceProtectedStorageContext().filesDir.canonicalPath
        assertTrue(queue.file.canonicalPath.startsWith(protectedDir))
    }

    @Test
    fun `toMap uses the channel field names`() {
        assertEquals(
            mapOf(
                "type" to "dismissedAll",
                "alertId" to "a1",
                "occurrenceKey" to "src|a1|occ",
                "startUtcMs" to NOW + MINUTE_MS,
                "atUtcMs" to NOW + 1,
                "snoozeUntilUtcMs" to null,
            ),
            event(1, EngineEventType.DISMISSED_ALL).toMap(),
        )
    }

    @Test
    fun `emit queues the event and tells the live listener on the main thread`() {
        var received: Map<String, Any?>? = null
        removeListener = EngineEvents.addListener { received = it }
        EngineEvents.emit(context, event(1))
        assertNull(received) // posted, not called inline
        shadowOf(Looper.getMainLooper()).idle()
        assertEquals(event(1).toMap(), received)
        assertEquals(listOf(event(1)), queue.drain())
    }

    @Test
    fun `emit without a listener still queues`() {
        EngineEvents.emit(context, event(1))
        assertEquals(listOf(event(1)), queue.drain())
    }
}
