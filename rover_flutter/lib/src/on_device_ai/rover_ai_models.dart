enum RoverAiOperation {
  onDevicePrompt,
  lensOcr,
  lensDescription,
  listenerLocalSpeech,
  curatorLocal,
  offlineIntelligence,
}

enum RoverAiResultStatus {
  success,
  partial,
  unavailable,
  denied,
  timeout,
  busy,
  quotaLimited,
  cancelled,
  error,
}

enum RoverAiProcessingLocation { device, roverBackend, none }

enum RoverAiVerificationState { candidate, verified, notApplicable }

enum RoverAiCapabilityAvailability {
  available,
  downloadable,
  downloading,
  unavailable,
  unknown,
}

enum RoverAiThermalState { nominal, fair, serious, critical, unknown }

class RoverAiFeatureCapability {
  const RoverAiFeatureCapability({
    required this.availability,
    this.provider,
    this.modelName,
    this.modelVersion,
    this.reason,
  });

  final RoverAiCapabilityAvailability availability;
  final String? provider;
  final String? modelName;
  final String? modelVersion;
  final String? reason;

  bool get isAvailable =>
      availability == RoverAiCapabilityAvailability.available;

  static const unavailable = RoverAiFeatureCapability(
    availability: RoverAiCapabilityAvailability.unavailable,
    reason: 'The feature is not available from the configured provider.',
  );
}

class RoverAiCapabilitySnapshot {
  const RoverAiCapabilitySnapshot({
    required this.platform,
    required this.manufacturer,
    required this.model,
    required this.prompt,
    required this.imageDescription,
    required this.ocr,
    required this.objectDetection,
    required this.speechRecognition,
    required this.localCuration,
    required this.offlineIntelligence,
    required this.foregroundEligible,
    required this.batterySaverEnabled,
    required this.thermalState,
    required this.memoryPressure,
    required this.quotaLimited,
    required this.checkedAtUtc,
    this.apiLevel,
    this.unavailabilityReason,
  });

  final String platform;
  final int? apiLevel;
  final String manufacturer;
  final String model;
  final RoverAiFeatureCapability prompt;
  final RoverAiFeatureCapability imageDescription;
  final RoverAiFeatureCapability ocr;
  final RoverAiFeatureCapability objectDetection;
  final RoverAiFeatureCapability speechRecognition;
  final RoverAiFeatureCapability localCuration;
  final RoverAiFeatureCapability offlineIntelligence;
  final bool foregroundEligible;
  final bool batterySaverEnabled;
  final RoverAiThermalState thermalState;
  final bool memoryPressure;
  final bool quotaLimited;
  final DateTime checkedAtUtc;
  final String? unavailabilityReason;

  RoverAiFeatureCapability capabilityFor(RoverAiOperation operation) {
    return switch (operation) {
      RoverAiOperation.onDevicePrompt => prompt,
      RoverAiOperation.lensOcr => ocr,
      RoverAiOperation.lensDescription => imageDescription,
      RoverAiOperation.listenerLocalSpeech => speechRecognition,
      RoverAiOperation.curatorLocal => localCuration,
      RoverAiOperation.offlineIntelligence => offlineIntelligence,
    };
  }

  factory RoverAiCapabilitySnapshot.unsupported({
    required DateTime checkedAtUtc,
    String reason = 'On-device AI is disabled or unsupported.',
  }) {
    final unavailable = RoverAiFeatureCapability(
      availability: RoverAiCapabilityAvailability.unavailable,
      reason: reason,
    );
    return RoverAiCapabilitySnapshot(
      platform: 'unsupported',
      manufacturer: 'unknown',
      model: 'unknown',
      prompt: unavailable,
      imageDescription: unavailable,
      ocr: unavailable,
      objectDetection: unavailable,
      speechRecognition: unavailable,
      localCuration: unavailable,
      offlineIntelligence: unavailable,
      foregroundEligible: false,
      batterySaverEnabled: false,
      thermalState: RoverAiThermalState.unknown,
      memoryPressure: false,
      quotaLimited: false,
      checkedAtUtc: checkedAtUtc,
      unavailabilityReason: reason,
    );
  }
}

class RoverAiPrivacyPolicy {
  const RoverAiPrivacyPolicy({
    this.cameraPermissionGranted = false,
    this.microphonePermissionGranted = false,
    this.preciseLocationAllowed = false,
    this.cloudFallbackAllowed = false,
    this.cameraUploadAllowed = false,
    this.foregroundEligible = true,
  });

