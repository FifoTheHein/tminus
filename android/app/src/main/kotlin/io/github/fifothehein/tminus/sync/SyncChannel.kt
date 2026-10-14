package io.github.fifothehein.tminus.sync

import android.content.Context
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.github.fifothehein.tminus.quiet.QuietStore
import io.github.fifothehein.tminus.quiet.QuietTileService
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
 * UI engines that want to hear when a headless sync finished (Plan 5 decision 6). Main thread only:
 * the headless runner reports from there, and so do the engines that attach and detach.
 */
object BackgroundSyncSignal {
    private val listeners = mutableSetOf<(String, String) -> Unit>()

    fun add(listener: (String, String) -> Unit) {
        listeners += listener
    }

    fun remove(listener: (String, String) -> Unit) {
        listeners -= listener
    }

    fun finished(trigger: String, outcome: String) {
        listeners.toList().forEach { listener ->
            try {
                listener(trigger, outcome)
            } catch (e: Exception) {
                Log.w("TMinusSync", "Background sync signal failed: ${e.javaClass.simpleName}")
            }
        }
    }
}

/**
 * The `tminus_sync` MethodChannel (Plan 4): what Dart's sync needs from Android besides the alarm
 * engine. Registered on the app's engine (MainActivity) and on each headless sync engine. Plan 5 adds
 * the install id, whether the app was ever updated, the quick-settings tile's waiting request and its
 * state mirror, and (on the UI engine only, through [attachUi]) the signal that a headless sync
 * finished.
 */
class SyncChannel internal constructor(
    private val context: Context,
    private val onFinished: ((String) -> Unit)?,
    private val lock: SyncLock = SyncLock.shared,
    private val scheduler: SyncScheduler = SyncScheduler(context),
    private val preSync: PreSyncScheduler = PreSyncScheduler(context),
    private val notifications: SyncNotifications = SyncNotifications(context),
    private val installId: InstallId = InstallId(context),
    private val quiet: QuietStore = QuietStore(context),
    private val onQuietChanged: () -> Unit = { QuietTileService.refresh(context) },
) : MethodChannel.MethodCallHandler {
    private val held = mutableSetOf<String>()

    /** The MethodChannel this handler answers on; [register] sets it. */
    internal var channel: MethodChannel? = null
    private var uiListener: ((String, String) -> Unit)? = null

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
                "installId" -> result.success(installId.get())
                "neverUpdated" -> result.success(neverUpdated())
                "takeQuietRequest" -> result.success(quiet.take()?.let { mapOf("action" to it.action, "atMs" to it.atMs) })
                "configure" -> {
                    // Read and check every argument before touching a scheduler: a bad call changes nothing.
                    val watchCalendars = call.bool("watchCalendars")
                    val preSyncTimes = call.longs("preSyncTimesMs")
                    // The quiet arguments are optional: a caller without them means no quiet mode.
                    val quietUntil = call.optionalLong("quietUntilMs")
                    val quietText = call.optionalString("quietText")
                    scheduler.ensurePeriodic()
                    scheduler.setCalendarWatch(watchCalendars)
                    preSync.setTimes(preSyncTimes)
                    quiet.mirror(quietUntil, quietText)
                    onQuietChanged()
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
            result.error("bad_args", null, null)
        } catch (e: ClassCastException) {
            result.error("bad_args", null, null)
        } catch (e: Exception) {
            // Never the message: it can carry a link, a path or a row's values.
            Log.e(TAG, "tminus_sync.${call.method} failed: ${e.javaClass.simpleName}")
            result.error("sync_error", null, null)
        }
    }

    /** The UI engine's channel: hears [BackgroundSyncSignal] until [detach]. */
    fun attachUi() {
        if (uiListener != null) return
        val listener: (String, String) -> Unit = { trigger, outcome ->
            channel?.invokeMethod("syncFinished", mapOf("trigger" to trigger, "outcome" to outcome))
        }
        uiListener = listener
        BackgroundSyncSignal.add(listener)
    }

    /** Releases every lock this engine took and stops listening; its Flutter engine is going away. */
    fun detach() {
        held.forEach(lock::release)
        held.clear()
        uiListener?.let { BackgroundSyncSignal.remove(it) }
        uiListener = null
    }

    /**
     * True when this package has never been updated: Android sets both times at install and moves
     * the update time on every update. Dart reads it to tell a backup of an old build, restored onto a
     * new phone, from an upgrade. Any failure answers false, which is the upgrade reading.
     */
    @Suppress("DEPRECATION") // getPackageInfo(String, Int) is fine for our own package on API 26+
    private fun neverUpdated(): Boolean = try {
        val info = context.packageManager.getPackageInfo(context.packageName, 0)
        info.firstInstallTime == info.lastUpdateTime
    } catch (e: Exception) {
        Log.w(TAG, "tminus_sync.neverUpdated failed: ${e.javaClass.simpleName}")
        false
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

    /** Null when the key is absent or null; anything else that is not a number is a bad argument. */
    private fun MethodCall.optionalLong(key: String): Long? = when (val value = argument<Any>(key)) {
        null -> null
        is Number -> value.toLong()
        else -> throw IllegalArgumentException("$key must be a number")
    }

    /** Null when the key is absent or null; anything else that is not a string is a bad argument. */
    private fun MethodCall.optionalString(key: String): String? = when (val value = argument<Any>(key)) {
        null -> null
        is String -> value
        else -> throw IllegalArgumentException("$key must be a string")
    }

    companion object {
        const val NAME = "tminus_sync"
        private const val TAG = "TMinusSync"

        /** [onFinished] receives `syncMain()`'s outcome; only the headless runner passes one. */
        fun register(messenger: BinaryMessenger, context: Context, onFinished: ((String) -> Unit)? = null): SyncChannel {
            val handler = SyncChannel(context.applicationContext, onFinished)
            handler.channel = MethodChannel(messenger, NAME).also { it.setMethodCallHandler(handler) }
            return handler
        }
    }
}
