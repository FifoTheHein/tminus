package io.github.fifothehein.tminus.engine

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import org.json.JSONObject
import java.io.File
import java.io.FileOutputStream
import java.io.RandomAccessFile
import java.nio.file.Files
import java.nio.file.StandardCopyOption
import java.util.concurrent.CopyOnWriteArraySet

/**
 * Engine events waiting for Dart, one JSON object per line, in device-protected storage.
 * Every event is appended, whether or not it was also streamed live (roadmap §3).
 */
class EventQueue(context: Context) {
    internal val file = File(File(context.createDeviceProtectedStorageContext().filesDir, PlanStore.DIR_NAME), FILE_NAME)
    internal val tempFile = File(file.parentFile, "$FILE_NAME.tmp")

    fun append(event: EngineEvent) = synchronized(LOCK) {
        file.parentFile!!.mkdirs()
        val line = EngineJson.eventToJson(event).toString()
        val existing = readLinesLocked()
        if (existing.size >= MAX_EVENTS) {
            // Rewrite via a synced temp file and an atomic rename so a crash cannot lose the whole queue.
            FileOutputStream(tempFile).use { out ->
                out.write((existing.takeLast(MAX_EVENTS - 1) + line).joinToString(separator = "\n", postfix = "\n").toByteArray(Charsets.UTF_8))
                out.flush()
                out.fd.sync()
            }
            Files.move(tempFile.toPath(), file.toPath(), StandardCopyOption.REPLACE_EXISTING, StandardCopyOption.ATOMIC_MOVE)
        } else {
            // A crash mid-append can leave a last line with no newline; start on a fresh line so the new event
            // is not glued onto those torn bytes.
            val bytes = ((if (endsMidLineLocked()) "\n" else "") + line + "\n").toByteArray(Charsets.UTF_8)
            FileOutputStream(file, true).use { out ->
                out.write(bytes)
                out.flush()
                out.fd.sync()
            }
        }
    }

    fun peek(): List<EngineEvent> = synchronized(LOCK) { parse(readLinesLocked()) }

    /** Returns every queued event and empties the queue. */
    fun drain(): List<EngineEvent> = synchronized(LOCK) {
        val events = parse(readLinesLocked())
        file.delete()
        events
    }

    private fun endsMidLineLocked(): Boolean {
        if (!file.exists() || file.length() == 0L) return false
        RandomAccessFile(file, "r").use { raf ->
            raf.seek(raf.length() - 1)
            return raf.read() != '\n'.code
        }
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

/**
 * Queues every engine event and streams it to Dart on every `alarm_engine/events` stream that has a
 * listener: one per registered engine (the app's and, from Plan 4, the headless one).
 */
object EngineEvents {
    private val listeners = CopyOnWriteArraySet<(Map<String, Any?>) -> Unit>()

    private val mainHandler by lazy { Handler(Looper.getMainLooper()) }

    /** Adds a live listener (AlarmEngineChannel.onListen) and returns a function that removes only it. */
    fun addListener(listener: (Map<String, Any?>) -> Unit): () -> Unit {
        listeners.add(listener)
        return { listeners.remove(listener) }
    }

    fun emit(context: Context, event: EngineEvent) {
        EventQueue(context).append(event)
        if (listeners.isEmpty()) return
        val current = listeners.toList()
        val map = event.toMap()
        mainHandler.post { current.forEach { it(map) } }
    }
}
