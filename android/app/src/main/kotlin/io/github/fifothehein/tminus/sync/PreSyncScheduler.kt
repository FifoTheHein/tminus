package io.github.fifothehein.tminus.sync

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import io.github.fifothehein.tminus.engine.TimeChangeReceiver

/**
 * Pre-alarm sync (spec §7): Dart sends one time per occurrence (12 min before its earliest alert)
 * after each sync; this keeps one AlarmManager alarm for the next of them. Times live in the app's
 * credential-protected preferences, so they are re-armed at BOOT_COMPLETED (a sync cannot run
 * before the first unlock anyway).
 */
class PreSyncScheduler(
    context: Context,
    private val clock: () -> Long = System::currentTimeMillis,
) {
    private val appContext: Context = context.applicationContext
    private val prefs = appContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
    private val alarmManager: AlarmManager = appContext.getSystemService(AlarmManager::class.java)

    fun setTimes(times: List<Long>) {
        prefs.edit().putString(KEY_TIMES, times.distinct().sorted().joinToString(",")).apply()
        armNext()
    }

    fun times(): List<Long> =
        prefs.getString(KEY_TIMES, "").orEmpty().split(',').mapNotNull { it.toLongOrNull() }

    /** The next stored time after now, or null. */
    fun next(): Long? = times().firstOrNull { it > clock() }

    /** Sets the alarm for [next], or cancels it when nothing is left. */
    fun armNext() {
        val at = next()
        if (at == null) {
            operation(PendingIntent.FLAG_NO_CREATE)?.let { alarmManager.cancel(it); it.cancel() }
            return
        }
        val operation = operation(PendingIntent.FLAG_UPDATE_CURRENT)!!
        try {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S || alarmManager.canScheduleExactAlarms()) {
                alarmManager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, operation)
            } else {
                alarmManager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, operation)
            }
        } catch (e: SecurityException) {
            Log.w(TAG, "Exact alarm refused for pre-alarm sync; using an inexact alarm", e)
            alarmManager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, operation)
        }
    }

    private fun operation(flags: Int): PendingIntent? = PendingIntent.getBroadcast(
        appContext,
        REQUEST_CODE,
        Intent(appContext, PreSyncReceiver::class.java).setAction(ACTION),
        flags or PendingIntent.FLAG_IMMUTABLE,
    )

    companion object {
        const val ACTION = "io.github.fifothehein.tminus.PRE_SYNC"
        const val PREFS = "tminus_sync"
        private const val KEY_TIMES = "preSyncTimes"
        private const val REQUEST_CODE = 0x5201
        private const val TAG = "TMinusSync"
    }
}

/** The pre-alarm sync alarm: an expedited sync now, then the alarm for the next time. */
class PreSyncReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != PreSyncScheduler.ACTION) return
        SyncScheduler(context).runNow(SyncWorker.TRIGGER_PRE_ALARM, expedited = true)
        PreSyncScheduler(context).armNext()
    }
}

/**
 * Re-arms the pre-alarm sync alarm after a reboot, an app update or a clock change. A clock or zone
 * change also queues a sync, so floating and all-day times and quiet modes are planned in the new
 * zone without waiting for the periodic sync (decision 28).
 */
class SyncBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action !in ACTIONS) return
        PreSyncScheduler(context).armNext()
        if (intent.action in SYNC_ACTIONS) {
            SyncScheduler(context).runNow(SyncWorker.TRIGGER_TIME_CHANGE, expedited = false)
        }
    }

    companion object {
        val ACTIONS = setOf(
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_MY_PACKAGE_REPLACED,
            Intent.ACTION_TIME_CHANGED,
            Intent.ACTION_TIMEZONE_CHANGED,
            TimeChangeReceiver.ACTION_EXACT_ALARM_PERMISSION_CHANGED,
        )

        /** The actions that also queue a `timeChange` sync. */
        val SYNC_ACTIONS = setOf(Intent.ACTION_TIME_CHANGED, Intent.ACTION_TIMEZONE_CHANGED)
    }
}
