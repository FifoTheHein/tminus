package io.github.fifothehein.tminus.ui

import android.Manifest
import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.pm.PackageManager
import android.media.RingtoneManager
import android.net.Uri
import android.os.BadParcelableException
import android.os.Looper
import android.os.Parcelable
import android.provider.Settings
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileNotFoundException
import java.util.concurrent.Executor
import java.util.concurrent.Executors

@RunWith(RobolectricTestRunner::class)
class UiChannelTest {
    private class Captured : MethodChannel.Result {
        var calls = 0
        var value: Any? = null
        var error: String? = null
        override fun success(result: Any?) { calls++; value = result }
        override fun error(code: String, message: String?, details: Any?) { calls++; error = code }
        override fun notImplemented() { calls++; error = "notImplemented" }
    }

    private lateinit var activity: Activity
    private lateinit var channel: UiChannel
    private val direct = Executor { it.run() }

    @Before
    fun setUp() {
        activity = Robolectric.buildActivity(Activity::class.java).setup().get()
        channel = UiChannel(activity, direct)
    }

    private fun call(method: String, args: Map<String, Any?> = emptyMap()) =
        Captured().also { channel.onMethodCall(MethodCall(method, args), it) }

    @Test
    fun `a granted permission answers granted without asking`() {
        shadowOf(activity.application).grantPermissions(Manifest.permission.READ_CALENDAR)
        val r = call("requestPermission", mapOf("kind" to "calendar"))
        assertEquals("granted", r.value)
        assertNull(shadowOf(activity).lastRequestedPermission)
    }

    @Test
    fun `a denial with a rationale is denied, without one it is permanently denied`() {
        val first = call("requestPermission", mapOf("kind" to "calendar"))
        assertEquals(0, first.calls) // waiting for the dialog
        shadowOf(activity.packageManager).setShouldShowRequestPermissionRationale(Manifest.permission.READ_CALENDAR, true)
        channel.onRequestPermissionsResult(UiChannel.REQ_PERMISSION, intArrayOf(PackageManager.PERMISSION_DENIED))
        assertEquals("denied", first.value)

        val second = call("requestPermission", mapOf("kind" to "calendar"))
        shadowOf(activity.packageManager).setShouldShowRequestPermissionRationale(Manifest.permission.READ_CALENDAR, false)
        channel.onRequestPermissionsResult(UiChannel.REQ_PERMISSION, intArrayOf(PackageManager.PERMISSION_DENIED))
        assertEquals("permanentlyDenied", second.value)
    }

    @Test
    fun `an interrupted request with no results is denied`() {
        val r = call("requestPermission", mapOf("kind" to "calendar"))
        channel.onRequestPermissionsResult(UiChannel.REQ_PERMISSION, intArrayOf())
        assertEquals("denied", r.value)
    }

    @Test
    fun `a second request while one waits is busy, and detach cancels the first`() {
        val first = call("requestPermission", mapOf("kind" to "calendar"))
        val second = call("pickAlarmTone", mapOf("current" to null))
        assertEquals("busy", second.error)
        channel.detach()
        assertEquals("cancelled", first.error)
        assertEquals(1, first.calls)
    }

    @Test
    fun `openUrl starts only https links`() {
        assertEquals(false, call("openUrl", mapOf("url" to "http://teams.microsoft.com/l/meetup-join/x")).value)
        assertEquals(false, call("openUrl", mapOf("url" to "javascript:alert(1)")).value)
        assertEquals(true, call("openUrl", mapOf("url" to "https://teams.microsoft.com/l/meetup-join/x")).value)
        val started = shadowOf(activity).nextStartedActivity
        assertEquals(Intent.ACTION_VIEW, started.action)
        assertEquals(Uri.parse("https://teams.microsoft.com/l/meetup-join/x"), started.data)
    }

    @Test
    fun `picking the default tone gives no uri, and cancelling gives not picked`() {
        val picked = call("pickAlarmTone", mapOf("current" to null))
        val data = Intent().putExtra(RingtoneManager.EXTRA_RINGTONE_PICKED_URI, Settings.System.DEFAULT_ALARM_ALERT_URI)
        channel.onActivityResult(UiChannel.REQ_TONE, Activity.RESULT_OK, data)
        assertEquals(mapOf("picked" to true, "uri" to null, "title" to UiChannel.DEFAULT_TONE_TITLE), picked.value)

        val cancelled = call("pickAlarmTone", mapOf("current" to null))
        channel.onActivityResult(UiChannel.REQ_TONE, Activity.RESULT_CANCELED, null)
        assertEquals(mapOf("picked" to false), cancelled.value)
    }

