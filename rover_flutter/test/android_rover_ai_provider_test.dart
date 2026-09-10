import 'package:flutter_test/flutter_test.dart';
import 'package:rover/src/on_device_ai/android_rover_ai_provider.dart';
import 'package:rover/src/on_device_ai/generated/rover_on_device_ai_api.g.dart';
import 'package:rover/src/on_device_ai/rover_ai_models.dart';

void main() {
  test('maps Android runtime capabilities into Phase 13 models', () async {
    final provider = AndroidRoverAiProvider(
      bridge: _FakeNativeBridge(capabilities: _capabilities()),
    );

    final snapshot = await provider.getCapabilities();

    expect(snapshot.platform, 'android');
    expect(snapshot.apiLevel, 36);
    expect(
      snapshot.prompt.availability,
      RoverAiCapabilityAvailability.downloadable,
    );
    expect(snapshot.imageDescription.isAvailable, isTrue);
    expect(snapshot.ocr.isAvailable, isTrue);
    expect(snapshot.batterySaverEnabled, isTrue);
    expect(snapshot.thermalState, RoverAiThermalState.fair);
    expect(
      snapshot.checkedAtUtc,
      DateTime.fromMillisecondsSinceEpoch(1234, isUtc: true),
    );
  });

  test('maps native unsupported result without claiming device work', () async {
    final bridge = _FakeNativeBridge(
      capabilities: _capabilities(),
      result: NativeRoverAiResult(
        correlationId: 'request-1',
        status: NativeRoverAiResultStatus.unavailable,
        provider: 'android-ml-kit',
        operation: NativeRoverAiOperation.lensDescription,
        durationMilliseconds: 3,
        fallbackUsed: false,
        diagnosticCode: 'native_operation_not_enabled_phase13_2',
        candidateLabels: const [],
        evidenceIds: const [],
        policyDecisions: const ['phase13_2_capability_only'],
      ),
    );
    final provider = AndroidRoverAiProvider(bridge: bridge);

    final result = await provider.execute(_request());

    expect(result.status, RoverAiResultStatus.unavailable);
    expect(result.processingLocation, RoverAiProcessingLocation.none);
    expect(result.verificationState, RoverAiVerificationState.notApplicable);
    expect(result.payload, isNull);
    expect(result.policyDecisions, ['phase13_2_capability_only']);
  });

  test('maps candidate labels as unverified observations', () async {
    final bridge = _FakeNativeBridge(
      capabilities: _capabilities(),
      result: NativeRoverAiResult(
        correlationId: 'request-1',
        status: NativeRoverAiResultStatus.success,
        provider: 'android-ml-kit',
        operation: NativeRoverAiOperation.lensDescription,
        durationMilliseconds: 12,
        fallbackUsed: false,
        diagnosticCode: 'ok',
        candidateLabels: const ['brick storefront'],
        confidence: 0.7,
        evidenceIds: const [],
        policyDecisions: const [],
      ),
    );
    final provider = AndroidRoverAiProvider(bridge: bridge);

    final result = await provider.execute(_request());

    expect(result.status, RoverAiResultStatus.success);
    expect(result.verificationState, RoverAiVerificationState.candidate);
    final payload = result.payload! as RoverAiCandidatePayload;
    expect(payload.observations.single.label, 'brick storefront');
    expect(payload.observations.single.frameRetained, isFalse);
  });

  test('maps OCR text as an unverified local candidate', () async {
    final bridge = _FakeNativeBridge(
      capabilities: _capabilities(),
      result: NativeRoverAiResult(
        correlationId: 'request-1',
        status: NativeRoverAiResultStatus.success,
        provider: 'ML Kit Text Recognition v2',
        operation: NativeRoverAiOperation.lensOcr,
        durationMilliseconds: 18,
        fallbackUsed: false,
        diagnosticCode: 'lens_ocr_completed',
        text: 'Westport Museum',
        candidateLabels: const [],
        evidenceIds: const [],
        policyDecisions: const ['local_only', 'candidate_unverified'],
      ),
    );
    final provider = AndroidRoverAiProvider(bridge: bridge);

    final result = await provider.execute(
      _request(operation: RoverAiOperation.lensOcr),
    );

    expect(result.status, RoverAiResultStatus.success);
    expect(result.verificationState, RoverAiVerificationState.candidate);
    expect((result.payload! as RoverAiTextPayload).text, 'Westport Museum');
    expect(result.evidenceIds, isEmpty);
  });

  test('native bridge exceptions become privacy-safe typed errors', () async {
    final provider = AndroidRoverAiProvider(
      bridge: _FakeNativeBridge(
        capabilities: _capabilities(),
        executeError: StateError('sensitive native detail'),
      ),
    );

    final result = await provider.execute(_request());

    expect(result.status, RoverAiResultStatus.error);
    expect(result.diagnosticCode, 'native_bridge_error');
  });

  test('forwards cancellation to the typed bridge', () async {
    final bridge = _FakeNativeBridge(capabilities: _capabilities());
    final provider = AndroidRoverAiProvider(bridge: bridge);

    await provider.cancel('cancel-me');

    expect(bridge.cancelledIds, ['cancel-me']);
  });
}

