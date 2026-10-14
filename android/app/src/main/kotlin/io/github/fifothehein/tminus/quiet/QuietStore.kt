package io.github.fifothehein.tminus.quiet

import android.content.Context
import android.content.SharedPreferences

/**
 * The quick-settings tile's side of quiet mode (Plan 5 decision 3). A tap leaves a request here for
 * the next sync to apply (`tminus_sync.takeQuietRequest`); each sync leaves the resulting state here
 * (`configure`), so the tile can draw itself without starting Flutter. One lock for every instance:
 * the tile and the channels each make their own.
 *
 * A request that a sync has taken is kept as "in flight" until that sync's `configure` has stored the
 * result, so the tile (and a second tap) reads it as still waiting in that window rather than falling
 * back to the old state. A sync that dies after taking it never stores the result, so a marker stops
 * counting after [IN_FLIGHT_MS].
 */
class QuietStore(context: Context, private val clock: () -> Long = System::currentTimeMillis) {
    private val prefs = context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    data class Request(val action: String, val atMs: Long)
    data class Display(val active: Boolean, val subtitle: String?)

    /** Stores the latest tap. It replaces a waiting request and a request that is in flight. */
    fun request(action: String) {
        require(action == MUTE || action == END) { "action" }
        synchronized(LOCK) {
            prefs.edit()
                .putString(KEY_ACTION, action).putLong(KEY_AT, clock())
                .remove(KEY_TAKEN).remove(KEY_TAKEN_AT)
                .commit()
        }
    }

    /** The waiting request, which then counts as in flight until the next [mirror]. */
    fun take(): Request? = synchronized(LOCK) {
        val action = prefs.getString(KEY_ACTION, null) ?: return null
        val at = prefs.getLong(KEY_AT, 0L)
        prefs.edit()
            .remove(KEY_ACTION).remove(KEY_AT)
            .putString(KEY_TAKEN, action).putLong(KEY_TAKEN_AT, at)
            .commit()
        Request(action, at)
    }

    /** The sync's result: what the tile shows from now on. A request that was in flight is done. */
    fun mirror(untilMs: Long?, text: String?) = synchronized(LOCK) {
        prefs.edit().apply {
            if (untilMs == null) remove(KEY_UNTIL) else putLong(KEY_UNTIL, untilMs)
            if (text == null) remove(KEY_TEXT) else putString(KEY_TEXT, text)
            remove(KEY_TAKEN).remove(KEY_TAKEN_AT)
        }.commit()
        Unit
    }

    fun display(): Display = synchronized(LOCK) {
        when (pendingAction()) {
            MUTE -> return Display(true, MUTING)
            END -> return Display(false, null)
        }
        val until = prefs.getLong(KEY_UNTIL, 0L)
        if (until > clock()) Display(true, prefs.getString(KEY_TEXT, null)) else Display(false, null)
    }

    /** A tap ends a quiet mode that is on (or about to be), and mutes otherwise. */
    fun actionForTap(): String = if (display().active) END else MUTE

    /**
     * Calls [listener] after every change to the store, from any instance in this process (the tile
     * redraws itself that way while it is open). SharedPreferences keeps listeners weakly: the caller
     * must hold [listener] for as long as it wants to hear.
     */
    fun addChangeListener(listener: SharedPreferences.OnSharedPreferenceChangeListener) =
        prefs.registerOnSharedPreferenceChangeListener(listener)

    fun removeChangeListener(listener: SharedPreferences.OnSharedPreferenceChangeListener) =
        prefs.unregisterOnSharedPreferenceChangeListener(listener)

    /** The action of a request that no sync has finished applying: still waiting, or in flight and not too old. */
    private fun pendingAction(): String? {
        prefs.getString(KEY_ACTION, null)?.let { return it }
        val taken = prefs.getString(KEY_TAKEN, null) ?: return null
        val age = clock() - prefs.getLong(KEY_TAKEN_AT, 0L)
        return if (age > IN_FLIGHT_MS) null else taken
    }

    companion object {
        const val PREFS = "tminus_quiet"
        const val MUTE = "mute"
        const val END = "end"
        const val MUTING = "Muting…"

        /** How long after the tap a taken request still counts as being applied. */
        const val IN_FLIGHT_MS = 10 * 60_000L
        private const val KEY_ACTION = "request"
        private const val KEY_AT = "requestAtMs"
        private const val KEY_TAKEN = "takenRequest"
        private const val KEY_TAKEN_AT = "takenRequestAtMs"
        private const val KEY_UNTIL = "untilMs"
        private const val KEY_TEXT = "text"
        private val LOCK = Any()
    }
}
