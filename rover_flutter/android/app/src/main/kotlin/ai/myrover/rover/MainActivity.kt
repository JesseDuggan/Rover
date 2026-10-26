package ai.myrover.rover

import ai.myrover.rover.ai.RoverOnDeviceAiHostApiImpl
import ai.myrover.rover.ai.generated.RoverOnDeviceAiHostApi
import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.MediaPlayer
import android.net.Uri
import android.os.Bundle
import android.provider.Settings
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.Locale
import java.util.UUID
import java.io.File
import java.io.FileInputStream

class MainActivity : FlutterActivity(), TextToSpeech.OnInitListener {
    private var memoryThumbnails: MemoryThumbnails? = null
    private var roverAiForeground = false
    private var roverAiHostApi: RoverOnDeviceAiHostApiImpl? = null
    private var tts: TextToSpeech? = null
    private var ttsReady = false
    private var speechRate = 0.48f
    private var pendingTtsConfigure: MutableList<Pair<Float, MethodChannel.Result>> = mutableListOf()
    private val pendingTtsSpeak = PendingUtterance<MethodChannel.Result>()
    private var speechRecognizer: SpeechRecognizer? = null
    private var pendingSpeechResult: MethodChannel.Result? = null
    private var pendingPermissionResult: MethodChannel.Result? = null
    private var pendingNotificationResult: MethodChannel.Result? = null
    private var premiumPlayer: MediaPlayer? = null
    private val pendingPremiumResult = PendingUtterance<MethodChannel.Result>()
    private var premiumAudioFile: File? = null
    private val audioManager by lazy { getSystemService(AUDIO_SERVICE) as AudioManager }
    private val audioFocusListener = AudioManager.OnAudioFocusChangeListener { change ->
        if (change == AudioManager.AUDIOFOCUS_LOSS) {
            premiumPlayer?.pause()
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        memoryThumbnails = MemoryThumbnails(applicationContext, flutterEngine.dartExecutor.binaryMessenger)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "ai.myrover.rover/drive")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "active" -> result.success(DriveNarrationService.active)
                    "stop" -> {
                        stopService(Intent(this, DriveNarrationService::class.java))
                        result.success(null)
                    }
                    "start" -> {
                        if (!roverAiForeground ||
                            checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) != PackageManager.PERMISSION_GRANTED ||
                            (android.os.Build.VERSION.SDK_INT >= 33 &&
                            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED)) {
                            result.error("drive_permission", "While parked, allow precise location and notifications before starting stories.", null)
                        } else {
                            val handler = android.os.Handler(android.os.Looper.getMainLooper())
                            var settled = false
                            val timeout = Runnable {
                                if (!settled) {
                                    settled = true
                                    stopService(Intent(this, DriveNarrationService::class.java))
                                    result.error("drive_start", "Drive stories could not start. Try again while parked.", null)
                                }
                            }
                            val receiver = object : android.os.ResultReceiver(handler) {
                                override fun onReceiveResult(code: Int, data: Bundle?) {
                                    if (settled) return
                                    settled = true
                                    handler.removeCallbacks(timeout)
                                    if (code == 0) result.success(null)
                                    else result.error("drive_start", "Drive stories need GPS and downloaded audio. Try again while parked.", null)
                                }
                            }
                            try {
                                startForegroundService(Intent(this, DriveNarrationService::class.java)
                                    .putExtra("path", call.argument<String>("path")).putExtra("receiver", receiver))
                                handler.postDelayed(timeout, 10000)
                            } catch (_: Exception) {
                                settled = true
                                result.error("drive_start", "Drive stories could not start. Keep Walkabout open while preparing.", null)
                            }
                        }
                    }
                    else -> result.notImplemented()
                }
            }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "ai.myrover.rover/voice"
        ).setMethodCallHandler { call, result -> handleVoiceCall(call, result) }
        roverAiHostApi = RoverOnDeviceAiHostApiImpl(this) { roverAiForeground }
        RoverOnDeviceAiHostApi.setUp(
            flutterEngine.dartExecutor.binaryMessenger,
            roverAiHostApi,
        )
    }

    override fun onResume() {
        super.onResume()
        roverAiForeground = true
    }

    override fun onPause() {
        roverAiForeground = false
        super.onPause()
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        memoryThumbnails?.dispose()
        memoryThumbnails = null
        RoverOnDeviceAiHostApi.setUp(flutterEngine.dartExecutor.binaryMessenger, null)
        roverAiHostApi = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    private fun handleVoiceCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "walkingNotificationPermission" -> {
                if (android.os.Build.VERSION.SDK_INT >= 33 &&
                    checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
                    pendingNotificationResult?.success(null)
                    pendingNotificationResult = result
                    requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 7402)
                } else result.success(null)
            }
            "audioConfigure" -> configureAudio(result)
            "ttsConfigure" -> configureTts(call, result)
            "ttsSpeak" -> speak(call, result)
            "ttsPause" -> stopTts(result)
            "ttsStop" -> stopTts(result)
            "premiumAudioPlayBytes" -> playPremiumAudioBytes(call, result)
            "premiumAudioPause" -> pausePremiumAudio(result)
            "premiumAudioResume" -> resumePremiumAudio(result)
            "premiumAudioStop" -> stopPremiumAudio(result)
            "speechInitialize" -> result.success(SpeechRecognizer.isRecognitionAvailable(this))
            "speechRequestPermission" -> requestSpeechPermission(result)
            "speechListen" -> listenForSpeech(result)
            "speechStop" -> stopSpeech(result)
            "openSettings" -> openSettings(result)
            else -> result.notImplemented()
        }
    }

    private fun configureAudio(result: MethodChannel.Result) {
        val outputs = audioManager.getDevices(AudioManager.GET_DEVICES_OUTPUTS)
            .joinToString { device -> device.productName?.toString() ?: "Android audio output" }
        Log.i(TAG, "Narration audio outputs: $outputs")
        result.success(null)
    }

    private fun requestNarrationAudioFocus() {
        audioManager.requestAudioFocus(
            audioFocusListener,
            AudioManager.STREAM_MUSIC,
            AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK,
        )
    }

    private fun abandonNarrationAudioFocus() {
        audioManager.abandonAudioFocus(audioFocusListener)
    }

    private fun configureTts(call: MethodCall, result: MethodChannel.Result) {
        speechRate = (call.argument<Double>("rate") ?: 0.48).toFloat().coerceIn(0.3f, 0.65f)
        ensureTts()
        if (ttsReady) {
            tts?.setSpeechRate(speechRate)
            result.success(null)
            return
        }
        pendingTtsConfigure.add(Pair(speechRate, result))
    }

    private fun ensureTts() {
        if (tts == null) {
            tts = TextToSpeech(this, this)
        }
    }

    override fun onInit(status: Int) {
        ttsReady = status == TextToSpeech.SUCCESS
        if (ttsReady) {
            tts?.language = Locale.getDefault()
            tts?.setSpeechRate(speechRate)
            tts?.setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_ASSISTANCE_NAVIGATION_GUIDANCE)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                    .build()
            )
            tts?.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
                override fun onStart(utteranceId: String?) = Unit

                override fun onDone(utteranceId: String?) {
                    completePendingSpeak(utteranceId, null)
                }

                @Deprecated("Deprecated in Java")
                override fun onError(utteranceId: String?) {
                    completePendingSpeak(utteranceId, "Text-to-speech failed.")
                }

                override fun onError(utteranceId: String?, errorCode: Int) {
                    completePendingSpeak(utteranceId, "Text-to-speech failed.")
                }

                override fun onStop(utteranceId: String?, interrupted: Boolean) {
                    completePendingSpeak(utteranceId, "Text-to-speech was interrupted.")
                }
            })
        }

        val pending = pendingTtsConfigure.toList()
        pendingTtsConfigure.clear()
        runOnUiThread {
            pending.forEach { pair ->
                if (ttsReady) {
                    tts?.setSpeechRate(pair.first)
                    pair.second.success(null)
                } else {
                    pair.second.error("tts_unavailable", "Text-to-speech is unavailable on this device.", null)
                }
            }
        }
    }

    private fun speak(call: MethodCall, result: MethodChannel.Result) {
        val text = call.argument<String>("text").orEmpty().trim()
        if (text.isEmpty()) {
            result.success(null)
            return
        }
        ensureTts()
        if (!ttsReady) {
            result.error("tts_unavailable", "Text-to-speech is not ready yet.", null)
            return
        }
        val utteranceId = UUID.randomUUID().toString()
        pendingTtsSpeak.replace(utteranceId, result)?.success(null)
        requestNarrationAudioFocus()
        if (tts?.speak(text, TextToSpeech.QUEUE_FLUSH, Bundle.EMPTY, utteranceId) != TextToSpeech.SUCCESS) {
            completePendingSpeak(utteranceId, "Text-to-speech could not start.")
        }
    }

    private fun completePendingSpeak(utteranceId: String?, message: String?) {
        runOnUiThread {
            val result = pendingTtsSpeak.take(utteranceId) ?: return@runOnUiThread
            abandonNarrationAudioFocus()
            if (message == null) {
                result.success(null)
            } else {
                result.error("tts_error", message, null)
            }
        }
    }

    private fun stopTts(result: MethodChannel.Result) {
        val pending = pendingTtsSpeak.clear()
        tts?.stop()
        pending?.success(null)
        abandonNarrationAudioFocus()
        result.success(null)
    }

    private fun playPremiumAudioBytes(call: MethodCall, result: MethodChannel.Result) {
        val bytes = call.argument<ByteArray>("bytes")
        if (bytes == null || bytes.isEmpty()) {
            result.error("premium_audio_empty", "Premium audio was empty.", null)
            return
        }

        stopPremiumAudioInternal(completePending = true)
        val playbackId = UUID.randomUUID().toString()
        pendingPremiumResult.replace(playbackId, result)
        try {
            requestNarrationAudioFocus()
            val file = File.createTempFile("rover-premium-", ".mp3", cacheDir)
            file.writeBytes(bytes)
            premiumAudioFile = file
            val player = MediaPlayer()
            premiumPlayer = player
            player.apply {
                setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_ASSISTANCE_NAVIGATION_GUIDANCE)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                        .build()
                )
                FileInputStream(file).use { input -> setDataSource(input.fd) }
                setOnCompletionListener {
                    completePremiumAudio(playbackId, null)
                }
                setOnErrorListener { _, what, extra ->
                    completePremiumAudio(playbackId, "Premium audio playback failed on Android MediaPlayer. what=$what extra=$extra")
                    true
                }
                prepare()
                start()
            }
        } catch (error: Exception) {
            completePremiumAudio(playbackId, "Premium audio playback failed: ${error.javaClass.simpleName}.")
        }
    }

    private fun pausePremiumAudio(result: MethodChannel.Result) {
        premiumPlayer?.pause()
        result.success(null)
    }

    private fun resumePremiumAudio(result: MethodChannel.Result) {
        premiumPlayer?.start()
        result.success(null)
    }

    private fun stopPremiumAudio(result: MethodChannel.Result) {
        stopPremiumAudioInternal(completePending = true)
        result.success(null)
    }

    private fun completePremiumAudio(playbackId: String, message: String?) {
        runOnUiThread {
            val result = pendingPremiumResult.take(playbackId) ?: return@runOnUiThread
            stopPremiumAudioInternal(completePending = false)
            if (message == null) {
                result.success(null)
            } else {
                result.error("premium_audio_error", message, null)
            }
        }
    }

    private fun stopPremiumAudioInternal(completePending: Boolean = true) {
        val pending = pendingPremiumResult.clear()
        premiumPlayer?.release()
        premiumPlayer = null
        if (completePending) {
            pending?.success(null)
        }
        premiumAudioFile?.delete()
        premiumAudioFile = null
        abandonNarrationAudioFocus()
    }

    private fun requestSpeechPermission(result: MethodChannel.Result) {
        if (!SpeechRecognizer.isRecognitionAvailable(this)) {
            result.success("unavailable")
            return
        }
        if (checkSelfPermission(Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED) {
            result.success("granted")
            return
        }
        pendingPermissionResult = result
        requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO), MICROPHONE_PERMISSION_REQUEST)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 7402) {
            // Denying notifications does not prevent a user-started location service.
            pendingNotificationResult?.success(null)
            pendingNotificationResult = null
            return
        }
        if (requestCode != MICROPHONE_PERMISSION_REQUEST) {
            return
        }

        val granted = grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED
        val blocked = !granted && !shouldShowRequestPermissionRationale(Manifest.permission.RECORD_AUDIO)
        pendingPermissionResult?.success(
            when {
                granted -> "granted"
                blocked -> "permanentlyDenied"
                else -> "denied"
            }
        )
        pendingPermissionResult = null
    }

    private fun listenForSpeech(result: MethodChannel.Result) {
        if (checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
            result.error("microphone_denied", "Microphone permission is needed for Ask Rover.", null)
            return
        }
        if (!SpeechRecognizer.isRecognitionAvailable(this)) {
            result.error("speech_unavailable", "Speech recognition is unavailable on this device.", null)
            return
        }

        pendingSpeechResult?.success("")
        pendingSpeechResult = result
        speechRecognizer?.destroy()
        speechRecognizer = SpeechRecognizer.createSpeechRecognizer(this)
        speechRecognizer?.setRecognitionListener(object : RecognitionListener {
            override fun onReadyForSpeech(params: Bundle?) = Unit
            override fun onBeginningOfSpeech() = Unit
            override fun onRmsChanged(rmsdB: Float) = Unit
            override fun onBufferReceived(buffer: ByteArray?) = Unit
            override fun onEndOfSpeech() = Unit
            override fun onPartialResults(partialResults: Bundle?) = Unit
            override fun onEvent(eventType: Int, params: Bundle?) = Unit

            override fun onError(error: Int) {
                val message = speechErrorMessage(error)
                Log.w(TAG, "Speech recognition failed: code=$error message=$message")
                completePendingSpeech(message, isError = true)
            }

            override fun onResults(results: Bundle?) {
                val matches = results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                completePendingSpeech(matches?.firstOrNull().orEmpty(), isError = false)
            }
        })

        val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
            putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, false)
            putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1)
            putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_COMPLETE_SILENCE_LENGTH_MILLIS, 1500L)
            putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_MINIMUM_LENGTH_MILLIS, 1000L)
        }
        speechRecognizer?.startListening(intent)
    }

    private fun completePendingSpeech(value: String, isError: Boolean) {
        runOnUiThread {
            val result = pendingSpeechResult
            pendingSpeechResult = null
            speechRecognizer?.stopListening()
            if (isError) {
                result?.error("speech_error", value, mapOf("message" to value))
            } else {
                result?.success(value)
            }
        }
    }

    private fun stopSpeech(result: MethodChannel.Result) {
        speechRecognizer?.stopListening()
        pendingSpeechResult?.success("")
        pendingSpeechResult = null
        result.success(null)
    }

    private fun openSettings(result: MethodChannel.Result) {
        val intent = Intent(
            Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
            Uri.fromParts("package", packageName, null)
        )
        startActivity(intent)
        result.success(true)
    }

    override fun onDestroy() {
        speechRecognizer?.destroy()
        stopPremiumAudioInternal(completePending = true)
        tts?.shutdown()
        super.onDestroy()
    }

    companion object {
        private const val TAG = "RoverVoice"
        private const val MICROPHONE_PERMISSION_REQUEST = 7401

        private fun speechErrorMessage(error: Int): String {
            return when (error) {
                SpeechRecognizer.ERROR_AUDIO -> "Speech recognition had an audio input problem. Check microphone access and try again."
                SpeechRecognizer.ERROR_CLIENT -> "Speech recognition could not start on this device. Check Samsung or Google speech services, then try again."
                SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS -> "Microphone permission is needed for Ask Rover."
                SpeechRecognizer.ERROR_NETWORK -> "Speech recognition could not reach the network."
                SpeechRecognizer.ERROR_NETWORK_TIMEOUT -> "Speech recognition network timed out."
                SpeechRecognizer.ERROR_NO_MATCH -> "I did not catch that. Try asking again or type the question below."
                SpeechRecognizer.ERROR_RECOGNIZER_BUSY -> "Speech recognition is busy. Wait a moment and try again."
                SpeechRecognizer.ERROR_SERVER -> "The speech recognition service had a server problem."
                SpeechRecognizer.ERROR_SERVER_DISCONNECTED -> "Speech recognition service disconnected. Try again or type the question below."
                SpeechRecognizer.ERROR_SPEECH_TIMEOUT -> "I did not hear a question. Try again or type the question below."
                else -> "Speech recognition failed with Android error code $error."
            }
        }
    }
}
