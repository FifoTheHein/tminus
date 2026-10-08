package io.github.fifothehein.tminus.engine

import android.app.Notification
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.os.VibrationAttributes
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.provider.Settings
import android.util.Log
import androidx.core.app.ServiceCompat
import androidx.core.content.ContextCompat

/**
 * Rings RingingSession: alarm-stream audio with a volume ramp, vibration and a partial wake lock,
 * as a mediaPlayback foreground service (spec §7 Firing). It holds transient audio focus while it
 * rings, so other audio pauses and resumes afterwards. Stops when the session empties, or after
 * the lead alert's ring timeout, which logs `missed` and posts a Missed notification.
 */
class RingingService : Service() {
    private val handler = Handler(Looper.getMainLooper())
    private lateinit var notifications: NotificationFactory
    private var unsubscribe: (() -> Unit)? = null
    private var inForeground = false
    private var alerting = false
    private var player: MediaPlayer? = null
    private var vibrator: Vibrator? = null
    private var wakeLock: PowerManager.WakeLock? = null
    private var audioFocus: AudioFocusRequest? = null
    /** Every id this instance has rung (the session at each start it handled); onDestroy removes only these. */
    private val accepted = mutableSetOf<String>()
    /** The session's ids at the last change this service saw, to tell which alerts just joined. */
    private var sessionIds: Set<String> = emptySet()
    /** The newest start id handled; stopping with it fails if a newer start is still queued. */
    private var lastStartId = 0
    private var volume = 1f

    /** The backstop: silences the whole session first, then reports what the state still lists as missed. */
    private val timeout = Runnable {
        val ringing = RingingSession.alerts
        RingingSession.clear() // stops ringing synchronously, through onSessionChanged
        EngineActions.create(this).missed(ringing.map { it.id })
    }

