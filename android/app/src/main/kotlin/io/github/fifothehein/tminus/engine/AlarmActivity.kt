package io.github.fifothehein.tminus.engine

import android.app.KeyguardManager
import android.os.Build
import android.os.Bundle
import android.view.KeyEvent
import android.view.WindowManager
import androidx.activity.ComponentActivity
import androidx.activity.OnBackPressedCallback
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue

/** Full-screen alarm over the lock screen (spec §7, brief §9). Shows RingingSession and closes when it empties. */
class AlarmActivity : ComponentActivity() {
    private var alerts by mutableStateOf<List<PlannedAlert>>(emptyList())
    private var unsubscribe: (() -> Unit)? = null
    private var joining = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        showOverLockScreen()
        enableEdgeToEdge()
        onBackPressedDispatcher.addCallback(
            this,
            object : OnBackPressedCallback(true) {
                // Back never dismisses an alarm: use a button or a volume key.
                override fun handleOnBackPressed() = Unit
            },
        )
        alerts = RingingSession.alerts
        if (alerts.isEmpty()) {
            finish()
            return
        }
        unsubscribe = RingingSession.observe { current ->
            alerts = current
            if (current.isEmpty() && !joining) finish()
        }
        val fonts = AlarmFonts.load(this)
        val text = AlertText.forDevice(this)
        setContent {
            AlarmScreen(
                alerts = alerts,
                fonts = fonts,
                text = text,
                callbacks = AlarmCallbacks(
                    onJoin = ::join,
                    onDismiss = { id -> actions().dismiss(listOf(id)) },
                    onDismissAll = { actions().dismissAll(alerts.map { it.id }) },
                    onSnooze = { option -> actions().snooze(alerts.map { it.id }, option) },
                ),
            )
        }
    }

    /** Volume keys act like the notification's Stop (spec §7): a single Dismiss of everything ringing. */
    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        if (event.keyCode in VOLUME_KEYS) {
            if (event.action == KeyEvent.ACTION_DOWN && event.repeatCount == 0) {
                actions().dismiss(alerts.map { it.id })
            }
            return true
        }
        return super.dispatchKeyEvent(event)
    }

    override fun onDestroy() {
        unsubscribe?.invoke()
        super.onDestroy()
    }

    private fun join(alertId: String) {
        joining = true
        val url = actions().join(alertId)?.event?.joinUrl
        val keyguard = getSystemService(KeyguardManager::class.java)
        when {
            url == null -> finishIfIdle()
            !keyguard.isKeyguardLocked -> {
                JoinActivity.openJoinUrl(this, url)
                finishIfIdle()
            }
            else -> keyguard.requestDismissKeyguard(
                this,
                object : KeyguardManager.KeyguardDismissCallback() {
                    override fun onDismissSucceeded() {
                        JoinActivity.openJoinUrl(this@AlarmActivity, url)
                        finishIfIdle()
                    }

                    override fun onDismissCancelled() = finishIfIdle()

                    override fun onDismissError() = finishIfIdle()
                },
            )
        }
    }

    private fun finishIfIdle() {
        joining = false
        if (alerts.isEmpty()) finish()
    }

    private fun actions() = EngineActions.create(this)

    private fun showOverLockScreen() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON)
        }
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
    }

    companion object {
        private val VOLUME_KEYS = setOf(KeyEvent.KEYCODE_VOLUME_UP, KeyEvent.KEYCODE_VOLUME_DOWN, KeyEvent.KEYCODE_VOLUME_MUTE)
    }
}
