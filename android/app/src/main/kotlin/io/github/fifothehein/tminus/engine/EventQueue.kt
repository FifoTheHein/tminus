package io.github.fifothehein.tminus.engine

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import org.json.JSONObject
import java.io.File

/**
 * Engine events waiting for Dart, one JSON object per line, in device-protected storage.
 * Every event is appended, whether or not it was also streamed live (roadmap §3).
 */
class EventQueue(context: Context) {
    internal val file = File(File(context.createDeviceProtectedStorageContext().filesDir, PlanStore.DIR_NAME), FILE_NAME)

    fun append(event: EngineEvent) = synchronized(LOCK) {
        file.parentFile!!.mkdirs()
        val line = EngineJson.eventToJson(event).toString()
        val existing = readLinesLocked()
        if (existing.size >= MAX_EVENTS) {
            file.writeText((existing.takeLast(MAX_EVENTS - 1) + line).joinToString(separator = "\n", postfix = "\n"))
        } else {
            file.appendText(line + "\n")
        }
    }

    fun peek(): List<EngineEvent> = synchronized(LOCK) { parse(readLinesLocked()) }

    /** Returns every queued event and empties the queue. */
    fun drain(): List<EngineEvent> = synchronized(LOCK) {
        val events = parse(readLinesLocked())
        file.delete()
        events
    }

    private fun readLinesLocked(): List<String> =
        if (file.exists()) file.readLines().filter { it.isNotBlank() } else emptyList()

    private fun parse(lines: List<String>): List<EngineEvent> = lines.mapNotNull { line ->
        try {
            EngineJson.eventFromJson(JSONObject(line))
        } catch (e: Exception) {
            Log.w(TAG, "Skipping an unreadable queued event", e)
            null
        }
    }

    companion object {
        const val FILE_NAME = "events.jsonl"
        /** If Dart never drains, keep the newest 500 rather than grow forever. */
        const val MAX_EVENTS = 500
        private const val TAG = "TMinusEngine"
        private val LOCK = Any()
    }
}

/** Queues every engine event and streams it to Dart while `alarm_engine/events` has a listener. */
object EngineEvents {
    /** Set by AlarmEngineChannel.onListen, cleared by onCancel. */
    @Volatile
    var listener: ((Map<String, Any?>) -> Unit)? = null

    private val mainHandler by lazy { Handler(Looper.getMainLooper()) }

    fun emit(context: Context, event: EngineEvent) {
        EventQueue(context).append(event)
        val current = listener ?: return
        val map = event.toMap()
        mainHandler.post { current(map) }
    }
}
