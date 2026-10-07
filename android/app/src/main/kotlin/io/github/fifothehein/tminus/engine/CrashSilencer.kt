package io.github.fifothehein.tminus.engine

import android.util.Log

/**
 * A crash never leaves the alarm sounding. The MediaPlayer and the vibrator keep going on their own
 * threads after the main thread dies, and Android's crash handler can block for minutes behind a
 * "keeps stopping" dialog, during which no stop control works. This process-wide uncaught-exception
 * handler silences first, then hands the crash to the handler that was installed before it.
 */
internal object CrashSilencer {
    private const val TAG = "TMinusEngine"

    @Volatile
    private var silence: (() -> Unit)? = null

    private class Handler(val previous: Thread.UncaughtExceptionHandler?) : Thread.UncaughtExceptionHandler {
        override fun uncaughtException(thread: Thread, error: Throwable) {
            try {
                silence?.invoke()
            } catch (t: Throwable) {
                runCatching { Log.e(TAG, "Could not silence the alarm while crashing", t) }
            }
            previous?.uncaughtException(thread, error)
        }
    }

    /** Wraps the current default handler, once per process. Call on the main thread. */
    fun install() {
        val current = Thread.getDefaultUncaughtExceptionHandler()
        if (current is Handler) return
        Thread.setDefaultUncaughtExceptionHandler(Handler(current))
    }

    /** [stop] silences what is ringing now; null when nothing rings. */
    fun register(stop: (() -> Unit)?) {
        silence = stop
    }
}