RoverAiRequest _request({
  RoverAiOperation operation = RoverAiOperation.lensDescription,
}) => RoverAiRequest(
  operation: operation,
  context: RoverAiRequestContext(
    correlationId: 'request-1',
    requestedAtUtc: _requestedAtUtc,
    locale: 'en-CA',
    userIntent: 'describe',
    privacyPolicy: RoverAiPrivacyPolicy(cameraPermissionGranted: true),
    localImagePath: 'temporary.jpg',
  ),
);

final _requestedAtUtc = DateTime.utc(2026, 8, 31);

NativeRoverAiCapabilitySnapshot _capabilities() =>
    NativeRoverAiCapabilitySnapshot(
      apiLevel: 36,
      manufacturer: 'Samsung',
      model: 'Fold7',
      prompt: NativeRoverAiFeatureCapability(
        availability: NativeRoverAiAvailability.downloadable,
        provider: 'ML Kit Prompt API',
      ),
      imageDescription: NativeRoverAiFeatureCapability(
        availability: NativeRoverAiAvailability.available,
      ),
      ocr: NativeRoverAiFeatureCapability(
        availability: NativeRoverAiAvailability.available,
      ),
      objectDetection: NativeRoverAiFeatureCapability(
        availability: NativeRoverAiAvailability.unavailable,
      ),
      speechRecognition: NativeRoverAiFeatureCapability(
        availability: NativeRoverAiAvailability.available,
      ),
      localCuration: NativeRoverAiFeatureCapability(
        availability: NativeRoverAiAvailability.unavailable,
      ),
      offlineIntelligence: NativeRoverAiFeatureCapability(
        availability: NativeRoverAiAvailability.unavailable,
      ),
      foregroundEligible: true,
      batterySaverEnabled: true,
      thermalState: NativeRoverAiThermalState.fair,
      memoryPressure: false,
      quotaLimited: false,
      checkedAtEpochMilliseconds: 1234,
    );

class _FakeNativeBridge implements RoverNativeAiBridge {
  _FakeNativeBridge({
    required this.capabilities,
    this.result,
    this.executeError,
  });

  final NativeRoverAiCapabilitySnapshot capabilities;
  final NativeRoverAiResult? result;
  final Object? executeError;
  final List<String> cancelledIds = [];

  @override
  Future<void> cancel(String correlationId) async {
    cancelledIds.add(correlationId);
  }

  @override
  Future<NativeRoverAiResult> execute(NativeRoverAiRequest request) async {
    if (executeError case final error?) {
      throw error;
    }
    return result ??
        NativeRoverAiResult(
          correlationId: request.correlationId,
          status: NativeRoverAiResultStatus.unavailable,
          provider: 'android-ml-kit',
          operation: request.operation,
          durationMilliseconds: 0,
          fallbackUsed: false,
          diagnosticCode: 'native_operation_not_enabled_phase13_2',
          candidateLabels: const [],
          evidenceIds: const [],
          policyDecisions: const [],
        );
  }

  @override
  Future<NativeRoverAiCapabilitySnapshot> getCapabilities() async =>
      capabilities;

  @override
  Future<String> getBridgeVersion() async => '1.0';
}