    @Test
    fun `a cancelled save answers false and a cancelled open answers null`() {
        val save = call("createDocument", mapOf("name" to "x.json", "text" to "{}"))
        channel.onActivityResult(UiChannel.REQ_CREATE, Activity.RESULT_CANCELED, null)
        assertEquals(false, save.value)
        val open = call("openDocument")
        channel.onActivityResult(UiChannel.REQ_OPEN, Activity.RESULT_CANCELED, null)
        assertNull(open.value)
        assertEquals(1, open.calls)
    }

    @Test
    fun `a result for another request code is not ours`() {
        assertFalse(channel.onActivityResult(0x1234, Activity.RESULT_OK, null))
        assertFalse(channel.onRequestPermissionsResult(0x1234, intArrayOf()))
    }

    /** An activity whose system refuses to open any picker. */
    class RefusingActivity : Activity() {
        override fun startActivityForResult(intent: Intent, requestCode: Int) {
            throw SecurityException("refused")
        }
    }

    /** An activity on a phone that has no app for the picker's intent. */
    class NoPickerActivity : Activity() {
        override fun startActivityForResult(intent: Intent, requestCode: Int) {
            throw ActivityNotFoundException("no picker")
        }
    }

    /** The stream a picked document is read from; it remembers that it was closed. */
    private class ClosingStream(bytes: ByteArray) : ByteArrayInputStream(bytes) {
        var closed = false

        override fun close() {
            closed = true
        }
    }

    /** A picker answer from another app whose extras cannot be read: reading a parcelable extra throws. */
    private class UnreadableIntent : Intent() {
        @Suppress("DEPRECATION", "OVERRIDE_DEPRECATION")
        override fun <T : Parcelable?> getParcelableExtra(name: String?): T? = throw BadParcelableException("unreadable")

        override fun <T : Any?> getParcelableExtra(name: String?, clazz: Class<T>): T? =
            throw BadParcelableException("unreadable")
    }

    /** The shadow of the resolver that UiChannel reads and writes through (the activity's own). */
    private val resolverShadow get() = shadowOf(activity.contentResolver)

    /** The picker answers the waiting request with [uri]; file I/O answers Dart by posting to the main thread. */
    private fun picked(requestCode: Int, uri: Uri) {
        channel.onActivityResult(requestCode, Activity.RESULT_OK, Intent().setData(uri))
        shadowOf(Looper.getMainLooper()).idle()
    }

    @Test
    fun `a picker that cannot start answers once and frees the slot`() {
        val refusing = Robolectric.buildActivity(RefusingActivity::class.java).setup().get()
        val onRefusing = UiChannel(refusing, direct)
        fun callOnRefusing(method: String) =
            Captured().also { onRefusing.onMethodCall(MethodCall(method, emptyMap<String, Any?>()), it) }

        val first = callOnRefusing("pickAlarmTone")
        assertEquals("ui_error", first.error)
        assertEquals(1, first.calls)

        val second = callOnRefusing("openDocument") // `busy` if the first request still held the slot
        assertEquals("ui_error", second.error)
        assertEquals(1, second.calls)

        onRefusing.detach() // nothing waits, so nothing is answered a second time
        assertEquals(1, first.calls)
        assertEquals(1, second.calls)
    }

    @Test
    fun `a picker with no app to open it answers no_activity and frees the slot`() {
        val bare = Robolectric.buildActivity(NoPickerActivity::class.java).setup().get()
        val onBare = UiChannel(bare, direct)
        fun callOnBare(method: String) =
            Captured().also { onBare.onMethodCall(MethodCall(method, emptyMap<String, Any?>()), it) }

        val first = callOnBare("openDocument")
        assertEquals("no_activity", first.error)
        val second = callOnBare("pickAlarmTone") // `busy` if the first request still held the slot
        assertEquals("no_activity", second.error)

        onBare.detach()
        assertEquals(1, first.calls)
        assertEquals(1, second.calls)
    }

