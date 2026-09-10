import 'rover_ai_models.dart';
import 'rover_phase13_flags.dart';

class RoverAiGuardianDecision {
  const RoverAiGuardianDecision._({
    required this.allowed,
    required this.status,
    required this.diagnosticCode,
    required this.policyDecisions,
  });

  final bool allowed;
  final RoverAiResultStatus status;
  final String diagnosticCode;
  final List<String> policyDecisions;

  factory RoverAiGuardianDecision.allow(List<String> decisions) {
    return RoverAiGuardianDecision._(
      allowed: true,
      status: RoverAiResultStatus.success,
      diagnosticCode: 'allowed',
      policyDecisions: decisions,
    );
  }

  factory RoverAiGuardianDecision.block({
    required RoverAiResultStatus status,
    required String diagnosticCode,
    required List<String> decisions,
  }) {
    return RoverAiGuardianDecision._(
      allowed: false,
      status: status,
      diagnosticCode: diagnosticCode,
      policyDecisions: decisions,
    );
  }
}

class RoverAiGuardian {
  const RoverAiGuardian(this.flags);

  final RoverPhase13Flags flags;

  RoverAiGuardianDecision evaluate(
    RoverAiRequest request, {
    RoverAiCapabilitySnapshot? capabilities,
  }) {
    final policy = request.context.privacyPolicy;
    final decisions = <String>[];

    if (!flags.enabled) {
      return RoverAiGuardianDecision.block(
        status: RoverAiResultStatus.unavailable,
        diagnosticCode: 'phase13_disabled',
        decisions: const ['Phase 13 master flag is disabled.'],
      );
    }
    if (!flags.enables(request.operation)) {
      return RoverAiGuardianDecision.block(
        status: RoverAiResultStatus.unavailable,
        diagnosticCode: 'operation_disabled',
        decisions: const ['The requested bounded capability is disabled.'],
      );
    }
    if (!policy.foregroundEligible) {
      return RoverAiGuardianDecision.block(
        status: RoverAiResultStatus.denied,
        diagnosticCode: 'foreground_required',
        decisions: const [
          'On-device AI requires an eligible foreground state.',
        ],
      );
    }
    if (_usesCamera(request.operation) && !policy.cameraPermissionGranted) {
      return RoverAiGuardianDecision.block(
        status: RoverAiResultStatus.denied,
        diagnosticCode: 'camera_permission_required',
        decisions: const ['Camera permission was not granted.'],
      );
    }
    if (request.operation == RoverAiOperation.listenerLocalSpeech &&
        !policy.microphonePermissionGranted) {
      return RoverAiGuardianDecision.block(
        status: RoverAiResultStatus.denied,
        diagnosticCode: 'microphone_permission_required',
        decisions: const ['Microphone permission was not granted.'],
      );
    }
    if (request.context.location?.isPrecise == true &&
        !policy.preciseLocationAllowed) {
      return RoverAiGuardianDecision.block(
        status: RoverAiResultStatus.denied,
        diagnosticCode: 'precise_location_denied',
        decisions: const ['Precise location use was not permitted.'],
      );
    }
    if (request.requiresImageUpload &&
        (!flags.cameraUpload || !policy.cameraUploadAllowed)) {
      return RoverAiGuardianDecision.block(
        status: RoverAiResultStatus.denied,
        diagnosticCode: 'camera_upload_denied',
        decisions: const ['Camera upload is disabled by policy.'],
      );
    }
    if (request.allowCloudFallback &&
        (!flags.cloudFallback || !policy.cloudFallbackAllowed)) {
      return RoverAiGuardianDecision.block(
        status: RoverAiResultStatus.denied,
        diagnosticCode: 'cloud_fallback_denied',
        decisions: const ['Cloud fallback is disabled by policy.'],
      );
    }

    decisions.add('Local bounded processing permitted.');
    if (capabilities == null) {
      return RoverAiGuardianDecision.allow(decisions);
    }
    if (!capabilities.foregroundEligible) {
      return RoverAiGuardianDecision.block(
        status: RoverAiResultStatus.denied,
        diagnosticCode: 'provider_background_blocked',
        decisions: const ['The provider is not foreground eligible.'],
      );
    }
    if (capabilities.quotaLimited) {
      return RoverAiGuardianDecision.block(
        status: RoverAiResultStatus.quotaLimited,
        diagnosticCode: 'provider_quota_limited',
        decisions: const ['The provider reported a quota limit.'],
      );
    }
    if (capabilities.thermalState == RoverAiThermalState.critical ||
        capabilities.memoryPressure) {
      return RoverAiGuardianDecision.block(
        status: RoverAiResultStatus.busy,
        diagnosticCode: 'device_pressure',
        decisions: const ['Device conditions are not suitable for AI work.'],
      );
    }
    if (!capabilities.capabilityFor(request.operation).isAvailable) {
      return RoverAiGuardianDecision.block(
        status: RoverAiResultStatus.unavailable,
        diagnosticCode: 'capability_unavailable',
        decisions: const ['The requested device capability is unavailable.'],
      );
    }
    return RoverAiGuardianDecision.allow(decisions);
  }

  bool _usesCamera(RoverAiOperation operation) {
    return operation == RoverAiOperation.lensOcr ||
        operation == RoverAiOperation.lensDescription;
  }
}
