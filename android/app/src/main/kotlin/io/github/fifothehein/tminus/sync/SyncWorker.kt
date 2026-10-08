package io.github.fifothehein.tminus.sync

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import androidx.concurrent.futures.CallbackToFutureAdapter
import androidx.core.app.NotificationCompat
import androidx.work.Data
import androidx.work.ForegroundInfo
import androidx.work.ListenableWorker
import androidx.work.WorkerParameters
import com.google.common.util.concurrent.ListenableFuture
import io.github.fifothehein.tminus.R

/**
 * Runs one sync (spec §7 "Sync triggers"): [SyncRunner] boots a headless FlutterEngine that runs
 * Dart `syncMain()` and reports an outcome. Every trigger (periodic, calendar change, pre-alarm,
 * Sync now) goes through here. `startWork` runs on the main thread, where a FlutterEngine must be
 * created.
 */
class SyncWorker(
    context: Context,
    params: WorkerParameters,
    private val runner: SyncRunner,
) : ListenableWorker(context, params) {
    /** The constructor WorkManager's default factory calls. */
    constructor(context: Context, params: WorkerParameters) :
        this(context, params, HeadlessFlutterRunner(context.applicationContext))

    @Volatile private var cancel: (() -> Unit)? = null

    override fun startWork(): ListenableFuture<Result> = CallbackToFutureAdapter.getFuture { completer ->
        val trigger = inputData.getString(KEY_TRIGGER) ?: TRIGGER_MANUAL
        cancel = runner.run(trigger) { outcome -> completer.set(resultFor(outcome, runAttemptCount)) }
        "SyncWorker($trigger)"
    }

    override fun onStopped() {
        cancel?.invoke()
    }

    /** Expedited work runs as a foreground service below Android 12; this is its notification. */
    override fun getForegroundInfoAsync(): ListenableFuture<ForegroundInfo> = CallbackToFutureAdapter.getFuture { completer ->
        completer.set(ForegroundInfo(RUNNING_NOTIFICATION_ID, runningNotification(applicationContext)))
        "SyncWorker foreground"
    }

    companion object {
        const val KEY_TRIGGER = "trigger"

        // Trigger names match Dart's SyncTrigger values.
        const val TRIGGER_PERIODIC = "periodic"
        const val TRIGGER_CALENDAR_CHANGE = "calendarChange"
        const val TRIGGER_PRE_ALARM = "preAlarm"
        const val TRIGGER_MANUAL = "manual"
        const val TRIGGER_TIME_CHANGE = "timeChange"

        /** What Dart's `syncMain()` reports (SyncRunOutcome names). */
        const val OUTCOME_OK = "ok"
        const val OUTCOME_RETRY = "retry"
        const val OUTCOME_BUSY = "busy"

        /**
         * Retries per request (decision 25): after 30 s and after 60 s. Every run fetches every source,
         * so a feed that keeps failing would otherwise back the request off for hours, and runNow's
         * KEEP / APPEND_OR_REPLACE would hold every later sync of that trigger behind it.
         */
        const val MAX_RETRIES = 2

        const val CHANNEL_RUNNING = "sync_running"
        private const val RUNNING_NOTIFICATION_ID = 0x5301

        fun input(trigger: String): Data = Data.Builder().putString(KEY_TRIGGER, trigger).build()

        /**
         * Temporary failures retry with WorkManager's backoff (spec §9), at most [MAX_RETRIES] times;
         * anything else is done. The next trigger (periodic within 15 min, pre-alarm, calendar change)
         * syncs again anyway.
         */
        fun resultFor(outcome: String, runAttemptCount: Int): Result =
            if (outcome == OUTCOME_RETRY && runAttemptCount < MAX_RETRIES) Result.retry() else Result.success()

        private fun runningNotification(context: Context): android.app.Notification {
            val manager = context.getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(
                NotificationChannel(CHANNEL_RUNNING, "Calendar sync in progress", NotificationManager.IMPORTANCE_MIN),
            )
            return NotificationCompat.Builder(context, CHANNEL_RUNNING)
                .setSmallIcon(R.drawable.ic_stat_tminus)
                .setContentTitle("Syncing calendars")
                .setPriority(NotificationCompat.PRIORITY_MIN)
                .setOngoing(true)
                .build()
        }
    }
}

/** Runs Dart `syncMain(trigger)` and calls `done` once with its outcome. Returns a cancel function. */
fun interface SyncRunner {
    fun run(trigger: String, done: (String) -> Unit): () -> Unit
}