    @Test
    fun `a picker result that is not a content uri is refused`() {
        val file = File.createTempFile("picked", ".json")
        try {
            file.writeText("original")
            // A private file of this app, as a file: uri. The resolver is given streams for it, so that a
            // wrongly accepted uri shows as bytes written or a stream opened, whatever the JVM does with a path.
            val privateFile = Uri.parse("file:///data/data/${activity.packageName}/files/secret.json")
            val stream = ClosingStream("secret".toByteArray())
            val sink = ByteArrayOutputStream()
            resolverShadow.registerInputStream(privateFile, stream)
            resolverShadow.registerOutputStream(privateFile, sink)
            listOf(
                Uri.fromFile(file),
                privateFile,
                Uri.parse("https://example.com/x.json"),
                Uri.parse("android.resource://${activity.packageName}/raw/x"),
            ).forEach { uri ->
                val save = call("createDocument", mapOf("name" to "x.json", "text" to "overwritten"))
                picked(UiChannel.REQ_CREATE, uri)
                assertEquals("$uri", "io_error", save.error)
                assertEquals("$uri", 1, save.calls)

                val open = call("openDocument")
                picked(UiChannel.REQ_OPEN, uri)
                assertEquals("$uri", "io_error", open.error)
                assertNull("$uri", open.value)
                assertEquals("$uri", 1, open.calls)
            }
            assertEquals("original", file.readText())
            assertEquals("written to a private file", 0, sink.size())
            assertFalse("a private file was opened", stream.closed)
        } finally {
            file.delete()
        }
    }

    @Test
    fun `a picker result naming this app's own provider is refused`() {
        val own = activity.packageName
        listOf(
            "content://$own.provider/secret",
            "content://0@$own.provider/secret", // Android drops the user id when it finds the provider
            "content://0%40$own.provider/secret", // an encoded @ is decoded first, so it is a user id too
            "content://${own.uppercase()}.PROVIDER/secret",
        ).map(Uri::parse).forEach { uri ->
            val stream = ClosingStream("secret".toByteArray())
            val sink = ByteArrayOutputStream()
            resolverShadow.registerInputStream(uri, stream)
            resolverShadow.registerOutputStream(uri, sink)

            val open = call("openDocument")
            picked(UiChannel.REQ_OPEN, uri)
            val save = call("createDocument", mapOf("name" to "x.json", "text" to "overwritten"))
            picked(UiChannel.REQ_CREATE, uri)

            assertEquals("$uri", "io_error", open.error)
            assertEquals("$uri", "io_error", save.error)
            assertFalse("$uri: opened", stream.closed)
            assertEquals("$uri: written", 0, sink.size())
        }
    }

    @Test
    fun `an open document over 1 MiB is too large and its stream is closed`() {
        val uri = Uri.parse("content://com.example.docs/document/big")
        val stream = ClosingStream(ByteArray(UiChannel.MAX_DOCUMENT_BYTES + 1))
        resolverShadow.registerInputStream(uri, stream)

        val open = call("openDocument")
        picked(UiChannel.REQ_OPEN, uri)

        assertEquals("too_large", open.error)
        assertEquals(1, open.calls)
        assertTrue("the stream is closed", stream.closed)
    }

    @Test
    fun `a saved document holds the text`() {
        val uri = Uri.parse("content://com.example.docs/document/new")
        val sink = ByteArrayOutputStream()
        resolverShadow.registerOutputStream(uri, sink)
        val text = "{\"name\":\"Caf${Char(0xE9)}\"}" // e with an acute accent: two bytes in UTF-8

        val save = call("createDocument", mapOf("name" to "x.json", "text" to text))
        picked(UiChannel.REQ_CREATE, uri)

        assertEquals(true, save.value)
        assertEquals(1, save.calls)
        assertEquals(text, String(sink.toByteArray(), Charsets.UTF_8))
    }

    @Test
    fun `a provider that refuses the truncating mode still gets the text`() {
        listOf(FileNotFoundException(), IllegalArgumentException(), UnsupportedOperationException()).forEach { refusal ->
            val uri = Uri.parse("content://com.example.docs/document/${refusal.javaClass.simpleName}")
            val sink = ByteArrayOutputStream()
            var opens = 0
            // The first open is the one in mode `wt`, which this provider refuses; the second is plain `w`.
            resolverShadow.registerOutputStreamSupplier(uri) {
                if (opens++ == 0) throw refusal
                sink
            }

            val save = call("createDocument", mapOf("name" to "x.json", "text" to "{}"))
            picked(UiChannel.REQ_CREATE, uri)

            assertEquals("$uri", true, save.value)
            assertEquals("$uri", 2, opens)
            assertEquals("$uri", "{}", String(sink.toByteArray(), Charsets.UTF_8))
        }
    }

    @Test
    fun `an unreadable tone result counts as not picked`() {
        val picked = call("pickAlarmTone", mapOf("current" to null))
        channel.onActivityResult(UiChannel.REQ_TONE, Activity.RESULT_OK, UnreadableIntent())
        assertEquals(mapOf("picked" to false), picked.value)
        assertEquals(1, picked.calls)
    }

    @Test
    fun `detach stops the io thread`() {
        val executor = Executors.newSingleThreadExecutor()
        UiChannel(activity, executor).detach()
        assertTrue(executor.isShutdown)
    }
}
