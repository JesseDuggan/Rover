package ai.myrover.rover.ai

import ai.myrover.rover.ai.generated.NativeRoverAiAvailability
import ai.myrover.rover.ai.generated.NativeRoverAiCapabilitySnapshot
import ai.myrover.rover.ai.generated.NativeRoverAiFeatureCapability
import ai.myrover.rover.ai.generated.NativeRoverAiThermalState
import android.app.ActivityManager
import android.content.Context
import android.os.Build
import android.os.PowerManager
import android.speech.SpeechRecognizer
import com.google.common.util.concurrent.ListenableFuture
import com.google.mlkit.genai.common.FeatureStatus
import com.google.mlkit.genai.imagedescription.ImageDescriberOptions
import com.google.mlkit.genai.imagedescription.ImageDescription
import com.google.mlkit.genai.prompt.Generation
import kotlinx.coroutines.suspendCancellableCoroutine
import java.util.concurrent.ExecutionException
import java.util.concurrent.Executor
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

internal object FeatureStatusMapper {
    fun map(status: Int): NativeRoverAiAvailability = when (status) {
        FeatureStatus.AVAILABLE -> NativeRoverAiAvailability.AVAILABLE
        FeatureStatus.DOWNLOADABLE -> NativeRoverAiAvailability.DOWNLOADABLE
        FeatureStatus.DOWNLOADING -> NativeRoverAiAvailability.DOWNLOADING
        FeatureStatus.UNAVAILABLE -> NativeRoverAiAvailability.UNAVAILABLE
        else -> NativeRoverAiAvailability.UNKNOWN
    }
}

