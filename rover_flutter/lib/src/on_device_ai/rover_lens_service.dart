import 'rover_ai_models.dart';
import 'rover_on_device_ai_coordinator.dart';

class RoverLensCandidate {
  const RoverLensCandidate({required this.id, required this.name});

  final String id;
  final String name;
}

class RoverLensAnalysis {
  const RoverLensAnalysis({
    required this.status,
    required this.message,
    required this.diagnosticCode,
    this.recognizedText,
    this.matchedCandidateId,
  });

  final RoverAiResultStatus status;
  final String message;
  final String diagnosticCode;
  final String? recognizedText;
  final String? matchedCandidateId;

  bool get succeeded => status == RoverAiResultStatus.success;
}

class RoverLensService {
  RoverLensService(this._coordinator);

  final RoverOnDeviceAiCoordinator _coordinator;
  int _sequence = 0;
  String? _activeCorrelationId;

  bool get enabled => _coordinator.isOperationEnabled(RoverAiOperation.lensOcr);

  Future<RoverLensAnalysis> recognizeText({
    required String localImagePath,
    required List<RoverLensCandidate> nearbyCandidates,
  }) async {
    final correlationId =
        'lens-ocr-${DateTime.now().microsecondsSinceEpoch}-${_sequence++}';
    _activeCorrelationId = correlationId;
    final result = await _coordinator.execute(
      RoverAiRequest(
        operation: RoverAiOperation.lensOcr,
        timeout: const Duration(seconds: 15),
        context: RoverAiRequestContext(
          correlationId: correlationId,
          requestedAtUtc: DateTime.now().toUtc(),
          locale: 'en-CA',
          userIntent: 'Read visible text from an intentional camera capture.',
          privacyPolicy: const RoverAiPrivacyPolicy(
            cameraPermissionGranted: true,
            foregroundEligible: true,
          ),
          localImagePath: localImagePath,
        ),
      ),
    );
    if (_activeCorrelationId == correlationId) {
      _activeCorrelationId = null;
    }

    final text = switch (result.payload) {
      RoverAiTextPayload(:final text) when text.trim().isNotEmpty =>
        text.trim(),
      _ => null,
    };
    if (result.status == RoverAiResultStatus.success && text != null) {
      final matchedCandidateId = _matchCandidate(text, nearbyCandidates);
      return RoverLensAnalysis(
        status: result.status,
        message: matchedCandidateId == null
            ? 'Text found. Rover has not verified a nearby place match.'
            : 'Text found and matched to a verified nearby place.',
        diagnosticCode: result.diagnosticCode,
        recognizedText: text,
        matchedCandidateId: matchedCandidateId,
      );
    }
    if (result.status == RoverAiResultStatus.success) {
      return RoverLensAnalysis(
        status: result.status,
        message: 'No readable text was found. Move closer and hold steady.',
        diagnosticCode: result.diagnosticCode,
      );
    }
    return RoverLensAnalysis(
      status: result.status,
      message: _messageFor(result),
      diagnosticCode: result.diagnosticCode,
    );
  }

  Future<void> cancel() async {
    final correlationId = _activeCorrelationId;
    _activeCorrelationId = null;
    if (correlationId != null) {
      await _coordinator.cancel(correlationId);
    }
  }

  static String? _matchCandidate(
    String recognizedText,
    List<RoverLensCandidate> candidates,
  ) {
    final normalizedText = _normalizeForMatch(recognizedText);
    final matches = candidates.where((candidate) {
      final name = _normalizeForMatch(candidate.name);
      final words = name.split(' ');
      final distinctive = words.length >= 2
          ? name.length >= 4
          : name.length >= 8;
      return distinctive && ' $normalizedText '.contains(' $name ');
    }).toList()..sort((a, b) => b.name.length.compareTo(a.name.length));
    return matches.firstOrNull?.id;
  }

  static String _normalizeForMatch(String value) => value
      .toLowerCase()
      .replaceAll(RegExp('[^a-z0-9]+'), ' ')
      .trim()
      .replaceAll(RegExp(' +'), ' ');

  static String _messageFor(RoverAiResult<RoverAiPayload> result) {
    return switch (result.diagnosticCode) {
      'phase13_disabled' || 'operation_disabled' =>
        'On-device text recognition is not enabled for this build.',
      'capability_unavailable' =>
        'On-device text recognition is unavailable on this device.',
      'device_pressure' =>
        'The device is busy or warm. Try text recognition again shortly.',
      'cancelled' ||
      'native_operation_cancelled' => 'Text recognition was cancelled.',
      _ => 'Rover could not read this image. Try again.',
    };
  }
}
