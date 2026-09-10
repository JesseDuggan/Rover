package ai.myrover.rover.ai

import ai.myrover.rover.ai.generated.NativeRoverAiCapabilitySnapshot
import ai.myrover.rover.ai.generated.NativeRoverAiOperation
import ai.myrover.rover.ai.generated.NativeRoverAiRequest
import ai.myrover.rover.ai.generated.NativeRoverAiResult
import ai.myrover.rover.ai.generated.NativeRoverAiResultStatus
import ai.myrover.rover.ai.generated.RoverOnDeviceAiHostApi
import android.content.Context
import java.util.LinkedHashSet

internal class RoverOnDeviceAiHostApiImpl(
    context: Context,
    private val isForegroundEligible: () -> Boolean,
) : RoverOnDeviceAiHostApi {
    private val capabilityService = DeviceCapabilityService(
        context = context.applicationContext,
        isForegroundEligible = isForegroundEligible,
    )
    private val lensProvider = OnDeviceLensProvider(context.applicationContext)
    private val cancellationLock = Any()
    private val cancelledCorrelationIds = LinkedHashSet<String>()

    override fun getBridgeVersion(): String = BRIDGE_VERSION

    override suspend fun getCapabilities(): NativeRoverAiCapabilitySnapshot =
        capabilityService.snapshot()

    override suspend fun execute(request: NativeRoverAiRequest): NativeRoverAiResult {
        if (consumeCancellation(request.correlationId)) {
            return result(
                request = request,
                status = NativeRoverAiResultStatus.CANCELLED,
                diagnosticCode = "native_operation_cancelled",
            )
        }

        if (!isForegroundEligible()) {
            return result(
                request = request,
                status = NativeRoverAiResultStatus.DENIED,
                diagnosticCode = "native_background_ineligible",
            )
        }

        val operationResult = when (request.operation) {
            NativeRoverAiOperation.LENS_OCR ->
                lensProvider.recognizeText(request)
            else -> result(
                request = request,
                status = NativeRoverAiResultStatus.UNAVAILABLE,
                diagnosticCode = "native_operation_not_enabled_phase13_3",
            )
        }
        return if (consumeCancellation(request.correlationId)) {
            result(
                request = request,
                status = NativeRoverAiResultStatus.CANCELLED,
                diagnosticCode = "native_operation_cancelled",
            )
        } else {
            operationResult
        }
    }

    override fun cancel(correlationId: String) {
        synchronized(cancellationLock) {
            cancelledCorrelationIds.add(correlationId)
            while (cancelledCorrelationIds.size > MAX_CANCELLATION_MARKERS) {
                val first = cancelledCorrelationIds.iterator().next()
                cancelledCorrelationIds.remove(first)
            }
        }
    }

    private fun consumeCancellation(correlationId: String): Boolean =
        synchronized(cancellationLock) {
            cancelledCorrelationIds.remove(correlationId)
        }

    private fun result(
        request: NativeRoverAiRequest,
        status: NativeRoverAiResultStatus,
        diagnosticCode: String,
    ) = NativeRoverAiResult(
        correlationId = request.correlationId,
        status = status,
        provider = PROVIDER_NAME,
        operation = request.operation,
        durationMilliseconds = 0,
        fallbackUsed = false,
        diagnosticCode = diagnosticCode,
        candidateLabels = emptyList(),
        evidenceIds = emptyList(),
        policyDecisions = listOf("phase13_3_bounded_operation"),
    )

    companion object {
        private const val BRIDGE_VERSION = "1.1"
        private const val PROVIDER_NAME = "android-ml-kit"
        private const val MAX_CANCELLATION_MARKERS = 64
    }
}
