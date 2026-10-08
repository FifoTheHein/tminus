package io.github.fifothehein.tminus.sync

import android.content.Context
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.TimeZone

/**
 * One sync at a time across the UI isolate and the headless one (Plan 4 decision): both run in the
 * app process, so a process-wide lease is enough. A lease that is not released (a killed engine)
 * runs out by itself.
 */
class SyncLock(private val clock: () -> Long = System::currentTimeMillis) {
    private var owner: String? = null
    private var expiresAt = 0L

    @Synchronized
    fun acquire(owner: String, leaseMs: Long): Boolean {
        val now = clock()
        if (this.owner != null && this.owner != owner && now < expiresAt) return false
        this.owner = owner
        expiresAt = now + leaseMs
        return true
    }

    @Synchronized
    fun release(owner: String) {
        if (this.owner == owner) this.owner = null
    }

    companion object {
        val shared = SyncLock()
    }
}

/**
 * The `tminus_sync` MethodChannel (Plan 4): what Dart's sync needs from Android besides the alarm
 * engine. Registered on the app's engine (MainActivity) and on each headless sync engine.
 */
class SyncChannel internal constructor(
    context: Context,
    private val onFinished: ((String) -> Unit)?,
    private val lock: SyncLock = SyncLock.shared,
    private val scheduler: SyncScheduler = SyncScheduler(context),
    private val preSync: PreSyncScheduler = PreSyncScheduler(context),
    private val notifications: SyncNotifications = SyncNotifications(context),
) : MethodChannel.MethodCallHandler {
    private val held = mutableSetOf<String>()

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "deviceZone" -> result.success(TimeZone.getDefault().id)
                "acquireLock" -> {
                    val owner = call.string("owner")
                    val acquired = lock.acquire(owner, call.long("leaseMs"))
                    if (acquired) held += owner
                    result.success(acquired)
                }
                "releaseLock" -> {
                    val owner = call.string("owner")
                    lock.release(owner)
                    held -= owner
                    result.success(null)
                }
                "configure" -> {
                    // Read and check every argument before touching a scheduler: a bad call changes nothing.
                    val watchCalendars = call.bool("watchCalendars")
                    val preSyncTimes = call.longs("preSyncTimesMs")
                    scheduler.ensurePeriodic()
                    scheduler.setCalendarWatch(watchCalendars)
                    preSync.setTimes(preSyncTimes)
                    result.success(null)
                }
                "requestSync" -> {
                    scheduler.runNow(call.string("trigger"), expedited = true)
                    result.success(null)
                }
                "postSourceNotice" -> {
                    notifications.post(call.string("kind"), call.string("sourceId"), call.string("title"), call.string("text"))
                    result.success(null)
                }
                "cancelSourceNotice" -> {
                    notifications.cancel(call.string("kind"), call.string("sourceId"))
                    result.success(null)
                }
                "finished" -> {
                    onFinished?.invoke(call.string("outcome"))
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        } catch (e: IllegalArgumentException) {
            result.error("bad_args", e.message, null)
        } catch (e: ClassCastException) {
            result.error("bad_args", e.message, null)
        } catch (e: Exception) {
            Log.e(TAG, "tminus_sync.${call.method} failed", e)
            result.error("sync_error", e.message, null)
        }
    }

    /** Releases every lock this engine took; its Flutter engine is going away. */
    fun detach() {
        held.forEach(lock::release)
        held.clear()
    }

    private fun MethodCall.string(key: String): String =
        argument<String>(key) ?: throw IllegalArgumentException("$key missing")

    private fun MethodCall.long(key: String): Long =
        argument<Number>(key)?.toLong() ?: throw IllegalArgumentException("$key missing")

    private fun MethodCall.bool(key: String): Boolean =
        argument<Boolean>(key) ?: throw IllegalArgumentException("$key missing")

    private fun MethodCall.longs(key: String): List<Long> {
        val values = argument<List<*>>(key) ?: throw IllegalArgumentException("$key missing")
        return values.map { (it as? Number)?.toLong() ?: throw IllegalArgumentException("$key must hold numbers") }
    }

    companion object {
        const val NAME = "tminus_sync"
        private const val TAG = "TMinusSync"

        /** [onFinished] receives `syncMain()`'s outcome; only the headless runner passes one. */
        fun register(messenger: BinaryMessenger, context: Context, onFinished: ((String) -> Unit)? = null): SyncChannel {
            val handler = SyncChannel(context.applicationContext, onFinished)
            MethodChannel(messenger, NAME).setMethodCallHandler(handler)
            return handler
        }
    }
}
