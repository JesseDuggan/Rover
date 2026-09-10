import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartPackageName: 'rover',
    dartOut: 'lib/src/on_device_ai/generated/rover_on_device_ai_api.g.dart',
    kotlinOut: 'android/app/src/main/kotlin/ai/myrover/rover/ai/generated/RoverOnDeviceAiApi.g.kt',
    kotlinOptions: KotlinOptions(package: 'ai.myrover.rover.ai.generated'),
  ),
)
enum NativeRoverAiOperation {
  onDevicePrompt,
  lensOcr,
  lensDescription,
  listenerLocalSpeech,
  curatorLocal,
  offlineIntelligence,
}

enum NativeRoverAiAvailability {
  available,
  downloadable,
  downloading,
  unavailable,
  unknown,
}

enum NativeRoverAiResultStatus {
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

enum NativeRoverAiThermalState { nominal, fair, serious, critical, unknown }

class NativeRoverAiFeatureCapability {
  NativeRoverAiFeatureCapability({
    required this.availability,
    this.provider,
    this.modelName,
    this.modelVersion,
    this.reason,
  });

  NativeRoverAiAvailability availability;
  String? provider;
  String? modelName;
  String? modelVersion;
  String? reason;
}

class NativeRoverAiCapabilitySnapshot {
  NativeRoverAiCapabilitySnapshot({
    required this.apiLevel,
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
    required this.checkedAtEpochMilliseconds,
    this.unavailabilityReason,
  });

  int apiLevel;
  String manufacturer;
  String model;
  NativeRoverAiFeatureCapability prompt;
  NativeRoverAiFeatureCapability imageDescription;
  NativeRoverAiFeatureCapability ocr;
  NativeRoverAiFeatureCapability objectDetection;
  NativeRoverAiFeatureCapability speechRecognition;
  NativeRoverAiFeatureCapability localCuration;
  NativeRoverAiFeatureCapability offlineIntelligence;
  bool foregroundEligible;
  bool batterySaverEnabled;
  NativeRoverAiThermalState thermalState;
  bool memoryPressure;
  bool quotaLimited;
  int checkedAtEpochMilliseconds;
  String? unavailabilityReason;
}

class NativeRoverAiRequest {
  NativeRoverAiRequest({
    required this.correlationId,
    required this.operation,
    required this.timeoutMilliseconds,
    this.localImagePath,
  });

  String correlationId;
  NativeRoverAiOperation operation;
  int timeoutMilliseconds;
  String? localImagePath;
}

class NativeRoverAiResult {
  NativeRoverAiResult({
    required this.correlationId,
    required this.status,
    required this.provider,
    required this.operation,
    required this.durationMilliseconds,
    required this.fallbackUsed,
    required this.diagnosticCode,
    required this.candidateLabels,
    required this.evidenceIds,
    required this.policyDecisions,
    this.text,
    this.confidence,
  });

  String correlationId;
  NativeRoverAiResultStatus status;
  String provider;
  NativeRoverAiOperation operation;
  int durationMilliseconds;
  bool fallbackUsed;
  String diagnosticCode;
  String? text;
  List<String> candidateLabels;
  double? confidence;
  List<String> evidenceIds;
  List<String> policyDecisions;
}

@HostApi()
abstract class RoverOnDeviceAiHostApi {
  String getBridgeVersion();

  @async
  NativeRoverAiCapabilitySnapshot getCapabilities();

  @async
  NativeRoverAiResult execute(NativeRoverAiRequest request);

  void cancel(String correlationId);
}