    private val ramp = object : Runnable {
        override fun run() {
            volume = (volume + RAMP_STEP).coerceAtMost(1f)
            player?.setVolume(volume, volume)
            if (volume < 1f) handler.postDelayed(this, RAMP_INTERVAL_MS)
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        notifications = NotificationFactory(this)
        sessionIds = RingingSession.ids
        unsubscribe = RingingSession.observe(::onSessionChanged)
        CrashSilencer.install()
        CrashSilencer.register(::stopAlerting)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        lastStartId = startId
        val retry = intent?.getBooleanExtra(EXTRA_RETRY, false) == true
        val ids = intent?.getStringArrayListExtra(EXTRA_ALERT_IDS).orEmpty().toSet()
        val alerts = PlanStore(this).read().presented.filter { it.id in ids }
        val session = (RingingSession.alerts + alerts).distinctBy { it.id }
        if (!inForeground) {
            // Must happen within seconds of startForegroundService, even if there is nothing to ring.
            notifications.ensureChannels()
            try {
                startForeground(this, NotificationFactory.RINGING_NOTIFICATION_ID, notifications.ringing(session), foregroundType())
            } catch (e: IllegalStateException) { // ForegroundServiceStartNotAllowedException is one
                refuseForeground(session, retry, e)
                return START_NOT_STICKY
            } catch (e: SecurityException) {
                refuseForeground(session, retry, e)
                return START_NOT_STICKY
            }
            inForeground = true
        }
        if (session.isEmpty()) {
            stopRinging()
            return START_NOT_STICKY
        }
        RingingSession.add(alerts)
        accepted += session.map { it.id }
        val lead = session.firstOrNull { it.strength == Strength.ALARM } ?: session.first()
        // The ring timeout and the wake lock restart from the newest alert (the ones this start added).
        val newest = alerts.firstOrNull { it.strength == Strength.ALARM } ?: alerts.firstOrNull() ?: lead
        if (!alerting) startAlerting(lead.sound)
        restartTimeout(newest)
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        CrashSilencer.register(null)
        unsubscribe?.invoke()
        // Nothing this instance rang rings once it is gone: the alarm screen drops them. An alert a newer
        // start is about to ring (the presenter adds it first) stays for the next instance.
        RingingSession.remove(accepted)
        stopAlerting()
        super.onDestroy()
    }

    /**
     * Android refused the foreground start (on Android 15+, for example, inside a boot broadcast's
     * allow-list). Nothing may ring: the session's alerts show as heads-up notifications instead, with
     * their normal actions, and stay presented. They ring again through AlarmManager after
     * RECOVERY_DELAY_MS, once: a refused [retry] is not retried again.
     */
    private fun refuseForeground(session: List<PlannedAlert>, retry: Boolean, error: Exception) {
        Log.w(TAG, "Ringing service refused the foreground; showing a heads-up instead (retry: $retry)", error)
        stopAlerting()
        AndroidAlertPresenter(this).fallBackToHeadsUp(session)
        if (!retry && session.isNotEmpty()) {
            AlarmScheduler(this).armRingingRetry(session.map { it.id }, System.currentTimeMillis() + EngineActions.RECOVERY_DELAY_MS)
        }
        stopSelfResult(lastStartId)
    }

    private fun onSessionChanged(alerts: List<PlannedAlert>) {
        val joined = alerts.filter { it.id !in sessionIds }
        sessionIds = alerts.map { it.id }.toSet()
        if (alerts.isEmpty()) {
            stopRinging()
            return
        }
        notifications.notifyRinging(alerts)
        // Any alert that joins a ringing session restarts the ring timeout, as soon as it joins: the
        // presenter adds a newly fired group before its start command arrives, and the timeout must not
        // report that group missed in the gap.
        if (alerting && joined.isNotEmpty()) restartTimeout(joined.firstOrNull { it.strength == Strength.ALARM } ?: joined.first())
    }

    /** The ring timeout and the wake lock restart from [newest]'s ringTimeoutSec. */
    private fun restartTimeout(newest: PlannedAlert) {
        holdWakeLock(newest.sound)
        handler.removeCallbacks(timeout)
        handler.postDelayed(timeout, newest.sound.ringTimeoutSec * 1_000L)
    }

    private fun stopRinging() {
        stopAlerting()
        ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_REMOVE)
        inForeground = false
        // Not stopSelf(): a newly fired alarm's startForegroundService may be queued behind this.
        stopSelfResult(lastStartId)
    }

    /** True while a tone is playing. */
    internal val isSounding: Boolean get() = player != null

    private fun startAlerting(sound: Sound) {
        alerting = true
        holdWakeLock(sound)
        requestAudioFocus()
        startSound(sound)
        if (sound.vibrate) startVibration()
    }

    private fun stopAlerting() {
        alerting = false
        handler.removeCallbacksAndMessages(null)
        player?.let { mp ->
            try {
                mp.stop()
            } catch (e: IllegalStateException) {
                // Not started yet; release below is enough.
            }
            mp.release()
        }
        player = null
        vibrator?.cancel()
        vibrator = null
        wakeLock?.takeIf { it.isHeld }?.release()
        wakeLock = null
        audioFocus?.let { getSystemService(AudioManager::class.java).abandonAudioFocusRequest(it) }
        audioFocus = null
    }

