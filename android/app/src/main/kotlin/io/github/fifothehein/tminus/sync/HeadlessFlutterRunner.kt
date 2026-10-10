package io.github.fifothehein.tminus.sync

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.Log
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.github.fifothehein.tminus.engine.AlarmEngineChannel

/**
 * Boots a FlutterEngine without a UI and runs Dart `syncMain(trigger)` in it (spec §3, §7). The
 * engine gets its own `alarm_engine` and `tminus_sync` channels; `syncMain` reports its outcome
 * through `tminus_sync.finished`, and the engine is destroyed. Call [run] on the main thread.
 *
 * Every way a run can end (Dart's report, the timeout, WorkManager stopping the worker, an engine
 * that will not start) goes through one teardown. It detaches both channels before the engine is
 * destroyed, so a sync that is cut short never leaves the sync lock behind (Plan 4 decision), and
 * it always reports an outcome to the worker, so the worker is never left waiting.
 */
class HeadlessFlutterRunner(
    private val context: Context,
    private val timeoutMs: Long = TIMEOUT_MS,
) : SyncRunner {
    override fun run(trigger: String, done: (String) -> Unit): () -> Unit {
        val main = Handler(Looper.getMainLooper())
        val token = Any()
        var engine: FlutterEngine? = null
        var alarm: AlarmEngineChannel? = null
        var sync: SyncChannel? = null
        var finished = false

        // A step that fails must not skip the steps after it, or the report to the worker.
        fun teardown(step: String, action: () -> Unit) {
            try {
                action()
            } catch (e: Exception) {
                Log.e(TAG, "Headless sync ($trigger): $step failed", e)
            }
        }

        fun finish(outcome: String) {
            if (finished) return
            finished = true
            main.removeCallbacksAndMessages(token)
            teardown("sync channel detach") { sync?.detach() } // releases a sync lock Dart still held
            teardown("alarm channel detach") { alarm?.detach() }
            teardown("engine destroy") { engine?.destroy() }
            engine = null
            Log.i(TAG, "Headless sync ($trigger) finished: $outcome")
            done(outcome)
        }

        try {
            val e = FlutterEngine(context) // starts the Flutter loader and registers the plugins
            engine = e
            val messenger = e.dartExecutor.binaryMessenger
            alarm = AlarmEngineChannel.register(messenger, context)
            sync = SyncChannel.register(messenger, context) { outcome -> main.post { finish(outcome) } }
            val bundle = FlutterInjector.instance().flutterLoader().findAppBundlePath()
            e.dartExecutor.executeDartEntrypoint(DartExecutor.DartEntrypoint(bundle, ENTRYPOINT), listOf(trigger))
            main.postAtTime({ finish(SyncWorker.OUTCOME_RETRY) }, token, SystemClock.uptimeMillis() + timeoutMs)
        } catch (e: Exception) {
            Log.e(TAG, "Headless sync ($trigger) could not start", e)
            finish(SyncWorker.OUTCOME_RETRY)
        }
        return { main.post { finish(SyncWorker.OUTCOME_RETRY) } }
    }

    companion object {
        /** The `@pragma('vm:entry-point')` function in lib/main.dart. */
        const val ENTRYPOINT = "syncMain"

        /** WorkManager stops a worker after 10 min; give up well before. */
        const val TIMEOUT_MS = 8 * 60 * 1000L
        private const val TAG = "TMinusSync"
    }
}
