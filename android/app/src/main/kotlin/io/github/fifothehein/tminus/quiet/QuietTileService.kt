package io.github.fifothehein.tminus.quiet

import android.content.ComponentName
import android.content.Context
import android.content.SharedPreferences
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import android.util.Log
import io.github.fifothehein.tminus.sync.SyncScheduler
import io.github.fifothehein.tminus.sync.SyncWorker

/**
 * "Mute today" in quick settings (spec §6, brief §7). A tap leaves a request in [QuietStore] and
 * queues a `quietTile` sync, which applies it in Dart and re-plans from the cache. On a locked
 * phone the tap asks for an unlock first, so nobody can silence the owner's alarms from the lock
 * screen. While the tile is on screen it follows the store, so a sync that finishes in the background
 * redraws it.
 */
class QuietTileService : TileService() {
    private val store by lazy(LazyThreadSafetyMode.NONE) { QuietStore(this) }

    // SharedPreferences keeps its listeners weakly: this field is what keeps the listener alive.
    private val storeListener = SharedPreferences.OnSharedPreferenceChangeListener { _, _ -> render() }

    override fun onStartListening() {
        super.onStartListening()
        store.addChangeListener(storeListener)
        render()
    }

    override fun onStopListening() {
        store.removeChangeListener(storeListener)
        super.onStopListening()
    }

    override fun onClick() {
        super.onClick()
        if (isLocked) unlockAndRun { toggle() } else toggle()
    }

    private fun toggle() {
        store.request(store.actionForTap())
        render()
        SyncScheduler(this).runNow(SyncWorker.TRIGGER_QUIET_TILE, expedited = true)
    }

    private fun render() {
        val tile = qsTile ?: return
        val display = store.display()
        tile.state = if (display.active) Tile.STATE_ACTIVE else Tile.STATE_INACTIVE
        tile.label = LABEL
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) tile.subtitle = display.subtitle
        tile.updateTile()
    }

    companion object {
        const val LABEL = "Mute today"
        private const val TAG = "TMinusQuiet"

        /** Asks Android to redraw the tile soon, after a sync changed the quiet state. */
        fun refresh(context: Context) {
            try {
                TileService.requestListeningState(context, ComponentName(context, QuietTileService::class.java))
            } catch (e: RuntimeException) {
                Log.w(TAG, "Tile refresh failed: ${e.javaClass.simpleName}")
            }
        }
    }
}