    /** Pauses other audio while the alarm rings. If focus is denied the alarm still rings. */
    private fun requestAudioFocus() {
        val request = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT)
            .setAudioAttributes(ALARM_ATTRIBUTES)
            .build()
        val granted = getSystemService(AudioManager::class.java).requestAudioFocus(request)
        if (granted != AudioManager.AUDIOFOCUS_REQUEST_GRANTED) Log.w(TAG, "Audio focus denied ($granted); ringing anyway")
        audioFocus = request
    }

    private fun startSound(sound: Sound) {
        val candidates = listOfNotNull(
            sound.toneUri?.let(Uri::parse),
            RingtoneManager.getActualDefaultRingtoneUri(this, RingtoneManager.TYPE_ALARM),
            Settings.System.DEFAULT_ALARM_ALERT_URI,
            RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE),
        ).distinct()
        play(candidates, sound.gradualVolume)
    }

    private fun play(candidates: List<Uri>, gradual: Boolean) {
        val opened = ToneFallback.firstPlayable(candidates, ::openPlayer)
        if (opened == null) {
            Log.w(TAG, "No playable alarm tone; vibrating only")
            return
        }
        val (index, mp) = opened
        if (index > 0) Log.w(TAG, "Tone ${candidates[0]} failed; using ${candidates[index]}")
        volume = if (gradual) RAMP_START else 1f
        mp.setVolume(volume, volume)
        mp.setOnErrorListener { failed, _, _ ->
            failed.release()
            if (player === failed) player = null
            play(candidates.drop(index + 1), gradual) // the tone broke while playing: fall back
            true
        }
        mp.start()
        player = mp
        if (gradual) {
            handler.removeCallbacks(ramp)
            handler.postDelayed(ramp, RAMP_INTERVAL_MS)
        }
    }

    private fun openPlayer(uri: Uri): MediaPlayer {
        val mp = MediaPlayer()
        try {
            mp.setAudioAttributes(ALARM_ATTRIBUTES)
            mp.setDataSource(this, uri)
            mp.isLooping = true
            mp.prepare()
            return mp
        } catch (e: Exception) {
            mp.release()
            throw e
        }
    }

    private fun startVibration() {
        @Suppress("DEPRECATION")
        val v: Vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            getSystemService(VibratorManager::class.java).defaultVibrator
        } else {
            getSystemService(Vibrator::class.java)
        }
        if (!v.hasVibrator()) return
        val effect = VibrationEffect.createWaveform(VIBRATION_PATTERN, 0)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            v.vibrate(effect, VibrationAttributes.createForUsage(VibrationAttributes.USAGE_ALARM))
        } else {
            @Suppress("DEPRECATION")
            v.vibrate(effect, AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_ALARM).build())
        }
        vibrator = v
    }

    /** Acquires the wake lock, or extends it, until 30 s after [sound]'s ring timeout. */
    private fun holdWakeLock(sound: Sound) {
        val lock = wakeLock ?: getSystemService(PowerManager::class.java)
            .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "tminus:ringing")
            .apply { setReferenceCounted(false) }
        lock.acquire((sound.ringTimeoutSec + 30) * 1_000L) // not reference counted: restarts the timeout
        wakeLock = lock
    }

    private fun foregroundType(): Int =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK else 0

    companion object {
        const val EXTRA_ALERT_IDS = "alertIds"
        /** Set on the start that retries a refused one; a refused retry is not retried again. */
        const val EXTRA_RETRY = "retry"
        private const val TAG = "TMinusEngine"
        private const val RAMP_START = 0.1f
        private const val RAMP_STEP = 0.03f // 0.1 → 1.0 in 30 steps of 1 s
        private const val RAMP_INTERVAL_MS = 1_000L
        private val VIBRATION_PATTERN = longArrayOf(0, 800, 600)
        private val ALARM_ATTRIBUTES: AudioAttributes = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_ALARM)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .build()

        internal val DEFAULT_START_FOREGROUND: (Service, Int, Notification, Int) -> Unit = ServiceCompat::startForeground

        /** ServiceCompat.startForeground; tests make it throw as Android may. */
        internal var startForeground: (Service, Int, Notification, Int) -> Unit = DEFAULT_START_FOREGROUND

        fun start(context: Context, alertIds: List<String>, retry: Boolean = false) {
            val intent = Intent(context, RingingService::class.java)
                .putStringArrayListExtra(EXTRA_ALERT_IDS, ArrayList(alertIds))
                .putExtra(EXTRA_RETRY, retry)
            ContextCompat.startForegroundService(context, intent)
        }
    }
}
