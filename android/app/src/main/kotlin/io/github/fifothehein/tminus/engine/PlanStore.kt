package io.github.fifothehein.tminus.engine

import android.content.Context
import android.util.Log
import org.json.JSONObject
import java.io.File
import java.io.FileOutputStream
import java.nio.file.Files
import java.nio.file.StandardCopyOption

/**
 * The engine's state as one JSON file in device-protected storage, so alarms can be re-armed
 * after a reboot before the user unlocks (spec §7). Writes are atomic: temp file, fsync, rename.
 */
class PlanStore(context: Context) {
    private val dir = File(context.createDeviceProtectedStorageContext().filesDir, DIR_NAME)
    internal val stateFile = File(dir, FILE_NAME)
    internal val tempFile = File(dir, "$FILE_NAME.tmp")

    fun read(): EngineState = synchronized(LOCK) { readLocked() }

    fun write(state: EngineState) = synchronized(LOCK) { writeLocked(state) }

    /** Read-modify-write under the store lock. Writes only when the state changed. */
    fun <T> update(block: (EngineState) -> Pair<EngineState, T>): T = synchronized(LOCK) {
        val current = readLocked()
        val (next, result) = block(current)
        if (next != current) writeLocked(next)
        result
    }

    fun clear() = synchronized(LOCK) {
        stateFile.delete()
        tempFile.delete()
        Unit
    }

    private fun readLocked(): EngineState {
        if (!stateFile.exists()) return EngineState.EMPTY
        return try {
            EngineJson.stateFromJson(JSONObject(stateFile.readText()))
        } catch (e: Exception) {
            Log.e(TAG, "Engine state unreadable; starting from an empty plan", e)
            runCatching { stateFile.copyTo(File(dir, "$FILE_NAME.corrupt"), overwrite = true) }
            EngineState.EMPTY
        }
    }

    private fun writeLocked(state: EngineState) {
        dir.mkdirs()
        FileOutputStream(tempFile).use { out ->
            out.write(EngineJson.stateToJson(state).toString().toByteArray(Charsets.UTF_8))
            out.fd.sync()
        }
        // rename(2) on Android; MoveFileEx(REPLACE_EXISTING) on the Windows test host.
        Files.move(tempFile.toPath(), stateFile.toPath(), StandardCopyOption.REPLACE_EXISTING, StandardCopyOption.ATOMIC_MOVE)
    }

    companion object {
        const val DIR_NAME = "engine"
        const val FILE_NAME = "state.json"
        private const val TAG = "TMinusEngine"
        private val LOCK = Any()
    }
}
