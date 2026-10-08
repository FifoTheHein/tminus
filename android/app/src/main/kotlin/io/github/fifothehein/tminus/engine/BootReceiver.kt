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
        when (intent.action) {
            // Android 15+ forbids starting the mediaPlayback service from a boot broadcast: whatever
            // should ring now fires through AlarmManager once the boot allow-list has ended (RECOVERY_DELAY_MS).
            in BOOT_ACTIONS -> EngineActions.create(context).recoverAfterBoot()
            // An update may start it (checked on API 36): show again what was on screen, then re-arm.
            Intent.ACTION_MY_PACKAGE_REPLACED -> EngineActions.create(context).run {
                recoverPresented()
                rearmAll()
            }
        }
    }

    companion object {
        val BOOT_ACTIONS = setOf(Intent.ACTION_LOCKED_BOOT_COMPLETED, Intent.ACTION_BOOT_COMPLETED)
        val ACTIONS = BOOT_ACTIONS + Intent.ACTION_MY_PACKAGE_REPLACED
    }
}
