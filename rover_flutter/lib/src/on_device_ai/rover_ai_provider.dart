import 'rover_ai_models.dart';

abstract interface class RoverAiProvider {
  String get name;

  Future<RoverAiCapabilitySnapshot> getCapabilities();

  Future<RoverAiResult<RoverAiPayload>> execute(RoverAiRequest request);

  Future<void> cancel(String correlationId);
}

abstract interface class RoverAiDiagnosticsProvider {
  Future<String?> getBridgeVersion();
}

class DisabledRoverAiProvider
    implements RoverAiProvider, RoverAiDiagnosticsProvider {
  const DisabledRoverAiProvider();

  @override
  String get name => 'disabled';

  @override
  Future<RoverAiCapabilitySnapshot> getCapabilities() async {
    return RoverAiCapabilitySnapshot.unsupported(
      checkedAtUtc: DateTime.now().toUtc(),
    );
  }

  @override
  Future<String?> getBridgeVersion() async => null;

  @override
  Future<RoverAiResult<RoverAiPayload>> execute(RoverAiRequest request) async {
    return RoverAiResult<RoverAiPayload>(
      correlationId: request.context.correlationId,
      status: RoverAiResultStatus.unavailable,
      provider: name,
      operation: request.operation,
      processingLocation: RoverAiProcessingLocation.none,
      verificationState: RoverAiVerificationState.notApplicable,
      duration: Duration.zero,
      fallbackUsed: true,
      diagnosticCode: 'provider_disabled',
    );
  }

  @override
  Future<void> cancel(String correlationId) async {}
}
