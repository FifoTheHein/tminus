package io.github.fifothehein.tminus.sync

import android.content.Context
import android.provider.CalendarContract
import androidx.work.BackoffPolicy
import androidx.work.Constraints
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequest
import androidx.work.OutOfQuotaPolicy
import androidx.work.PeriodicWorkRequest
import androidx.work.WorkManager
import androidx.work.Worker
import androidx.work.WorkerParameters
import java.time.Duration
import java.util.concurrent.TimeUnit

/** Every WorkManager request for sync (spec §7 "Sync triggers"). */
class SyncScheduler(
    context: Context,
    private val workManager: WorkManager = WorkManager.getInstance(context.applicationContext),
) {
    /** Every 15 min with a network; kept if already scheduled. App start calls this. */
    fun ensurePeriodic() {
        val request = PeriodicWorkRequest.Builder(SyncWorker::class.java, 15, TimeUnit.MINUTES)
            .setConstraints(Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build())
            .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, BACKOFF_SECONDS, TimeUnit.SECONDS)
            .setInputData(SyncWorker.input(SyncWorker.TRIGGER_PERIODIC))
            .build()
        workManager.enqueueUniquePeriodicWork(PERIODIC, ExistingPeriodicWorkPolicy.KEEP, request)
    }

    /**
     * One sync as soon as possible, without a network condition: device calendars still refresh and
     * the stale-feed check still runs offline. Pre-alarm and Sync now are expedited. A request whose
     * trigger is already queued or running is dropped, except calendar changes, which queue one more
     * run after the current one so a change made during a sync is not missed.
     */
    fun runNow(trigger: String, expedited: Boolean) {
        val builder = OneTimeWorkRequest.Builder(SyncWorker::class.java)
            .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, BACKOFF_SECONDS, TimeUnit.SECONDS)
            .setInputData(SyncWorker.input(trigger))
        if (expedited) builder.setExpedited(OutOfQuotaPolicy.RUN_AS_NON_EXPEDITED_WORK_REQUEST)
        val policy = if (trigger == SyncWorker.TRIGGER_CALENDAR_CHANGE) ExistingWorkPolicy.APPEND_OR_REPLACE else ExistingWorkPolicy.KEEP
        workManager.enqueueUniqueWork(nowName(trigger), policy, builder.build())
    }

    /**
     * Watches `CalendarContract.Events` while a device source exists (spec §7): a change starts a
     * sync. Content-URI work runs once, so [CalendarWatchWorker] queues the next watch itself.
     */
    fun setCalendarWatch(enabled: Boolean) {
        if (enabled) {
            workManager.enqueueUniqueWork(CALENDAR_WATCH, ExistingWorkPolicy.KEEP, calendarWatchRequest())
        } else {
            workManager.cancelUniqueWork(CALENDAR_WATCH)
        }
    }

    /** From inside a running watch: the next watch starts when this one finishes. */
    internal fun rewatch() {
        workManager.enqueueUniqueWork(CALENDAR_WATCH, ExistingWorkPolicy.APPEND_OR_REPLACE, calendarWatchRequest())
    }

    private fun calendarWatchRequest(): OneTimeWorkRequest = OneTimeWorkRequest.Builder(CalendarWatchWorker::class.java)
        .setConstraints(
            Constraints.Builder()
                .addContentUriTrigger(CalendarContract.Events.CONTENT_URI, true)
                .setTriggerContentUpdateDelay(Duration.ofSeconds(5))
                .setTriggerContentMaxDelay(Duration.ofSeconds(30))
                .build(),
        )
        .build()

    companion object {
        const val PERIODIC = "tminus.sync.periodic"
        const val CALENDAR_WATCH = "tminus.sync.calendarWatch"
        private const val BACKOFF_SECONDS = 30L

        fun nowName(trigger: String) = "tminus.sync.now.$trigger"
    }
}

/** Fires when the phone's calendar changes: queues a sync and the next watch. Never boots Flutter. */
class CalendarWatchWorker(context: Context, params: WorkerParameters) : Worker(context, params) {
    override fun doWork(): Result {
        SyncScheduler(applicationContext).run {
            runNow(SyncWorker.TRIGGER_CALENDAR_CHANGE, expedited = false)
            rewatch()
        }
        return Result.success()
    }
}
