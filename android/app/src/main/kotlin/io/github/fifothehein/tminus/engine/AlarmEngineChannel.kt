package io.github.fifothehein.tminus.engine

import android.app.NotificationManager
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.media.AudioManager
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import android.util.Log
import androidx.core.app.NotificationManagerCompat
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONException

/** Native side of the `alarm_engine` MethodChannel and the `alarm_engine/events` EventChannel (roadmap §3). */
class AlarmEngineChannel internal constructor(
    context: Context,
    private val store: PlanStore = PlanStore(context),
    private val scheduler: AlarmScheduler = AlarmScheduler(context, store),
    presenter: AlertPresenter = AndroidAlertPresenter(context, store),
    private val clock: () -> Long = System::currentTimeMillis,
) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {
    private val appContext: Context = context.applicationContext
    private val actions = EngineActions(context, presenter, store, scheduler, clock)
    private var stopListening: (() -> Unit)? = null

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "applyPlan" -> result.success(actions.applyPlan(EngineJson.parsePlan(call.mapArgs())).toMap())
                "getHealth" -> result.success(health())
                "testAlarm" -> {
                    testAlarm(call.mapArgs())
                    result.success(null)
                }
                "openPermissionSettings" -> {
                    openPermissionSettings(call.mapArgs())
                    result.success(null)
                }
                "drainEvents" -> result.success(EventQueue(appContext).drain().map { it.toMap() })
                else -> result.notImplemented()
            }
        } catch (e: IllegalArgumentException) {
            result.error("bad_args", e.message, null)
        } catch (e: JSONException) {
            result.error("bad_args", e.message, null)
        } catch (e: ClassCastException) {
            result.error("bad_args", e.message, null)
        } catch (e: Exception) {
            Log.e(TAG, "alarm_engine.${call.method} failed", e)
            result.error("engine_error", e.message, null)
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        stopListening?.invoke()
        stopListening = EngineEvents.addListener { events.success(it) }
    }

    override fun onCancel(arguments: Any?) = detach()

    /** Stops streaming live events to this engine only (onCancel, or its Flutter engine going away). */
    fun detach() {
        stopListening?.invoke()
        stopListening = null
    }

    private fun MethodCall.mapArgs(): Map<*, *> =
        arguments as? Map<*, *> ?: throw IllegalArgumentException("$method expects a map argument")

    private fun health(): Map<String, Any?> {
        val notifications = appContext.getSystemService(NotificationManager::class.java)
        val power = appContext.getSystemService(PowerManager::class.java)
        val audio = appContext.getSystemService(AudioManager::class.java)
        return mapOf(
            "notificationsEnabled" to NotificationManagerCompat.from(appContext).areNotificationsEnabled(),
            // The user can turn off just the "Ringing alarms" category: the alarm then rings with no
            // notification and no full-screen intent (additive to roadmap §3's getHealth shape).
            "ringingChannelEnabled" to
                (notifications.getNotificationChannel(NotificationFactory.CHANNEL_RINGING)?.importance != NotificationManager.IMPORTANCE_NONE),
            "canUseFullScreenIntent" to (Build.VERSION.SDK_INT < 34 || notifications.canUseFullScreenIntent()),
            "canScheduleExactAlarms" to scheduler.canScheduleExactAlarms(),
            "ignoringBatteryOptimizations" to power.isIgnoringBatteryOptimizations(appContext.packageName),
            "alarmStreamMuted" to (audio.getStreamVolume(AudioManager.STREAM_ALARM) == 0),
            "upcoming" to scheduler.upcoming(5).map {
                mapOf("id" to it.id, "fireAtUtcMs" to it.fireAtUtcMs, "strength" to it.strength.wire, "title" to it.event.title)
            },
        )
    }

    private fun testAlarm(args: Map<*, *>) {
        val strength = Strength.fromWire(args["strength"] as? String ?: throw IllegalArgumentException("strength missing"))
        val delaySec = (args["delaySec"] as? Number)?.toLong() ?: throw IllegalArgumentException("delaySec missing")
        require(delaySec >= 0) { "delaySec must not be negative" }
        val now = clock()
        val fireAt = now + delaySec * 1_000
        val start = fireAt + MINUTE_MS
        val alert = PlannedAlert(
            id = "test-$now",
            occurrenceKey = "${EngineState.TEST_KEY_PREFIX}$now",
            fireAtUtcMs = fireAt,
            offsetMinutes = 1,
            strength = strength,
            sound = Sound.DEFAULT,
            event = EventSnapshot(
                title = if (strength == Strength.ALARM) "Test alarm" else "Test heads-up",
                startUtcMs = start,
                endUtcMs = start + 30 * MINUTE_MS,
                location = null,
                joinUrl = null,
                color = TEST_COLOR,
            ),
            coalesceGroup = CoalesceGroups.groupFor(fireAt),
        )
        val t = store.update { s -> EngineReducer.addTest(s, alert).let { it.state to it } }
        t.toArm.forEach(scheduler::arm)
    }

    private fun openPermissionSettings(args: Map<*, *>) {
        val pkg = appContext.packageName
        val packageUri = Uri.parse("package:$pkg")
        val intent = when (val kind = args["kind"] as? String) {
            "notifications" -> notificationSettings(pkg)
            "fullScreenIntent" ->
                if (Build.VERSION.SDK_INT >= 34) Intent(Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT, packageUri)
                else notificationSettings(pkg)
            "exactAlarm" ->
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM, packageUri)
                else appDetails(packageUri)
            // Not ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS: that needs a permission Play restricts (spec §7).
            "batteryOptimization" -> Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
            "alarmVolume" -> Intent(Settings.ACTION_SOUND_SETTINGS)
            else -> throw IllegalArgumentException("Unknown permission kind: $kind")
        }
        try {
            appContext.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        } catch (e: ActivityNotFoundException) {
            appContext.startActivity(appDetails(packageUri).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        }
    }

    private fun notificationSettings(pkg: String) =
        Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE, pkg)

    private fun appDetails(packageUri: Uri) = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, packageUri)

    companion object {
        const val METHOD_CHANNEL = "alarm_engine"
        const val EVENT_CHANNEL = "alarm_engine/events"
        private const val TAG = "TMinusEngine"
        /** calendarBlue (dark): the brief's Work Outlook colour. */
        private const val TEST_COLOR = 0xFF6AA0F5L

        /** Registers both channels on [messenger]. Plan 4's headless engine calls this too. */
        fun register(messenger: BinaryMessenger, context: Context): AlarmEngineChannel {
            val handler = AlarmEngineChannel(context.applicationContext)
            MethodChannel(messenger, METHOD_CHANNEL).setMethodCallHandler(handler)
            EventChannel(messenger, EVENT_CHANNEL).setStreamHandler(handler)
            return handler
        }
    }
}
