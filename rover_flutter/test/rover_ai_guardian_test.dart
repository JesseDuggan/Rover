import 'package:flutter_test/flutter_test.dart';
import 'package:rover/src/on_device_ai/rover_ai_guardian.dart';
import 'package:rover/src/on_device_ai/rover_ai_models.dart';
import 'package:rover/src/on_device_ai/rover_phase13_flags.dart';

void main() {
  test('OCR does not require Gemini Nano or a particular phone model', () {
    const guardian = RoverAiGuardian(
      RoverPhase13Flags(enabled: true, lensOcr: true),
    );
    for (final model in [
      'Fold5',
      'Fold7',
      'S24',
      'S22',
      'Other manufacturer',
    ]) {
      final capabilities = _availableCapabilities(
        model: model,
        nanoUnavailable: true,
      );
      final decision = guardian.evaluate(
        _request(
          operation: RoverAiOperation.lensOcr,
          policy: const RoverAiPrivacyPolicy(cameraPermissionGranted: true),
        ),
        capabilities: capabilities,
      );
      expect(decision.allowed, isTrue, reason: model);
    }
  });
  test('master disable blocks all Phase 13 work', () {
    const guardian = RoverAiGuardian(RoverPhase13Flags());

    final decision = guardian.evaluate(_request());

    expect(decision.allowed, isFalse);
    expect(decision.status, RoverAiResultStatus.unavailable);
    expect(decision.diagnosticCode, 'phase13_disabled');
  });

  test('camera work requires permission', () {
    const guardian = RoverAiGuardian(
      RoverPhase13Flags(enabled: true, lensDescription: true),
    );

    final decision = guardian.evaluate(
      _request(
        operation: RoverAiOperation.lensDescription,
        policy: const RoverAiPrivacyPolicy(),
      ),
    );

    expect(decision.allowed, isFalse);
    expect(decision.status, RoverAiResultStatus.denied);
    expect(decision.diagnosticCode, 'camera_permission_required');
  });

  test('camera upload stays denied without both flag and consent', () {
    const guardian = RoverAiGuardian(
      RoverPhase13Flags(enabled: true, lensOcr: true),
    );

    final decision = guardian.evaluate(
      _request(
        operation: RoverAiOperation.lensOcr,
        requiresImageUpload: true,
        policy: const RoverAiPrivacyPolicy(cameraPermissionGranted: true),
      ),
    );

    expect(decision.allowed, isFalse);
    expect(decision.diagnosticCode, 'camera_upload_denied');
  });

  test('precise location requires policy permission', () {
    const guardian = RoverAiGuardian(
      RoverPhase13Flags(enabled: true, onDevicePrompt: true),
    );

    final decision = guardian.evaluate(
      _request(
        location: const RoverAiLocationContext(
          latitude: 44.68,
          longitude: -76.4,
          accuracyMeters: 4,
          isPrecise: true,
        ),
      ),
    );

    expect(decision.allowed, isFalse);
    expect(decision.diagnosticCode, 'precise_location_denied');
  });

  test('available capability and permitted policy allow bounded work', () {
    const guardian = RoverAiGuardian(
      RoverPhase13Flags(enabled: true, onDevicePrompt: true),
    );

    final decision = guardian.evaluate(
      _request(),
      capabilities: _availableCapabilities(),
    );

    expect(decision.allowed, isTrue);
    expect(decision.diagnosticCode, 'allowed');
  });

  test('critical thermal state blocks optional AI work', () {
    const guardian = RoverAiGuardian(
      RoverPhase13Flags(enabled: true, onDevicePrompt: true),
    );
    final capabilities = _availableCapabilities(
      thermalState: RoverAiThermalState.critical,
    );

    final decision = guardian.evaluate(_request(), capabilities: capabilities);

    expect(decision.allowed, isFalse);
    expect(decision.status, RoverAiResultStatus.busy);
    expect(decision.diagnosticCode, 'device_pressure');
  });
}

RoverAiRequest _request({
  RoverAiOperation operation = RoverAiOperation.onDevicePrompt,
  RoverAiPrivacyPolicy policy = const RoverAiPrivacyPolicy(),
  RoverAiLocationContext? location,
  bool requiresImageUpload = false,
}) {
  return RoverAiRequest(
    operation: operation,
    requiresImageUpload: requiresImageUpload,
    context: RoverAiRequestContext(
      correlationId: 'guardian-test',
      requestedAtUtc: DateTime.utc(2026, 8, 31),
      locale: 'en-CA',
      userIntent: 'test',
      privacyPolicy: policy,
      location: location,
    ),
  );
}

RoverAiCapabilitySnapshot _availableCapabilities({
  RoverAiThermalState thermalState = RoverAiThermalState.nominal,
  String model = 'Test device',
  bool nanoUnavailable = false,
}) {
  const available = RoverAiFeatureCapability(
    availability: RoverAiCapabilityAvailability.available,
    provider: 'test',
  );
  return RoverAiCapabilitySnapshot(
    platform: 'android',
    apiLevel: 36,
    manufacturer: 'Samsung',
    model: model,
    prompt: nanoUnavailable
        ? const RoverAiFeatureCapability(
            availability: RoverAiCapabilityAvailability.unavailable,
          )
        : available,
    imageDescription: nanoUnavailable
        ? const RoverAiFeatureCapability(
            availability: RoverAiCapabilityAvailability.unavailable,
          )
        : available,
    ocr: available,
    objectDetection: available,
    speechRecognition: available,
    localCuration: available,
    offlineIntelligence: available,
    foregroundEligible: true,
    batterySaverEnabled: false,
    thermalState: thermalState,
    memoryPressure: false,
    quotaLimited: false,
    checkedAtUtc: DateTime.utc(2026, 8, 31),
  );
}
