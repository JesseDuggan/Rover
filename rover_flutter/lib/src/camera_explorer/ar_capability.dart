class RoverArCapability {
  const RoverArCapability({
    required this.mode,
    required this.arCoreSupported,
    required this.vpsAvailable,
    required this.fallbackReason,
  });

  final String mode;
  final bool arCoreSupported;
  final bool vpsAvailable;
  final String fallbackReason;

  static const cameraOverlayFallback = RoverArCapability(
    mode: 'Camera overlay',
    arCoreSupported: false,
    vpsAvailable: false,
    fallbackReason: 'ARCore Geospatial is deferred; Camera Explorer is active.',
  );
}

abstract class VisualRecognitionProvider {
  bool get enabled;

  Future<VisualRecognitionResult> identifyFromExplicitCapture({
    required List<CameraVisualCandidate> candidates,
  });
}

class DisabledVisualRecognitionProvider implements VisualRecognitionProvider {
  const DisabledVisualRecognitionProvider();

  @override
  bool get enabled => false;

  @override
  Future<VisualRecognitionResult> identifyFromExplicitCapture({
    required List<CameraVisualCandidate> candidates,
  }) async {
    return const VisualRecognitionResult(
      usedImage: false,
      message: 'Visual recognition is disabled. Rover is using location and heading instead.',
    );
  }
}

class CameraVisualCandidate {
  const CameraVisualCandidate({required this.id, required this.name});

  final String id;
  final String name;
}

class VisualRecognitionResult {
  const VisualRecognitionResult({
    required this.usedImage,
    required this.message,
    this.selectedCandidateId,
  });

  final bool usedImage;
  final String message;
  final String? selectedCandidateId;
}
