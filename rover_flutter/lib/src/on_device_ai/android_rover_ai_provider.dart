import 'generated/rover_on_device_ai_api.g.dart';
import 'rover_ai_models.dart';
import 'rover_ai_provider.dart';

abstract interface class RoverNativeAiBridge {
  Future<String> getBridgeVersion();

  Future<NativeRoverAiCapabilitySnapshot> getCapabilities();

  Future<NativeRoverAiResult> execute(NativeRoverAiRequest request);

  Future<void> cancel(String correlationId);
}

class PigeonRoverNativeAiBridge implements RoverNativeAiBridge {
  PigeonRoverNativeAiBridge({RoverOnDeviceAiHostApi? api})
    : _api = api ?? RoverOnDeviceAiHostApi();

  final RoverOnDeviceAiHostApi _api;

  @override
  Future<void> cancel(String correlationId) => _api.cancel(correlationId);

  @override
  Future<NativeRoverAiResult> execute(NativeRoverAiRequest request) =>
      _api.execute(request);

  @override
  Future<NativeRoverAiCapabilitySnapshot> getCapabilities() =>
      _api.getCapabilities();

  @override
  Future<String> getBridgeVersion() => _api.getBridgeVersion();
}

class AndroidRoverAiProvider
    implements RoverAiProvider, RoverAiDiagnosticsProvider {
  AndroidRoverAiProvider({RoverNativeAiBridge? bridge})
    : _bridge = bridge ?? PigeonRoverNativeAiBridge();

  final RoverNativeAiBridge _bridge;

  @override
  String get name => 'android-ml-kit';

  @override
  Future<String?> getBridgeVersion() => _bridge.getBridgeVersion();

  @override
  Future<RoverAiCapabilitySnapshot> getCapabilities() async {
    final snapshot = await _bridge.getCapabilities();
    return RoverAiCapabilitySnapshot(
      platform: 'android',
      apiLevel: snapshot.apiLevel,
      manufacturer: snapshot.manufacturer,
      model: snapshot.model,
      prompt: _mapCapability(snapshot.prompt),
      imageDescription: _mapCapability(snapshot.imageDescription),
      ocr: _mapCapability(snapshot.ocr),
      objectDetection: _mapCapability(snapshot.objectDetection),
      speechRecognition: _mapCapability(snapshot.speechRecognition),
      localCuration: _mapCapability(snapshot.localCuration),
      offlineIntelligence: _mapCapability(snapshot.offlineIntelligence),
      foregroundEligible: snapshot.foregroundEligible,
      batterySaverEnabled: snapshot.batterySaverEnabled,
      thermalState: _mapThermalState(snapshot.thermalState),
      memoryPressure: snapshot.memoryPressure,
      quotaLimited: snapshot.quotaLimited,
      checkedAtUtc: DateTime.fromMillisecondsSinceEpoch(
        snapshot.checkedAtEpochMilliseconds,
        isUtc: true,
      ),
      unavailabilityReason: snapshot.unavailabilityReason,
    );
  }

  @override
  Future<RoverAiResult<RoverAiPayload>> execute(RoverAiRequest request) async {
    try {
      final nativeResult = await _bridge.execute(
        NativeRoverAiRequest(
          correlationId: request.context.correlationId,
          operation: _mapOperationToNative(request.operation),
          timeoutMilliseconds: request.timeout.inMilliseconds,
          localImagePath: request.context.localImagePath,
        ),
      );
      final payload = _mapPayload(nativeResult);
      return RoverAiResult<RoverAiPayload>(
        correlationId: nativeResult.correlationId,
        status: _mapResultStatus(nativeResult.status),
        provider: nativeResult.provider,
        operation: _mapOperationFromNative(nativeResult.operation),
        processingLocation:
            nativeResult.status == NativeRoverAiResultStatus.success ||
                nativeResult.status == NativeRoverAiResultStatus.partial
            ? RoverAiProcessingLocation.device
            : RoverAiProcessingLocation.none,
        verificationState:
            nativeResult.candidateLabels.isNotEmpty ||
                (nativeResult.text?.trim().isNotEmpty ?? false)
            ? RoverAiVerificationState.candidate
            : RoverAiVerificationState.notApplicable,
        duration: Duration(milliseconds: nativeResult.durationMilliseconds),
        fallbackUsed: nativeResult.fallbackUsed,
        diagnosticCode: nativeResult.diagnosticCode,
        payload: payload,
        confidence: nativeResult.confidence,
        evidenceIds: List.unmodifiable(nativeResult.evidenceIds),
        policyDecisions: List.unmodifiable(nativeResult.policyDecisions),
      );
    } catch (_) {
      return RoverAiResult<RoverAiPayload>(
        correlationId: request.context.correlationId,
        status: RoverAiResultStatus.error,
        provider: name,
        operation: request.operation,
        processingLocation: RoverAiProcessingLocation.none,
        verificationState: RoverAiVerificationState.notApplicable,
        duration: Duration.zero,
        fallbackUsed: false,
        diagnosticCode: 'native_bridge_error',
      );
    }
  }

  @override
  Future<void> cancel(String correlationId) async {
    try {
      await _bridge.cancel(correlationId);
    } catch (_) {
      // Cancellation is best effort and must not replace the original result.
    }
  }

  RoverAiPayload? _mapPayload(NativeRoverAiResult result) {
    if (result.candidateLabels.isNotEmpty) {
      final capturedAtUtc = DateTime.now().toUtc();
      return RoverAiCandidatePayload(
        result.candidateLabels
            .map(
              (label) => RoverAiCandidateObservation(
                label: label,
                provider: result.provider,
                capturedAtUtc: capturedAtUtc,
                frameRetained: false,
                confidence: result.confidence,
              ),
            )
            .toList(growable: false),
      );
    }
    if (result.text case final text? when text.trim().isNotEmpty) {
      return RoverAiTextPayload(text);
    }
    return null;
  }
}

RoverAiFeatureCapability _mapCapability(
  NativeRoverAiFeatureCapability capability,
) => RoverAiFeatureCapability(
  availability: switch (capability.availability) {
    NativeRoverAiAvailability.available =>
      RoverAiCapabilityAvailability.available,
    NativeRoverAiAvailability.downloadable =>
      RoverAiCapabilityAvailability.downloadable,
    NativeRoverAiAvailability.downloading =>
      RoverAiCapabilityAvailability.downloading,
    NativeRoverAiAvailability.unavailable =>
      RoverAiCapabilityAvailability.unavailable,
    NativeRoverAiAvailability.unknown => RoverAiCapabilityAvailability.unknown,
  },
  provider: capability.provider,
  modelName: capability.modelName,
  modelVersion: capability.modelVersion,
  reason: capability.reason,
);

RoverAiThermalState _mapThermalState(NativeRoverAiThermalState state) =>
    switch (state) {
      NativeRoverAiThermalState.nominal => RoverAiThermalState.nominal,
      NativeRoverAiThermalState.fair => RoverAiThermalState.fair,
      NativeRoverAiThermalState.serious => RoverAiThermalState.serious,
      NativeRoverAiThermalState.critical => RoverAiThermalState.critical,
      NativeRoverAiThermalState.unknown => RoverAiThermalState.unknown,
    };

NativeRoverAiOperation _mapOperationToNative(RoverAiOperation operation) =>
    NativeRoverAiOperation.values[operation.index];

RoverAiOperation _mapOperationFromNative(NativeRoverAiOperation operation) =>
    RoverAiOperation.values[operation.index];

RoverAiResultStatus _mapResultStatus(NativeRoverAiResultStatus status) =>
    RoverAiResultStatus.values[status.index];