internal class DeviceCapabilityService(
    private val context: Context,
    private val isForegroundEligible: () -> Boolean,
) {
    suspend fun snapshot(): NativeRoverAiCapabilitySnapshot {
        val prompt = detectPromptCapability()
        val imageDescription = detectImageDescriptionCapability()
        val unavailabilityReason = if (
            prompt.availability == NativeRoverAiAvailability.UNAVAILABLE &&
            imageDescription.availability == NativeRoverAiAvailability.UNAVAILABLE
        ) {
            "Gemini Nano features are unavailable on this device or are not ready in AICore."
        } else {
            null
        }

        return NativeRoverAiCapabilitySnapshot(
            apiLevel = Build.VERSION.SDK_INT.toLong(),
            manufacturer = Build.MANUFACTURER.orEmpty(),
            model = Build.MODEL.orEmpty(),
            prompt = prompt,
            imageDescription = imageDescription,
            ocr = availableCapability(
                provider = "ML Kit Text Recognition v2",
                modelName = "Bundled Latin OCR",
            ),
            objectDetection = unavailableCapability(
                "Object detection is not configured in Phase 13.2.",
            ),
            speechRecognition = detectLocalSpeechCapability(),
            localCuration = unavailableCapability(
                "No native curation model is configured. Deterministic Flutter curation is reported separately.",
            ),
            offlineIntelligence = unavailableCapability(
                "Offline Story Pack intelligence is reserved for a later Phase 13 package.",
            ),
            foregroundEligible = isForegroundEligible(),
            batterySaverEnabled = powerManager()?.isPowerSaveMode ?: false,
            thermalState = thermalState(),
            memoryPressure = memoryPressure(),
            quotaLimited = false,
            checkedAtEpochMilliseconds = System.currentTimeMillis(),
            unavailabilityReason = unavailabilityReason,
        )
    }

    private suspend fun detectPromptCapability(): NativeRoverAiFeatureCapability {
        val model = try {
            Generation.getClient()
        } catch (_: Throwable) {
            return unavailableCapability("ML Kit Prompt could not initialize.")
        }

        return try {
            featureCapability(
                status = model.checkStatus(),
                provider = "ML Kit Prompt API",
                modelName = "Gemini Nano",
            )
        } catch (_: Throwable) {
            unavailableCapability("ML Kit Prompt capability could not be queried.")
        } finally {
            model.close()
        }
    }

    private suspend fun detectImageDescriptionCapability(): NativeRoverAiFeatureCapability {
        val describer = try {
            val options = ImageDescriberOptions.builder(context).build()
            ImageDescription.getClient(options)
        } catch (_: Throwable) {
            return unavailableCapability("ML Kit Image Description could not initialize.")
        }

        return try {
            featureCapability(
                status = describer.checkFeatureStatus().awaitResult(),
                provider = "ML Kit Image Description API",
                modelName = "Gemini Nano",
            )
        } catch (_: Throwable) {
            unavailableCapability(
                "ML Kit Image Description capability could not be queried.",
            )
        } finally {
            describer.close()
        }
    }

    private fun detectLocalSpeechCapability(): NativeRoverAiFeatureCapability {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
            return unavailableCapability("On-device speech recognition requires Android 12 or newer.")
        }

        return if (SpeechRecognizer.isOnDeviceRecognitionAvailable(context)) {
            availableCapability(
                provider = "Android SpeechRecognizer",
                modelName = "On-device speech recognition",
            )
        } else {
            unavailableCapability("Android reports no on-device speech recognizer.")
        }
    }

    private fun thermalState(): NativeRoverAiThermalState {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            return NativeRoverAiThermalState.UNKNOWN
        }

        return when (powerManager()?.currentThermalStatus) {
            PowerManager.THERMAL_STATUS_NONE -> NativeRoverAiThermalState.NOMINAL
            PowerManager.THERMAL_STATUS_LIGHT -> NativeRoverAiThermalState.FAIR
            PowerManager.THERMAL_STATUS_MODERATE,
            PowerManager.THERMAL_STATUS_SEVERE -> NativeRoverAiThermalState.SERIOUS
            PowerManager.THERMAL_STATUS_CRITICAL,
            PowerManager.THERMAL_STATUS_EMERGENCY,
            PowerManager.THERMAL_STATUS_SHUTDOWN -> NativeRoverAiThermalState.CRITICAL
            else -> NativeRoverAiThermalState.UNKNOWN
        }
    }

    private fun memoryPressure(): Boolean {
        val manager = context.getSystemService(Context.ACTIVITY_SERVICE) as? ActivityManager
            ?: return false
        return ActivityManager.MemoryInfo().also(manager::getMemoryInfo).lowMemory
    }

    private fun powerManager(): PowerManager? =
        context.getSystemService(Context.POWER_SERVICE) as? PowerManager

    private fun featureCapability(
        status: Int,
        provider: String,
        modelName: String,
    ): NativeRoverAiFeatureCapability {
        val availability = FeatureStatusMapper.map(status)
        val reason = when (availability) {
            NativeRoverAiAvailability.DOWNLOADABLE ->
                "The on-device model is supported but has not been downloaded."
            NativeRoverAiAvailability.DOWNLOADING ->
                "The on-device model is currently downloading."
            NativeRoverAiAvailability.UNAVAILABLE ->
                "The on-device feature is unavailable from AICore."
            NativeRoverAiAvailability.UNKNOWN ->
                "The on-device feature returned an unknown status."
            NativeRoverAiAvailability.AVAILABLE -> null
        }
        return NativeRoverAiFeatureCapability(
            availability = availability,
            provider = provider,
            modelName = modelName,
            reason = reason,
        )
    }

    private fun availableCapability(
        provider: String,
        modelName: String,
    ) = NativeRoverAiFeatureCapability(
        availability = NativeRoverAiAvailability.AVAILABLE,
        provider = provider,
        modelName = modelName,
    )

    private fun unavailableCapability(reason: String) = NativeRoverAiFeatureCapability(
        availability = NativeRoverAiAvailability.UNAVAILABLE,
        reason = reason,
    )
}

private suspend fun <T> ListenableFuture<T>.awaitResult(): T =
    suspendCancellableCoroutine { continuation ->
        addListener(
            {
                if (continuation.isActive) {
                    try {
                        continuation.resume(get())
                    } catch (error: ExecutionException) {
                        continuation.resumeWithException(error.cause ?: error)
                    } catch (error: Throwable) {
                        continuation.resumeWithException(error)
                    }
                }
            },
            DIRECT_EXECUTOR,
        )
        continuation.invokeOnCancellation { cancel(true) }
    }

private val DIRECT_EXECUTOR = Executor { command -> command.run() }
