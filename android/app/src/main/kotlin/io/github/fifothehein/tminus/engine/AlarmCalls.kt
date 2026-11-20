package io.github.fifothehein.tminus.engine

import android.content.BroadcastReceiver
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.annotation.VisibleForTesting
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executor
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference

/**
 * The one queue for every AlarmManager call and every PendingIntent lookup that the alarm engine
 * and the pre-alarm sync make. Each of them is a Binder call to system_server, and a re-arm or an
 * applyPlan makes 150 to 300. Made on the main thread while system_server was slow, they held it for
 * more than five seconds: Android raised an input ANR (stack in IAlarmManager.set, reached from
 * TimeChangeReceiver.onReceive) and a background ANR at boot. They now run on this object's own
 * thread, one at a time, in the order they were posted.
 *
 * Only the Binder calls move. What to arm is decided on the caller's thread, so PlanStore
 * transitions, EngineReducer, the presenter, RingingSession and the engine events stay confined to
 * the main thread. A race between such a transition and a queued call can at worst leave an alarm
 * for an alert the store no longer lists (EngineReducer.fire ignores it); because the queue is
 * serial it can never leave a scheduled alert unarmed.
 *
 * A block that throws is logged (the class only) and its first failure is kept for the next
 * [whenIdle] marker, so a caller that has to answer for the calls (the `applyPlan` and `testAlarm`
 * replies) can still tell that one failed. The failure is process-wide: the next marker takes it,
 * whoever posted that marker. A receiver's [finishWhenAlarmCallsIdle] marker takes it too and ignores
 * it, because a broadcast finishes either way. The queue carries on in every case.
 */
object AlarmCalls {
    private const val TAG = "TMinusEngine"

    /** The first failure of a block since the last marker ran; markers take it. */
    private val pendingFailure = AtomicReference<Throwable?>(null)

    /**
     * Where blocks run. Tests replace it: Robolectric runs with one that calls the block on the
     * caller's thread, and a test of the threading installs a queue it runs by hand. Replacing it
     * also drops a failure the old queue kept and resets [failureHook] to null, so a test starts
     * clean and one that installs its own queue gets no hook.
     */
    @VisibleForTesting
    @Volatile
    internal var executor: Executor = Executors.newSingleThreadExecutor { runnable ->
        Thread(runnable, "tminus-alarm-calls").also { it.isDaemon = true }
    }
        set(value) {
            field = value
            pendingFailure.set(null)
            failureHook = null
        }

    /**
     * Called by [run] with the exception of a block that threw, after it was logged and kept and
     * while no lock is held. The default is null: the failure is only logged and kept for the next
     * marker. A test that runs blocks on its own thread sets one that rethrows, so a failed alarm call
     * fails that test, as it did before the calls moved to this queue. Assigning [executor] resets it
     * to null, so set it after the executor.
     */
    @VisibleForTesting
    @Volatile
    internal var failureHook: ((Throwable) -> Unit)? = null

    /** Posts [block]. Blocks run one at a time, in the order they were posted. */
    fun run(block: () -> Unit) {
        executor.execute {
            try {
                block()
            } catch (e: Exception) {
                // The class only: a message can quote a package name, a link or an event's text.
                Log.e(TAG, "Alarm call failed: ${e.javaClass.simpleName}")
                pendingFailure.compareAndSet(null, e)
                failureHook?.invoke(e)
            }
        }
    }

    /**
     * Posts a marker. [callback] runs after every block posted before it, on the executor's thread,
     * with the first failure of those blocks since the previous marker ran (null if none), and clears
     * that failure.
     */
    fun whenIdle(callback: (failure: Throwable?) -> Unit) {
        executor.execute {
            val failure = pendingFailure.getAndSet(null)
            try {
                callback(failure)
            } catch (e: Exception) {
                // Nothing may escape on this thread: an uncaught exception here ends the app.
                Log.e(TAG, "Alarm call callback failed: ${e.javaClass.simpleName}")
            }
        }
    }

    /**
     * Blocks the calling thread until a marker posted now has run; false if [timeoutMs] passed first.
     * For instrumented tests, which assert on what AlarmManager holds after a receiver returned. Never
     * call it on the thread that runs the queue.
     */
    @VisibleForTesting
    fun awaitIdle(timeoutMs: Long): Boolean {
        val idle = CountDownLatch(1)
        whenIdle { idle.countDown() }
        return idle.await(timeoutMs, TimeUnit.MILLISECONDS)
    }
}

/**
 * Keeps this receiver's broadcast open until [AlarmCalls] has run everything posted so far, so
 * Android keeps the process alive while the alarms are armed, within the broadcast's time limit (a
 * re-arm that outlasts it is cut off, which is why AlarmScheduler.rearmAll posts the nearest alarms
 * first). Call it at the end of onReceive, on every path that posted alarm calls. goAsync() returns
 * null when onReceive was called directly (in tests), and then there is nothing to finish. It
 * ignores the failure the marker takes: a broadcast finishes either way.
 */
fun BroadcastReceiver.finishWhenAlarmCallsIdle() {
    val pending = goAsync()
    AlarmCalls.whenIdle { pending?.finish() }
}

/**
 * Runs [block] on the main thread: at once if the caller is on it, else posted to its looper. The
 * replies of the method channels go back this way, because they are sent from AlarmCalls' thread.
 */
internal fun onMainThread(block: () -> Unit) {
    val main = Looper.getMainLooper()
    if (Looper.myLooper() == main) block() else Handler(main).post { block() }
}