  final bool cameraPermissionGranted;
  final bool microphonePermissionGranted;
  final bool preciseLocationAllowed;
  final bool cloudFallbackAllowed;
  final bool cameraUploadAllowed;
  final bool foregroundEligible;
}

class RoverAiLocationContext {
  const RoverAiLocationContext({
    required this.latitude,
    required this.longitude,
    required this.accuracyMeters,
    required this.isPrecise,
    this.headingDegrees,
    this.headingAccuracyDegrees,
    this.speedMetersPerSecond,
  });

  final double latitude;
  final double longitude;
  final double accuracyMeters;
  final bool isPrecise;
  final double? headingDegrees;
  final double? headingAccuracyDegrees;
  final double? speedMetersPerSecond;
}

class RoverAiBoundingRegion {
  const RoverAiBoundingRegion({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  final double left;
  final double top;
  final double right;
  final double bottom;
}

class RoverAiCandidateObservation {
  const RoverAiCandidateObservation({
    required this.label,
    required this.provider,
    required this.capturedAtUtc,
    required this.frameRetained,
    this.confidence,
    this.boundingRegion,
  });

  final String label;
  final String provider;
  final DateTime capturedAtUtc;
  final bool frameRetained;
  final double? confidence;
  final RoverAiBoundingRegion? boundingRegion;
}

class RoverAiRequestContext {
  const RoverAiRequestContext({
    required this.correlationId,
    required this.requestedAtUtc,
    required this.locale,
    required this.userIntent,
    required this.privacyPolicy,
    this.location,
    this.routeId,
    this.journeyId,
    this.stopId,
    this.nearbyVerifiedPoiIds = const [],
    this.storyFactIds = const [],
    this.localImagePath,
  });

  final String correlationId;
  final DateTime requestedAtUtc;
  final String locale;
  final String userIntent;
  final RoverAiPrivacyPolicy privacyPolicy;
  final RoverAiLocationContext? location;
  final String? routeId;
  final String? journeyId;
  final String? stopId;
  final List<String> nearbyVerifiedPoiIds;
  final List<String> storyFactIds;
  final String? localImagePath;
}

class RoverAiRequest {
  const RoverAiRequest({
    required this.operation,
    required this.context,
    this.timeout = const Duration(seconds: 10),
    this.allowCloudFallback = false,
    this.requiresImageUpload = false,
  });

  final RoverAiOperation operation;
  final RoverAiRequestContext context;
  final Duration timeout;
  final bool allowCloudFallback;
  final bool requiresImageUpload;
}

abstract interface class RoverAiPayload {}

class RoverAiTextPayload implements RoverAiPayload {
  const RoverAiTextPayload(this.text);

  final String text;
}

class RoverAiCandidatePayload implements RoverAiPayload {
  const RoverAiCandidatePayload(this.observations);

  final List<RoverAiCandidateObservation> observations;
}

class RoverAiCommandPayload implements RoverAiPayload {
  const RoverAiCommandPayload({
    required this.command,
    this.arguments = const {},
  });

  final String command;
  final Map<String, String> arguments;
}

class RoverAiResult<T extends RoverAiPayload> {
  const RoverAiResult({
    required this.correlationId,
    required this.status,
    required this.provider,
    required this.operation,
    required this.processingLocation,
    required this.verificationState,
    required this.duration,
    required this.fallbackUsed,
    required this.diagnosticCode,
    this.payload,
    this.confidence,
    this.evidenceIds = const [],
    this.policyDecisions = const [],
  });

  final String correlationId;
  final RoverAiResultStatus status;
  final String provider;
  final RoverAiOperation operation;
  final RoverAiProcessingLocation processingLocation;
  final RoverAiVerificationState verificationState;
  final Duration duration;
  final bool fallbackUsed;
  final String diagnosticCode;
  final T? payload;
  final double? confidence;
  final List<String> evidenceIds;
  final List<String> policyDecisions;

  RoverAiResult<T> withDuration(Duration value) {
    return RoverAiResult<T>(
      correlationId: correlationId,
      status: status,
      provider: provider,
      operation: operation,
      processingLocation: processingLocation,
      verificationState: verificationState,
      duration: value,
      fallbackUsed: fallbackUsed,
      diagnosticCode: diagnosticCode,
      payload: payload,
      confidence: confidence,
      evidenceIds: evidenceIds,
      policyDecisions: policyDecisions,
    );
  }
}
