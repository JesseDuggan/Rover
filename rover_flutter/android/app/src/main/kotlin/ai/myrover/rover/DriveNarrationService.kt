package ai.myrover.rover

import android.app.*
import android.content.Intent
import android.content.Context
import android.content.pm.ServiceInfo
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.media.MediaPlayer
import android.os.*
import org.json.JSONObject
import java.io.File

class DriveNarrationService : Service(), LocationListener {
    companion object {
        private const val CHANNEL = "scenic_drive_stories"
        private const val NOTIFICATION = 7420
        var active = false
            private set
    }
    private val handler = Handler(Looper.getMainLooper())
    private lateinit var locations: LocationManager
    private lateinit var audio: AudioManager
    private var approach: DriveApproach? = null
    private var sessionId: String? = null
    private var sessionDirectory: File? = null
    private var player: MediaPlayer? = null
    private var playingIndex: Int? = null
    private var focus: AudioFocusRequest? = null
    private var blocked = false
    private var prepared = false
    private var lastFix: DriveFix? = null
    private var lastFixAt = 0L
    private var pauseAt = 0L
    private var deadline = 0L
    private val attributes = AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_MEDIA)
        .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH).build()

    override fun onCreate() {
        super.onCreate()
        locations = getSystemService(Context.LOCATION_SERVICE) as LocationManager
        audio = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        (getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager).createNotificationChannel(
            NotificationChannel(CHANNEL, "Scenic Drive stories", NotificationManager.IMPORTANCE_LOW))
    }

    private fun notification(text: String): Notification {
        val open = PendingIntent.getActivity(this, 0, Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val stop = PendingIntent.getService(this, 1, Intent(this, DriveNarrationService::class.java).setAction("stop"),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        return Notification.Builder(this, CHANNEL).setSmallIcon(android.R.drawable.ic_media_play)
            .setContentTitle("Walkabout drive stories").setContentText(text)
            .setContentIntent(open).setOngoing(true).setOnlyAlertOnce(true)
            .addAction(Notification.Action.Builder(null, "Stop stories", stop).build()).build()
    }

    private fun status(text: String) {
        (getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager).notify(NOTIFICATION, notification(text))
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == "stop" || intent == null) { stopSelf(); return START_NOT_STICKY }
        @Suppress("DEPRECATION")
        val receiver = intent.getParcelableExtra<ResultReceiver>("receiver")
        try {
            val root = File(applicationInfo.dataDir).canonicalFile
            val file = File(requireNotNull(intent.getStringExtra("path"))).canonicalFile
            require(file.path.startsWith(root.path + File.separator) && file.name == "session.json")
            require(file.parentFile?.name == "drive_narration")
            sessionDirectory = file.parentFile
            val json = JSONObject(file.readText())
            if (active && sessionId == json.getString("id")) {
                receiver?.send(0, Bundle()); return START_NOT_STICKY
            }
            clearPlayback()
            locations.removeUpdates(this)
            val routeJson = json.getJSONArray("route")
            val route = (0 until routeJson.length()).map {
                DrivePoint(routeJson.getJSONArray(it).getDouble(0), routeJson.getJSONArray(it).getDouble(1))
            }
            require(route.size >= 2)
            val stopJson = json.getJSONArray("stops")
            val stops = (0 until stopJson.length()).map {
                val s = stopJson.getJSONObject(it)
                val path = if (s.isNull("audio")) null else File(s.getString("audio")).canonicalFile.also { audioFile ->
                    require(audioFile.parentFile == file.parentFile && audioFile.isFile)
                }.path
                DriveStop(s.getString("id"), s.getString("name"),
                    DrivePoint(s.getDouble("latitude"), s.getDouble("longitude")), path,
                    if (s.isNull("expires")) null else s.getLong("expires"))
            }
            require(stops.isNotEmpty() && stops.size <= 7)
            require(locations.isProviderEnabled(LocationManager.GPS_PROVIDER))
            approach = DriveApproach(route, stops)
            sessionId = json.getString("id")
            val notice = notification("Automatic introductions are on. Location stays active during this drive.")
            if (Build.VERSION.SDK_INT >= 29) startForeground(NOTIFICATION, notice,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION or ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK)
            else startForeground(NOTIFICATION, notice)
            locations.requestLocationUpdates(LocationManager.GPS_PROVIDER, 5000L, 0f, this, Looper.getMainLooper())
            deadline = SystemClock.elapsedRealtime() + json.getInt("minutes").coerceIn(15, 780) * 60000L
            active = true
            handler.removeCallbacks(tick)
            handler.postDelayed(tick, 5000)
            receiver?.send(0, Bundle())
        } catch (_: Exception) {
            receiver?.send(1, Bundle())
            stopSelf()
        }
        return START_NOT_STICKY
    }

    override fun onLocationChanged(location: Location) {
        val age = (SystemClock.elapsedRealtimeNanos() - location.elapsedRealtimeNanos) / 1000000
        val fix = DriveFix(DrivePoint(location.latitude, location.longitude),
            if (location.hasSpeed()) location.speed.toDouble() else 0.0,
            if (location.hasAccuracy()) location.accuracy.toDouble() else 999.0, age)
        lastFix = fix
        lastFixAt = SystemClock.elapsedRealtime()
        val engine = approach ?: return
        val candidate = engine.candidate(fix, System.currentTimeMillis())
        if (engine.arrived && player == null) { stopSelf(); return }
        if (candidate == null || player != null || audio.mode != AudioManager.MODE_NORMAL || audio.isMusicActive) return
        play(candidate)
    }

    private fun play(index: Int) {
        val stop = approach?.stops?.get(index) ?: return
        val path = stop.audio ?: return
        if (stop.expires?.let { it <= System.currentTimeMillis() } == true) return
        playingIndex = index
        prepared = false
        blocked = false
        focus = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK)
            .setAudioAttributes(attributes).setWillPauseWhenDucked(true)
            .setAcceptsDelayedFocusGain(true)
            .setOnAudioFocusChangeListener({ change ->
                when (change) {
                    AudioManager.AUDIOFOCUS_GAIN -> {
                        blocked = false
                        if (prepared && canResume()) runCatching {
                            playingIndex?.let { approach?.played(it, System.currentTimeMillis()) }
                            player?.start()
                        }
                        else if (prepared) clearPlayback()
                    }
                    AudioManager.AUDIOFOCUS_LOSS_TRANSIENT, AudioManager.AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK -> {
                        blocked = true
                        pauseAt = SystemClock.elapsedRealtime()
                        runCatching { if (player?.isPlaying == true) player?.pause() }
                    }
                    AudioManager.AUDIOFOCUS_LOSS -> clearPlayback()
                }
            }, handler).build()
        val granted = audio.requestAudioFocus(focus!!)
        if (granted == AudioManager.AUDIOFOCUS_REQUEST_FAILED) { clearPlayback(); return }
        blocked = granted != AudioManager.AUDIOFOCUS_REQUEST_GRANTED
        pauseAt = SystemClock.elapsedRealtime()
        try {
            player = MediaPlayer().apply {
                setAudioAttributes(attributes)
                setWakeMode(applicationContext, PowerManager.PARTIAL_WAKE_LOCK)
                setDataSource(path)
                setOnPreparedListener {
                    prepared = true
                    if (!blocked && canResume()) {
                        approach?.played(index, System.currentTimeMillis())
                        status("Playing: ${stop.name}")
                        start()
                    }
                }
                setOnCompletionListener {
                    clearPlayback()
                    status("Waiting for the next stop")
                    if (approach?.arrived == true) stopSelf()
                }
                setOnErrorListener { _, _, _ ->
                    approach?.played(index, System.currentTimeMillis())
                    clearPlayback()
                    status("A story could not play. Waiting for the next stop.")
                    true
                }
                prepareAsync()
            }
        } catch (_: Exception) {
            approach?.played(index, System.currentTimeMillis())
            clearPlayback()
        }
    }

    private fun canResume(): Boolean {
        val fix = lastFix ?: return false
        val stop = playingIndex?.let { approach?.stops?.get(it) } ?: return false
        val fresh = SystemClock.elapsedRealtime() - lastFixAt < 30000
        val close = driveDistance(fix.point, stop.point) < 3500
        val recentPause = SystemClock.elapsedRealtime() - pauseAt < 120000
        return fresh && close && recentPause && audio.mode == AudioManager.MODE_NORMAL
    }

    private fun clearPlayback() {
        player?.release()
        player = null
        playingIndex = null
        prepared = false
        blocked = false
        focus?.let { audio.abandonAudioFocusRequest(it) }
        focus = null
    }

    private val tick = object : Runnable {
        override fun run() {
            if (SystemClock.elapsedRealtime() > deadline) { stopSelf(); return }
            if (SystemClock.elapsedRealtime() - lastFixAt > 30000 && player != null) clearPlayback()
            handler.postDelayed(this, 5000)
        }
    }
    override fun onProviderDisabled(provider: String) {
        clearPlayback()
        status("Location unavailable. Stories are waiting for GPS.")
    }
    override fun onProviderEnabled(provider: String) = Unit
    @Deprecated("Deprecated in Java")
    override fun onStatusChanged(provider: String?, status: Int, extras: Bundle?) = Unit
    override fun onTaskRemoved(rootIntent: Intent?) { stopSelf() }
    override fun onDestroy() {
        active = false
        handler.removeCallbacksAndMessages(null)
        locations.removeUpdates(this)
        clearPlayback()
        sessionDirectory?.listFiles()?.filter { it.isFile && (it.extension == "audio" || it.name == "session.json") }
            ?.forEach { it.delete() }
        stopForeground(STOP_FOREGROUND_REMOVE)
        super.onDestroy()
    }
    override fun onBind(intent: Intent?) = null
}

