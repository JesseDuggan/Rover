import 'package:flutter_test/flutter_test.dart';
import 'package:rover/src/on_device_ai/rover_ai_models.dart';
import 'package:rover/src/on_device_ai/rover_phase13_flags.dart';

void main() {
  test('Phase 13 and every capability default to disabled', () {
    const flags = RoverPhase13Flags();

    expect(flags.enabled, isFalse);
    for (final operation in RoverAiOperation.values) {
      expect(flags.enables(operation), isFalse);
    }
    expect(flags.cloudFallback, isFalse);
    expect(flags.cameraUpload, isFalse);
  });

  test('master flag still gates individually enabled capabilities', () {
    const disabledMaster = RoverPhase13Flags(lensOcr: true);
    const enabledMaster = RoverPhase13Flags(enabled: true, lensOcr: true);

    expect(disabledMaster.enables(RoverAiOperation.lensOcr), isFalse);
    expect(enabledMaster.enables(RoverAiOperation.lensOcr), isTrue);
    expect(enabledMaster.enables(RoverAiOperation.lensDescription), isFalse);
  });

  test('candidate observation is explicitly unverified', () {
    final observation = RoverAiCandidateObservation(
      label: 'Possible museum sign',
      provider: 'test-lens',
      capturedAtUtc: DateTime.utc(2026, 8, 31),
      frameRetained: false,
      confidence: 0.72,
    );
    final result = RoverAiResult<RoverAiCandidatePayload>(
      correlationId: 'candidate-1',
      status: RoverAiResultStatus.success,
      provider: 'test-lens',
      operation: RoverAiOperation.lensOcr,
      processingLocation: RoverAiProcessingLocation.device,
      verificationState: RoverAiVerificationState.candidate,
      duration: const Duration(milliseconds: 20),
      fallbackUsed: false,
      diagnosticCode: 'candidate_created',
      payload: RoverAiCandidatePayload([observation]),
    );

    expect(result.verificationState, RoverAiVerificationState.candidate);
    expect(result.evidenceIds, isEmpty);
    expect(result.payload!.observations.single.frameRetained, isFalse);
  });

  test('unsupported capability snapshot reports every feature unavailable', () {
    final snapshot = RoverAiCapabilitySnapshot.unsupported(
      checkedAtUtc: DateTime.utc(2026, 8, 31),
    );

    for (final operation in RoverAiOperation.values) {
      expect(snapshot.capabilityFor(operation).isAvailable, isFalse);
    }
    expect(snapshot.foregroundEligible, isFalse);
  });
}
