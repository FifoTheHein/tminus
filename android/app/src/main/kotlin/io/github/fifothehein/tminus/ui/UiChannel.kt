package io.github.fifothehein.tminus.ui

import android.Manifest
import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.pm.PackageManager
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.util.Log
import androidx.core.app.ActivityCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import androidx.core.content.IntentCompat
import androidx.core.content.pm.PackageInfoCompat
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.FileNotFoundException
import java.io.IOException
import java.io.OutputStream
import java.util.concurrent.Executor
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.RejectedExecutionException

/**
 * The `tminus_ui` MethodChannel (Plan 5 decision 1): what the screens need from Android that Flutter
 * does not give. Registered on the UI engine only, because it needs the activity. One request that
 * waits for another screen (a permission dialog, a picker) at a time; a second gets `busy`.
 *
 * Errors carry a code only: an exception message can name a file or a link.
 */
class UiChannel internal constructor(
    private val activity: Activity,
    private val io: Executor = Executors.newSingleThreadExecutor(),
) : MethodChannel.MethodCallHandler {
    private val main = Handler(Looper.getMainLooper())
    private var pending: Pending? = null

    private sealed interface Pending { val result: MethodChannel.Result }
    private class PermissionRequest(override val result: MethodChannel.Result, val permission: String) : Pending
    private class TonePick(override val result: MethodChannel.Result) : Pending
    private class CreateDoc(override val result: MethodChannel.Result, val text: String) : Pending
    private class OpenDoc(override val result: MethodChannel.Result) : Pending
    private class TooLarge : IOException()

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "requestPermission" -> requestPermission(call.string("kind"), result)
                "pickAlarmTone" -> start(TonePick(result), REQ_TONE, toneIntent(call.argument<String>("current")))
                "toneTitle" -> result.success(toneTitle(call.argument<String>("uri")))
                "openUrl" -> result.success(openUrl(call.string("url")))
                "openAppDetails" -> {
                    activity.startActivity(
                        Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.fromParts("package", activity.packageName, null)),
                    )
                    result.success(null)
                }
                "createDocument" -> start(
                    CreateDoc(result, call.string("text")),
                    REQ_CREATE,
                    Intent(Intent.ACTION_CREATE_DOCUMENT)
                        .addCategory(Intent.CATEGORY_OPENABLE)
                        .setType(JSON)
                        .putExtra(Intent.EXTRA_TITLE, call.string("name")),
                )
                "openDocument" -> start(
                    OpenDoc(result),
                    REQ_OPEN,
                    Intent(Intent.ACTION_OPEN_DOCUMENT)
                        .addCategory(Intent.CATEGORY_OPENABLE)
                        .setType("*/*")
                        .putExtra(Intent.EXTRA_MIME_TYPES, arrayOf(JSON, "text/plain", "application/octet-stream")),
                )
                "deviceInfo" -> result.success(deviceInfo())
                else -> result.notImplemented()
            }
        } catch (e: IllegalArgumentException) {
            result.error("bad_args", null, null)
        } catch (e: ActivityNotFoundException) {
            result.error("no_activity", null, null)
        } catch (e: Exception) {
            Log.e(TAG, "tminus_ui.${call.method} failed: ${e.javaClass.simpleName}")
            result.error("ui_error", null, null)
        }
    }

    /** True when [requestCode] was ours. */
    fun onRequestPermissionsResult(requestCode: Int, grantResults: IntArray): Boolean {
        if (requestCode != REQ_PERMISSION) return false
        val request = pending as? PermissionRequest ?: return true
        pending = null
        request.result.success(
            when {
                grantResults.isEmpty() -> DENIED // the dialog was interrupted
                grantResults[0] == PackageManager.PERMISSION_GRANTED -> GRANTED
                ActivityCompat.shouldShowRequestPermissionRationale(activity, request.permission) -> DENIED
                else -> PERMANENTLY_DENIED
            },
        )
        return true
    }

    /**
     * True when [requestCode] was ours. A document picker's answer is used only when it is a `content` uri
     * of another app's provider (see [isForeignContentUri]); anything else is answered as a failed read or
     * write (`io_error`), and nothing is opened.
     */
    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQ_TONE && requestCode != REQ_CREATE && requestCode != REQ_OPEN) return false
        val request = pending ?: return true
        pending = null
        val uri = if (resultCode == Activity.RESULT_OK) data?.data else null
        when (request) {
            is TonePick -> request.result.success(toneResult(resultCode, data))
            is CreateDoc -> when {
                uri == null -> request.result.success(false)
                !isForeignContentUri(uri) -> refuse(request.result, "createDocument")
                else -> background(request.result, "createDocument") {
                    writeDocument(uri, request.text)
                    true
                }
            }
            is OpenDoc -> when {
                uri == null -> request.result.success(null)
                !isForeignContentUri(uri) -> refuse(request.result, "openDocument")
                else -> background(request.result, "openDocument") { readCapped(uri) }
            }
            is PermissionRequest -> request.result.error("bad_state", null, null)
        }
        return true
    }

    /** The activity is going away: a waiting request will never be answered by Android. */
    fun detach() {
        pending?.result?.error("cancelled", null, null)
        pending = null
        // Frees the I/O thread. A read or write already running still answers; the executor only stops
        // taking new work (the tests pass a plain Executor, which has nothing to shut down).
        (io as? ExecutorService)?.shutdown()
    }

    private fun requestPermission(kind: String, result: MethodChannel.Result) {
        val permission = when (kind) {
            "calendar" -> Manifest.permission.READ_CALENDAR
            "notifications" -> {
                if (Build.VERSION.SDK_INT < 33) {
                    // No runtime permission before Android 13: report the switch, and Dart opens settings.
                    result.success(if (NotificationManagerCompat.from(activity).areNotificationsEnabled()) GRANTED else DENIED)
                    return
                }
                Manifest.permission.POST_NOTIFICATIONS
            }
            else -> throw IllegalArgumentException("kind")
        }
        if (ContextCompat.checkSelfPermission(activity, permission) == PackageManager.PERMISSION_GRANTED) {
            result.success(GRANTED)
            return
        }
        if (pending != null) {
            result.error("busy", null, null)
            return
        }
        pending = PermissionRequest(result, permission)
        ActivityCompat.requestPermissions(activity, arrayOf(permission), REQ_PERMISSION)
    }

    private fun start(request: Pending, code: Int, intent: Intent) {
        if (pending != null) {
            request.result.error("busy", null, null)
            return
        }
        pending = request
        try {
            activity.startActivityForResult(intent, code)
        } catch (e: Exception) {
            // The screen never opened, so Android will not answer this request later: free the slot (or every
            // later request would be `busy`, and detach() would answer this one a second time) and answer now.
            pending = null
            if (e is ActivityNotFoundException) {
                request.result.error("no_activity", null, null)
            } else {
                Log.e(TAG, "picker did not start: ${e.javaClass.simpleName}")
                request.result.error("ui_error", null, null)
            }
        }
    }

    private fun toneIntent(current: String?): Intent = Intent(RingtoneManager.ACTION_RINGTONE_PICKER)
        .putExtra(RingtoneManager.EXTRA_RINGTONE_TYPE, RingtoneManager.TYPE_ALARM)
        .putExtra(RingtoneManager.EXTRA_RINGTONE_SHOW_DEFAULT, true)
        .putExtra(RingtoneManager.EXTRA_RINGTONE_SHOW_SILENT, false)
        .putExtra(RingtoneManager.EXTRA_RINGTONE_DEFAULT_URI, Settings.System.DEFAULT_ALARM_ALERT_URI)
        .putExtra(
            RingtoneManager.EXTRA_RINGTONE_EXISTING_URI,
            current?.let(Uri::parse) ?: Settings.System.DEFAULT_ALARM_ALERT_URI,
        )

    private fun toneResult(resultCode: Int, data: Intent?): Map<String, Any?> {
        if (resultCode != Activity.RESULT_OK || data == null) return mapOf("picked" to false)
        val uri = try {
            IntentCompat.getParcelableExtra(data, RingtoneManager.EXTRA_RINGTONE_PICKED_URI, Uri::class.java)
        } catch (e: Exception) {
            // A parcel we cannot read (BadParcelableException and friends) counts as a cancelled pick.
            Log.w(TAG, "tone result unreadable: ${e.javaClass.simpleName}")
            return mapOf("picked" to false)
        }
        val isDefault = uri == null || uri == Settings.System.DEFAULT_ALARM_ALERT_URI
        return mapOf(
            "picked" to true,
            "uri" to if (isDefault) null else uri.toString(),
            "title" to if (isDefault) DEFAULT_TONE_TITLE else (toneTitle(uri.toString()) ?: CUSTOM_TONE_TITLE),
        )
    }

    private fun toneTitle(uri: String?): String? {
        if (uri == null) return DEFAULT_TONE_TITLE
        return runCatching { RingtoneManager.getRingtone(activity, Uri.parse(uri))?.getTitle(activity) }.getOrNull()
    }

    private fun openUrl(url: String): Boolean {
        val uri = Uri.parse(url)
        if (uri.scheme?.lowercase() != "https" || uri.host.isNullOrEmpty()) return false
        return try {
            activity.startActivity(Intent(Intent.ACTION_VIEW, uri).addCategory(Intent.CATEGORY_BROWSABLE))
            true
        } catch (e: ActivityNotFoundException) {
            false
        }
    }

    @Suppress("DEPRECATION") // getPackageInfo(String, Int) is fine for our own package on API 26+
    private fun deviceInfo(): Map<String, Any> {
        val info = activity.packageManager.getPackageInfo(activity.packageName, 0)
        return mapOf(
            "versionName" to (info.versionName ?: ""),
            "versionCode" to PackageInfoCompat.getLongVersionCode(info),
            "manufacturer" to Build.MANUFACTURER,
            "sdkInt" to Build.VERSION.SDK_INT,
        )
    }

    private fun readCapped(uri: Uri): String {
        val out = ByteArrayOutputStream()
        activity.contentResolver.openInputStream(uri)!!.use { input ->
            val buffer = ByteArray(8192)
            while (true) {
                val n = input.read(buffer)
                if (n < 0) break
                out.write(buffer, 0, n)
                if (out.size() > MAX_DOCUMENT_BYTES) throw TooLarge()
            }
        }
        return out.toString(Charsets.UTF_8.name())
    }

    /**
     * Writes [text] to a document the user just created. Some document providers refuse the truncating
     * mode `wt`; a document that was just created is empty, so plain `w` does the same job.
     */
    private fun writeDocument(uri: Uri, text: String) {
        val resolver = activity.contentResolver
        val out: OutputStream? = try {
            resolver.openOutputStream(uri, "wt")
        } catch (e: FileNotFoundException) {
            resolver.openOutputStream(uri, "w")
        } catch (e: IllegalArgumentException) {
            resolver.openOutputStream(uri, "w")
        } catch (e: UnsupportedOperationException) {
            resolver.openOutputStream(uri, "w")
        }
        (out ?: throw FileNotFoundException()).use { it.write(text.toByteArray(Charsets.UTF_8)) }
    }

    /**
     * A picker is another app, and its answer is not trusted. Only a `content` uri is opened, and not one
     * of this app's own providers: a `file:` uri or an own uri would make the app read or overwrite its
     * private files with its own rights. The authority is read the way the resolver reads it when it finds
     * the provider: percent-decoded, with everything up to the last `@` (a user id) dropped. `Uri.getHost`
     * is not used: it keeps a `%40` as text, so `0%40<package>.x` would pass as foreign and still reach an
     * own provider. A provider of this app has an authority that starts with the package name. A `content`
     * uri without an authority names no provider at all; opening it fails like any unreadable document.
     */
    private fun isForeignContentUri(uri: Uri): Boolean {
        if (uri.scheme != "content") return false
        val authority = uri.authority?.substringAfterLast('@')?.lowercase().orEmpty()
        return !authority.startsWith(activity.packageName.lowercase())
    }

    /** Answers a refused picker result the way a failed read or write is answered. Logs no uri. */
    private fun refuse(result: MethodChannel.Result, what: String) {
        Log.w(TAG, "$what refused a picker result that is not another app's content uri")
        result.error("io_error", null, null)
    }

    /** Runs file I/O off the main thread and answers on it. */
    private fun background(result: MethodChannel.Result, what: String, work: () -> Any?) {
        try {
            io.execute {
                val outcome = runCatching(work)
                main.post {
                    outcome.fold(
                        { result.success(it) },
                        { e ->
                            Log.w(TAG, "$what failed: ${e.javaClass.simpleName}")
                            result.error(if (e is TooLarge) "too_large" else "io_error", null, null)
                        },
                    )
                }
            }
        } catch (e: RejectedExecutionException) {
            // detach() shut the executor down; the screen is gone, but a request must still be answered once.
            Log.w(TAG, "$what could not start: ${e.javaClass.simpleName}")
            result.error("io_error", null, null)
        }
    }

    private fun MethodCall.string(key: String): String =
        argument<String>(key) ?: throw IllegalArgumentException("$key missing")

    companion object {
        const val NAME = "tminus_ui"
        const val REQ_PERMISSION = 0x5501
        const val REQ_TONE = 0x5502
        const val REQ_CREATE = 0x5503
        const val REQ_OPEN = 0x5504
        const val GRANTED = "granted"
        const val DENIED = "denied"
        const val PERMANENTLY_DENIED = "permanentlyDenied"
        const val DEFAULT_TONE_TITLE = "Default alarm tone"
        const val CUSTOM_TONE_TITLE = "Custom tone"
        const val MAX_DOCUMENT_BYTES = 1 shl 20
        private const val JSON = "application/json"
        private const val TAG = "TMinusUi"

        fun register(messenger: BinaryMessenger, activity: Activity): UiChannel {
            val handler = UiChannel(activity)
            MethodChannel(messenger, NAME).setMethodCallHandler(handler)
            return handler
        }
    }
}
