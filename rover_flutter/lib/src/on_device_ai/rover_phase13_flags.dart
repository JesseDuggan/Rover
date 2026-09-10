import 'rover_ai_models.dart';

class RoverPhase13Flags {
  const RoverPhase13Flags({
    this.enabled = false,
    this.onDevicePrompt = false,
    this.lensOcr = false,
    this.lensDescription = false,
    this.listenerLocalSpeech = false,
    this.curatorLocal = false,
    this.offlineIntelligence = false,
    this.cloudFallback = false,
    this.cameraUpload = false,
  });

  final bool enabled;
  final bool onDevicePrompt;
  final bool lensOcr;
  final bool lensDescription;
  final bool listenerLocalSpeech;
  final bool curatorLocal;
  final bool offlineIntelligence;
  final bool cloudFallback;
  final bool cameraUpload;

  factory RoverPhase13Flags.fromEnvironment() {
    return const RoverPhase13Flags(
      enabled: bool.fromEnvironment('ROVER_PHASE13_ENABLED'),
      onDevicePrompt: bool.fromEnvironment('ROVER_AI_ON_DEVICE_PROMPT'),
      lensOcr: bool.fromEnvironment('ROVER_AI_LENS_OCR'),
      lensDescription: bool.fromEnvironment('ROVER_AI_LENS_DESCRIPTION'),
      listenerLocalSpeech: bool.fromEnvironment(
        'ROVER_AI_LISTENER_LOCAL_SPEECH',
      ),
      curatorLocal: bool.fromEnvironment('ROVER_AI_CURATOR_LOCAL'),
      offlineIntelligence: bool.fromEnvironment('ROVER_AI_OFFLINE'),
      cloudFallback: bool.fromEnvironment('ROVER_AI_CLOUD_FALLBACK'),
      cameraUpload: bool.fromEnvironment('ROVER_AI_CAMERA_UPLOAD'),
    );
  }

  bool enables(RoverAiOperation operation) {
    if (!enabled) {
      return false;
    }
    return switch (operation) {
      RoverAiOperation.onDevicePrompt => onDevicePrompt,
      RoverAiOperation.lensOcr => lensOcr,
      RoverAiOperation.lensDescription => lensDescription,
      RoverAiOperation.listenerLocalSpeech => listenerLocalSpeech,
      RoverAiOperation.curatorLocal => curatorLocal,
      RoverAiOperation.offlineIntelligence => offlineIntelligence,
    };
  }
}
