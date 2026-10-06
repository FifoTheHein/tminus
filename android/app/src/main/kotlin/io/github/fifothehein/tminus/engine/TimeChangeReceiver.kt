package io.github.fifothehein.tminus.engine

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * Re-arms after the clock, the time zone or exact-alarm access changes (spec §7). Alarms are absolute
 * UTC times, so this mainly handles alerts that are now overdue and restores exactness.
 */
class TimeChangeReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action !in ACTIONS) return
        EngineActions.create(context).rearmAll()
    }

    companion object {
        /** AlarmManager.ACTION_SCHEDULE_EXACT_ALARM_PERMISSION_STATE_CHANGED (API 31). */
        const val ACTION_EXACT_ALARM_PERMISSION_CHANGED = "android.app.action.SCHEDULE_EXACT_ALARM_PERMISSION_STATE_CHANGED"

        val ACTIONS = setOf(
            Intent.ACTION_TIME_CHANGED, // "android.intent.action.TIME_SET"
            Intent.ACTION_TIMEZONE_CHANGED,
            ACTION_EXACT_ALARM_PERMISSION_CHANGED,
        )
    }
}
