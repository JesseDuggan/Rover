import 'package:flutter_test/flutter_test.dart';
import 'package:rover/src/on_device_ai/rover_ai_models.dart';
import 'package:rover/src/on_device_ai/rover_ai_provider.dart';
import 'package:rover/src/on_device_ai/rover_lens_service.dart';
import 'package:rover/src/on_device_ai/rover_on_device_ai_coordinator.dart';
import 'package:rover/src/on_device_ai/rover_phase13_flags.dart';

void main() {
  test('returns OCR text and conservatively matches a nearby place', () async {
    final provider = _LensProvider(
      result: _result(text: 'Welcome to the WESTPORT MUSEUM\nOpen daily'),
    );
    final service = RoverLensService(_coordinator(provider));

    final analysis = await service.recognizeText(
      localImagePath: '/temporary/capture.jpg',
      nearbyCandidates: const [
        RoverLensCandidate(id: 'museum', name: 'Westport Museum'),
        RoverLensCandidate(id: 'cafe', name: 'Tangled Garden Cafe'),
      ],
    );

    expect(analysis.succeeded, isTrue);
    expect(analysis.matchedCandidateId, 'museum');
    expect(analysis.recognizedText, contains('WESTPORT MUSEUM'));
    expect(provider.lastRequest!.requiresImageUpload, isFalse);
    expect(
      provider.lastRequest!.context.privacyPolicy.cameraUploadAllowed,
      isFalse,
    );
  });

  test('does not claim a match for partial or ambiguous text', () async {
    final provider = _LensProvider(result: _result(text: 'Westport welcome'));
    final service = RoverLensService(_coordinator(provider));

    final analysis = await service.recognizeText(
      localImagePath: '/temporary/capture.jpg',
      nearbyCandidates: const [
        RoverLensCandidate(id: 'museum', name: 'Westport Museum'),
      ],
    );

    expect(analysis.matchedCandidateId, isNull);
    expect(analysis.message, contains('not verified'));
  });

  test('returns a useful no-text result', () async {
    final provider = _LensProvider(result: _result());
    final service = RoverLensService(_coordinator(provider));

    final analysis = await service.recognizeText(
      localImagePath: '/temporary/capture.jpg',
      nearbyCandidates: const [],
    );

    expect(analysis.succeeded, isTrue);
    expect(analysis.recognizedText, isNull);
    expect(analysis.message, contains('No readable text'));
  });

  test('disabled flags prevent native execution', () async {
    final provider = _LensProvider(result: _result(text: 'ignored'));
    final coordinator = RoverOnDeviceAiCoordinator(
      flags: const RoverPhase13Flags(),
      provider: provider,
    );
    final service = RoverLensService(coordinator);

    final analysis = await service.recognizeText(
      localImagePath: '/temporary/capture.jpg',
      nearbyCandidates: const [],
    );

    expect(analysis.status, RoverAiResultStatus.unavailable);
    expect(analysis.message, contains('not enabled'));
    expect(provider.executeCalls, 0);
    await coordinator.dispose();
  });
}

RoverOnDeviceAiCoordinator _coordinator(_LensProvider provider) {
  return RoverOnDeviceAiCoordinator(
    flags: const RoverPhase13Flags(enabled: true, lensOcr: true),
    provider: provider,
  );
}

RoverAiResult<RoverAiPayload> _result({String? text}) {
  return RoverAiResult<RoverAiPayload>(
    correlationId: 'native',
    status: RoverAiResultStatus.success,
    provider: 'ML Kit Text Recognition v2',
    operation: RoverAiOperation.lensOcr,
    processingLocation: RoverAiProcessingLocation.device,
    verificationState: text == null
        ? RoverAiVerificationState.notApplicable
        : RoverAiVerificationState.candidate,
    duration: const Duration(milliseconds: 10),
    fallbackUsed: false,
    diagnosticCode: text == null ? 'lens_ocr_no_text' : 'lens_ocr_completed',
    payload: text == null ? null : RoverAiTextPayload(text),
    policyDecisions: const ['local_only', 'candidate_unverified'],
  );
}

class _LensProvider implements RoverAiProvider {
  _LensProvider({required this.result});

  final RoverAiResult<RoverAiPayload> result;
  RoverAiRequest? lastRequest;
  int executeCalls = 0;

  @override
  String get name => 'fake-lens';

  @override
  Future<void> cancel(String correlationId) async {}

  @override
  Future<RoverAiResult<RoverAiPayload>> execute(RoverAiRequest request) async {
    executeCalls++;
    lastRequest = request;
    return RoverAiResult<RoverAiPayload>(
      correlationId: request.context.correlationId,
      status: result.status,
      provider: result.provider,
      operation: result.operation,
      processingLocation: result.processingLocation,
      verificationState: result.verificationState,
      duration: result.duration,
      fallbackUsed: result.fallbackUsed,
      diagnosticCode: result.diagnosticCode,
      payload: result.payload,
      policyDecisions: result.policyDecisions,
    );
  }

  @override
  Future<RoverAiCapabilitySnapshot> getCapabilities() async {
    const available = RoverAiFeatureCapability(
      availability: RoverAiCapabilityAvailability.available,
      provider: 'fake-lens',
    );
    return RoverAiCapabilitySnapshot(
      platform: 'android',
      apiLevel: 36,
      manufacturer: 'Samsung',
      model: 'Fold7',
      prompt: RoverAiFeatureCapability.unavailable,
      imageDescription: RoverAiFeatureCapability.unavailable,
      ocr: available,
      objectDetection: RoverAiFeatureCapability.unavailable,
      speechRecognition: RoverAiFeatureCapability.unavailable,
      localCuration: RoverAiFeatureCapability.unavailable,
      offlineIntelligence: RoverAiFeatureCapability.unavailable,
      foregroundEligible: true,
      batterySaverEnabled: false,
      thermalState: RoverAiThermalState.nominal,
      memoryPressure: false,
      quotaLimited: false,
      checkedAtUtc: DateTime.utc(2026, 8, 31),
    );
  }
}
