package io.github.fifothehein.tminus.engine

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * Re-arms every alarm after a reboot (before and after the first unlock) and after an app update
 * (spec §7). Reads only device-protected storage, so it works in direct boot.
 */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action !in ACTIONS) return
        EngineActions.create(context).rearmAll()
    }

    companion object {
        val ACTIONS = setOf(
            Intent.ACTION_LOCKED_BOOT_COMPLETED,
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_MY_PACKAGE_REPLACED,
        )
    }
}
