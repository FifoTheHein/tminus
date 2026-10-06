package io.github.fifothehein.tminus.engine

import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.media.AudioAttributes
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
 * as a mediaPlayback foreground service (spec §7 Firing). Stops when the session empties, or after
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
    private var volume = 1f

    private val timeout = Runnable {
        EngineActions.create(this).missed(RingingSession.alerts.map { it.id })
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
        unsubscribe = RingingSession.observe(::onSessionChanged)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val ids = intent?.getStringArrayListExtra(EXTRA_ALERT_IDS).orEmpty().toSet()
        val alerts = PlanStore(this).read().presented.filter { it.id in ids }
        val session = (RingingSession.alerts + alerts).distinctBy { it.id }
        if (!inForeground) {
            // Must happen within seconds of startForegroundService, even if there is nothing to ring.
            notifications.ensureChannels()
            ServiceCompat.startForeground(this, NotificationFactory.RINGING_NOTIFICATION_ID, notifications.ringing(session), foregroundType())
            inForeground = true
        }
        if (session.isEmpty()) {
            stopRinging()
            return START_NOT_STICKY
        }
        RingingSession.add(alerts)
        val lead = session.firstOrNull { it.strength == Strength.ALARM } ?: session.first()
        if (!alerting) startAlerting(lead.sound)
        handler.removeCallbacks(timeout)
        handler.postDelayed(timeout, lead.sound.ringTimeoutSec * 1_000L)
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        unsubscribe?.invoke()
        stopAlerting()
        super.onDestroy()
    }

    private fun onSessionChanged(alerts: List<PlannedAlert>) {
        if (alerts.isEmpty()) stopRinging() else notifications.notifyRinging(alerts)
    }

    private fun stopRinging() {
        stopAlerting()
        ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_REMOVE)
        inForeground = false
        stopSelf()
    }

    private fun startAlerting(sound: Sound) {
        alerting = true
        acquireWakeLock(sound)
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
            mp.setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_ALARM)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build(),
            )
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

    private fun acquireWakeLock(sound: Sound) {
        wakeLock = getSystemService(PowerManager::class.java)
            .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "tminus:ringing")
            .apply {
                setReferenceCounted(false)
                acquire((sound.ringTimeoutSec + 30) * 1_000L)
            }
    }

    private fun foregroundType(): Int =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK else 0

    companion object {
        const val EXTRA_ALERT_IDS = "alertIds"
        private const val TAG = "TMinusEngine"
        private const val RAMP_START = 0.1f
        private const val RAMP_STEP = 0.03f // 0.1 → 1.0 in 30 steps of 1 s
        private const val RAMP_INTERVAL_MS = 1_000L
        private val VIBRATION_PATTERN = longArrayOf(0, 800, 600)

        fun start(context: Context, alertIds: List<String>) {
            val intent = Intent(context, RingingService::class.java)
                .putStringArrayListExtra(EXTRA_ALERT_IDS, ArrayList(alertIds))
            ContextCompat.startForegroundService(context, intent)
        }
    }
}
