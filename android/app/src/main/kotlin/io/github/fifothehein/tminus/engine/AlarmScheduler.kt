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
 *
 * Every AlarmManager call and PendingIntent lookup is a Binder call that can block for seconds when
 * system_server is slow, so none of them runs on the caller's thread: [arm], [cancel], [applyPlan]
 * and the others post theirs to [AlarmCalls] and return at once, and it runs them one at a time in
 * the order they were issued. What to arm is still worked out on the caller's thread (the PlanStore
 * diff, the clock), so the engine's state stays confined to the main thread. [armNow] and
 * [armRingingRetryNow] are the two exceptions: they make their calls on the caller's thread, for the
 * two callers that finish at once and have nothing to keep the process alive for a queued alarm.
 */
class AlarmScheduler(
    context: Context,
    private val store: PlanStore = PlanStore(context),
    private val clock: () -> Long = System::currentTimeMillis,
) {
    private val appContext: Context = context.applicationContext
    private val alarmManager: AlarmManager = appContext.getSystemService(AlarmManager::class.java)

    /**
     * Diffs [incoming] against the stored plan on the caller's thread, then posts ONE [AlarmCalls]
     * block that cancels, arms and re-arms. [onApplied] gets the counts on AlarmCalls' thread once that
     * block has run, so a caller that tells someone "armed" can wait for it. It is not called when
     * the block threw: AlarmCalls keeps the failure for its next marker.
     */
    fun applyPlan(incoming: List<PlannedAlert>, onApplied: (ApplyResult) -> Unit = {}) {
        val now = clock()
        val diff = store.update { old -> PlanDiff.apply(old, incoming, now).let { it.state to it } }
        AlarmCalls.run {
            diff.toCancel.forEach { cancelBlocking(it.id) }
            diff.toArm.forEach { armBlocking(it) }
            // Kept alerts are armed again too: the same PendingIntent replaces the alarm, so this is
            // idempotent, and it restores an alarm that vanished even if its PendingIntent survived.
            // One whose PendingIntent is gone too (a force stop) counts as armed rather than kept.
            val vanished = diff.kept.filterNot(::isArmed)
            diff.kept.forEach { armBlocking(it) }
            onApplied(
                ApplyResult(
                    armed = diff.toArm.size + vanished.size,
                    cancelled = diff.toCancel.size,
                    kept = diff.kept.size - vanished.size,
                ),
            )
        }
    }

    /**
     * Re-arm triggers (spec §7) and app start: posts the arm of every future alert, one block each so
     * a failing alarm does not leave the rest unarmed, and returns their count at once. They are posted
     * in fire-time order: if the process is cut off before the queue has drained (a receiver's broadcast
     * has a time limit), the alarms that were not armed are the latest, not the nearest. Overdue ones
     * stay in the store for EngineActions.reconcile, which rings them or reports them missed.
     */
    fun rearmAll(): Int {
        val now = clock()
        val future = store.read().scheduled.filter { it.fireAtUtcMs > now }.sortedBy { it.fireAtUtcMs }
        future.forEach { arm(it) }
        Log.i(TAG, "Re-arming ${future.size} alerts")
        return future.size
    }

    /** Posts the arm of [alert]'s alarm for [at]: its fire time, or a moment from now for an alert overdue at boot. */
    fun arm(alert: PlannedAlert, at: Long = alert.fireAtUtcMs) {
        AlarmCalls.run { armBlocking(alert, at) }
    }

    /**
     * [arm], made on the caller's thread and then posted again. The call on the caller's thread sets the
     * alarm at once: it waits for system_server, and a failure of it reaches the caller. Only for the
     * alarm screen's Snooze (EngineActions.snooze with `armNow`): the screen closes with the snooze and
     * nothing would keep the process alive for a queued alarm, which Android could end before it ran.
     * The copy posted behind the queue keeps the alarm armed after any cancel for the same id that was
     * queued earlier: snoozing a snooze reuses its id, and a reconcile or a fire queues the cancel of
     * every alert it fires, so such a cancel can still be waiting when this runs, and without the copy
     * it would remove the alarm that was just set while the stored plan still lists the snooze as
     * scheduled. Same id and time, so the second arm only replaces the first. Every other caller uses
     * [arm], because these calls can hold the main thread for seconds when system_server is slow.
     */
    fun armNow(alert: PlannedAlert, at: Long = alert.fireAtUtcMs) {
        armBlocking(alert, at)
        AlarmCalls.run { armBlocking(alert, at) }
    }

    /** Posts the cancel of [alertId]'s alarm. */
    fun cancel(alertId: String) {
        AlarmCalls.run { cancelBlocking(alertId) }
    }

    /**
     * Boot recovery: an alarm that was ringing at reboot rings again through AlarmReceiver at [at],
     * which calls EngineActions.recoverPresented (Android 15+ refused the previous mediaPlayback type
     * from the boot broadcasts, though an exact alarm could start it; the delay stays as a guard,
     * Plan 6 decision 9). The alarm is posted to [AlarmCalls].
     */
    fun armRecovery(at: Long) {
        AlarmCalls.run {
            set(recoveryOperation(PendingIntent.FLAG_UPDATE_CURRENT)!!, at, alarmClock = true, label = "boot recovery")
        }
    }

    /**
     * RingingService's foreground start was refused and [alertIds] show as a heads-up: they ring again
     * through AlarmReceiver at [at] (an alarm-clock alarm may start the service). The alarm is posted
     * to [AlarmCalls].
     */
    fun armRingingRetry(alertIds: List<String>, at: Long) {
        val ids = alertIds.toList()
        AlarmCalls.run { armRingingRetryBlocking(ids, at) }
    }

    /**
     * [armRingingRetry], made on the caller's thread, and a failure reaches the caller. Only for
     * RingingService.refuseForeground: the service must stop at once after a refused foreground start,
     * so nothing would keep the process alive for a queued retry, and if the retry were lost the alerts
     * would stay heads-up notifications and never ring. It is one alarm with a request code of its own,
     * so making it ahead of the queue cannot reorder another alert's calls.
     */
    fun armRingingRetryNow(alertIds: List<String>, at: Long) {
        armRingingRetryBlocking(alertIds, at)
    }

    /** Posts the cancel of boot recovery's alarm. */
    fun cancelRecovery() {
        AlarmCalls.run {
            val operation = recoveryOperation(PendingIntent.FLAG_NO_CREATE) ?: return@run
            alarmManager.cancel(operation)
            operation.cancel()
        }
    }

    /**
     * True if the alert's PendingIntent exists. The alarm itself may still be gone: see applyPlan. A
     * Binder call: production code asks it only inside an [AlarmCalls] block.
     */
    fun isArmed(alert: PlannedAlert): Boolean = operation(alert.id, PendingIntent.FLAG_NO_CREATE) != null

    fun upcoming(limit: Int = 5): List<PlannedAlert> {
        val now = clock()
        return store.read().scheduled.filter { it.fireAtUtcMs > now }.sortedBy { it.fireAtUtcMs }.take(limit)
    }

    /**
     * A Binder call too: [set] asks it inside an [AlarmCalls] block, and `getHealth` asks it once, on
     * the channel's thread.
     */
    fun canScheduleExactAlarms(): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.S || alarmManager.canScheduleExactAlarms()

    // What follows talks to system_server and waits for its answer: only an AlarmCalls block may call it,
    // apart from armNow and armRingingRetryNow.

    private fun armBlocking(alert: PlannedAlert, at: Long = alert.fireAtUtcMs) {
        set(operation(alert.id, PendingIntent.FLAG_UPDATE_CURRENT)!!, at, alarmClock = alert.strength == Strength.ALARM, label = alert.id)
    }

    private fun armRingingRetryBlocking(alertIds: List<String>, at: Long) {
        val operation = PendingIntent.getBroadcast(
            appContext,
            "retry|${alertIds.joinToString(",")}".hashCode(),
            AlarmReceiver.retryRingingIntent(appContext, alertIds),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        set(operation, at, alarmClock = true, label = "ringing retry")
    }

    private fun cancelBlocking(alertId: String) {
        val operation = operation(alertId, PendingIntent.FLAG_NO_CREATE) ?: return
        alarmManager.cancel(operation)
        operation.cancel()
    }

    private fun set(operation: PendingIntent, at: Long, alarmClock: Boolean, label: String) {
        try {
            when {
                !canScheduleExactAlarms() -> alarmManager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, operation)
                alarmClock -> alarmManager.setAlarmClock(AlarmManager.AlarmClockInfo(at, showIntent()), operation)
                else -> alarmManager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, operation)
            }
        } catch (e: SecurityException) {
            Log.w(TAG, "Exact alarm refused for $label; using an inexact alarm: ${e.javaClass.simpleName}")
            alarmManager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, operation)
        }
    }

    private fun operation(alertId: String, flags: Int): PendingIntent? = PendingIntent.getBroadcast(
        appContext,
        alertId.hashCode(),
        AlarmReceiver.fireIntent(appContext, alertId),
        flags or PendingIntent.FLAG_IMMUTABLE,
    )

    private fun recoveryOperation(flags: Int): PendingIntent? = PendingIntent.getBroadcast(
        appContext,
        RECOVERY_REQUEST_CODE,
        AlarmReceiver.recoverIntent(appContext),
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
        private const val RECOVERY_REQUEST_CODE = 0x5105
    }
}
