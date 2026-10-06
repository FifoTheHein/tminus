package io.github.fifothehein.tminus.engine

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import io.github.fifothehein.tminus.MainActivity

data class ApplyResult(val armed: Int, val cancelled: Int, val kept: Int) {
    fun toMap(): Map<String, Int> = mapOf("armed" to armed, "cancelled" to cancelled, "kept" to kept)
}

/**
 * Owns every AlarmManager call. One alarm per alert, keyed by alert id (PendingIntent request
 * code = id.hashCode(), roadmap §3); coalescing happens at fire time in EngineReducer.fire.
 */
class AlarmScheduler(
    context: Context,
    private val store: PlanStore = PlanStore(context),
    private val clock: () -> Long = System::currentTimeMillis,
) {
    private val appContext: Context = context.applicationContext
    private val alarmManager: AlarmManager = appContext.getSystemService(AlarmManager::class.java)

    fun applyPlan(incoming: List<PlannedAlert>): ApplyResult {
        val now = clock()
        val diff = store.update { old -> PlanDiff.apply(old, incoming, now).let { it.state to it } }
        diff.toCancel.forEach { cancel(it.id) }
        diff.toArm.forEach(::arm)
        // Kept alerts are armed again too: the same PendingIntent replaces the alarm, so this is
        // idempotent, and it restores an alarm that vanished even if its PendingIntent survived.
        // One whose PendingIntent is gone too (a force stop) counts as armed rather than kept.
        val vanished = diff.kept.filterNot(::isArmed)
        diff.kept.forEach(::arm)
        return ApplyResult(
            armed = diff.toArm.size + vanished.size,
            cancelled = diff.toCancel.size,
            kept = diff.kept.size - vanished.size,
        )
    }

    /**
     * Re-arm triggers (spec §7) and app start: arms every future alert. Overdue ones stay in the
     * store for EngineActions.reconcile, which rings them or reports them missed.
     */
    fun rearmAll(): Int {
        val now = clock()
        val future = store.read().scheduled.filter { it.fireAtUtcMs > now }
        future.forEach(::arm)
        Log.i(TAG, "Re-armed ${future.size} alerts")
        return future.size
    }

    fun arm(alert: PlannedAlert) {
        val operation = operation(alert.id, PendingIntent.FLAG_UPDATE_CURRENT)!!
        val at = alert.fireAtUtcMs
        try {
            when {
                !canScheduleExactAlarms() -> alarmManager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, operation)
                alert.strength == Strength.ALARM ->
                    alarmManager.setAlarmClock(AlarmManager.AlarmClockInfo(at, showIntent()), operation)
                else -> alarmManager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, operation)
            }
        } catch (e: SecurityException) {
            Log.w(TAG, "Exact alarm refused for ${alert.id}; using an inexact alarm", e)
            alarmManager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, operation)
        }
    }

    fun cancel(alertId: String) {
        val operation = operation(alertId, PendingIntent.FLAG_NO_CREATE) ?: return
        alarmManager.cancel(operation)
        operation.cancel()
    }

    /** True if the alert's PendingIntent exists. The alarm itself may still be gone: see applyPlan. */
    fun isArmed(alert: PlannedAlert): Boolean = operation(alert.id, PendingIntent.FLAG_NO_CREATE) != null

    fun upcoming(limit: Int = 5): List<PlannedAlert> {
        val now = clock()
        return store.read().scheduled.filter { it.fireAtUtcMs > now }.sortedBy { it.fireAtUtcMs }.take(limit)
    }

    fun canScheduleExactAlarms(): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.S || alarmManager.canScheduleExactAlarms()

    private fun operation(alertId: String, flags: Int): PendingIntent? = PendingIntent.getBroadcast(
        appContext,
        alertId.hashCode(),
        AlarmReceiver.fireIntent(appContext, alertId),
        flags or PendingIntent.FLAG_IMMUTABLE,
    )

    /** setAlarmClock's show intent opens the app (the Agenda, once Plan 5 exists). */
    private fun showIntent(): PendingIntent = PendingIntent.getActivity(
        appContext,
        SHOW_REQUEST_CODE,
        Intent(appContext, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )

    companion object {
        private const val TAG = "TMinusEngine"
        private const val SHOW_REQUEST_CODE = 0x5101
    }
}
