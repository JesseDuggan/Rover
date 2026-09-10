import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:rover/src/on_device_ai/rover_ai_models.dart';
import 'package:rover/src/on_device_ai/rover_ai_provider.dart';
import 'package:rover/src/on_device_ai/rover_on_device_ai_coordinator.dart';
import 'package:rover/src/on_device_ai/rover_phase13_flags.dart';

void main() {
  test(
    'diagnostics query bypasses feature flags without executing work',
    () async {
      final provider = _FakeRoverAiProvider();
      final coordinator = RoverOnDeviceAiCoordinator(
        flags: const RoverPhase13Flags(),
        provider: provider,
      );

      final capabilities = await coordinator.getCapabilitiesForDiagnostics();

      expect(capabilities.platform, 'android');
      expect(provider.capabilityCalls, 1);
      expect(provider.executeCalls, 0);
      await coordinator.dispose();
    },
  );

  test('disabled master flag never calls the provider', () async {
    final provider = _FakeRoverAiProvider();
    final coordinator = RoverOnDeviceAiCoordinator(
      flags: const RoverPhase13Flags(),
      provider: provider,
    );

    final result = await coordinator.execute(_request('disabled'));

    expect(result.status, RoverAiResultStatus.unavailable);
    expect(result.diagnosticCode, 'phase13_disabled');
    expect(provider.capabilityCalls, 0);
    expect(provider.executeCalls, 0);
    expect(
      coordinator.interpretStoryControl('Quiet for ten minutes.').action,
      RoverStoryControlAction.none,
    );
    await coordinator.dispose();
  });

  test('allowed bounded operation returns the provider result', () async {
    final provider = _FakeRoverAiProvider();
    final coordinator = _enabledCoordinator(provider);

    final result = await coordinator.execute(_request('success'));

    expect(result.status, RoverAiResultStatus.success);
    expect(result.provider, 'fake-device');
    expect(result.processingLocation, RoverAiProcessingLocation.device);
    expect(result.verificationState, RoverAiVerificationState.candidate);
    expect(provider.capabilityCalls, 1);
    expect(provider.executeCalls, 1);
    await coordinator.dispose();
  });

  test('operation timeout cancels provider work', () async {
    final provider = _FakeRoverAiProvider(holdOperations: true);
    final coordinator = _enabledCoordinator(provider);

    final result = await coordinator.execute(
      _request('timeout', timeout: const Duration(milliseconds: 5)),
    );

    expect(result.status, RoverAiResultStatus.timeout);
    expect(result.diagnosticCode, 'operation_timeout');
    expect(provider.cancelledIds, contains('timeout'));
    await coordinator.dispose();
  });

  test(
    'explicit cancellation completes promptly and cancels provider',
    () async {
      final provider = _FakeRoverAiProvider(holdOperations: true);
      final coordinator = _enabledCoordinator(provider);
      final pending = coordinator.execute(_request('cancel-me'));
      await Future<void>.delayed(Duration.zero);

      await coordinator.cancel('cancel-me');
      final result = await pending;

      expect(result.status, RoverAiResultStatus.cancelled);
      expect(provider.cancelledIds, contains('cancel-me'));
      await coordinator.dispose();
    },
  );

  test('concurrency ceiling rejects additional work as busy', () async {
    final provider = _FakeRoverAiProvider(holdOperations: true);
    final coordinator = RoverOnDeviceAiCoordinator(
      flags: const RoverPhase13Flags(enabled: true, onDevicePrompt: true),
      provider: provider,
      maximumConcurrentOperations: 1,
    );
    final first = coordinator.execute(_request('first'));
    await Future<void>.delayed(Duration.zero);

    final second = await coordinator.execute(_request('second'));

    expect(second.status, RoverAiResultStatus.busy);
    expect(second.diagnosticCode, 'operation_limit_reached');
    expect(provider.executeCalls, 1);
    await coordinator.cancel('first');
    expect((await first).status, RoverAiResultStatus.cancelled);
    await coordinator.dispose();
  });

  test('duplicate correlation identifiers are rejected', () async {
    final provider = _FakeRoverAiProvider(holdOperations: true);
    final coordinator = _enabledCoordinator(provider);
    final first = coordinator.execute(_request('same'));
    await Future<void>.delayed(Duration.zero);

    final duplicate = await coordinator.execute(_request('same'));

    expect(duplicate.status, RoverAiResultStatus.busy);
    expect(duplicate.diagnosticCode, 'duplicate_correlation');
    await coordinator.cancel('same');
    await first;
    await coordinator.dispose();
  });

  test('Phase 15 story commands are deterministic typed actions', () async {
    final provider = _FakeRoverAiProvider();
    final coordinator = RoverOnDeviceAiCoordinator(
      flags: const RoverPhase13Flags(enabled: true, onDevicePrompt: true),
      provider: provider,
      storyControlsEnabled: true,
    );

    expect(
      coordinator.interpretStoryControl('Quiet for ten minutes.').action,
      RoverStoryControlAction.quietTenMinutes,
    );
    expect(
      coordinator.interpretStoryControl('Resume stories.').action,
      RoverStoryControlAction.resumeStories,
    );
    expect(
      coordinator.interpretStoryControl('Tell me more.').action,
      RoverStoryControlAction.tellMore,
    );
    expect(
      coordinator
          .interpretStoryControl('Tell me more stories like that.')
          .action,
      RoverStoryControlAction.preferSimilar,
    );
    expect(
      coordinator.interpretStoryControl('Give me the short version.').action,
      RoverStoryControlAction.shortVersion,
    );
    expect(
      coordinator.interpretStoryControl('More history, please.').category,
      'history',
    );
    expect(
      coordinator
          .interpretStoryControl('What is happening around here today?')
          .action,
      RoverStoryControlAction.currentLocalInformation,
    );
    expect(
      coordinator.interpretStoryControl('Fewer weather updates.').action,
      RoverStoryControlAction.reduceWeather,
    );
    expect(
      coordinator.interpretStoryControl('Skip this.').action,
      RoverStoryControlAction.skip,
    );
    expect(
      coordinator
          .interpretStoryControl("Don't tell me stories like this again.")
          .action,
      RoverStoryControlAction.dismissCategory,
    );
    expect(
      coordinator.interpretStoryControl('Where is the next stop?').action,
      RoverStoryControlAction.none,
    );
    expect(provider.executeCalls, 0);
    await coordinator.dispose();
  });
}

RoverOnDeviceAiCoordinator _enabledCoordinator(RoverAiProvider provider) {
  return RoverOnDeviceAiCoordinator(
    flags: const RoverPhase13Flags(enabled: true, onDevicePrompt: true),
    provider: provider,
  );
}

RoverAiRequest _request(
  String correlationId, {
  Duration timeout = const Duration(seconds: 2),
}) {
  return RoverAiRequest(
    operation: RoverAiOperation.onDevicePrompt,
    timeout: timeout,
    context: RoverAiRequestContext(
      correlationId: correlationId,
      requestedAtUtc: DateTime.utc(2026, 8, 31),
      locale: 'en-CA',
      userIntent: 'Bounded test operation',
      privacyPolicy: const RoverAiPrivacyPolicy(),
    ),
  );
}

class _FakeRoverAiProvider implements RoverAiProvider {
  _FakeRoverAiProvider({this.holdOperations = false});

  final bool holdOperations;
  final Map<String, Completer<RoverAiResult<RoverAiPayload>>> _pending = {};
  final List<String> cancelledIds = [];
  int capabilityCalls = 0;
  int executeCalls = 0;

  @override
  String get name => 'fake-device';

  @override
  Future<void> cancel(String correlationId) async {
    cancelledIds.add(correlationId);
    final completer = _pending.remove(correlationId);
    if (completer != null && !completer.isCompleted) {
      completer.complete(_result(correlationId, RoverAiResultStatus.cancelled));
    }
  }

  @override
  Future<RoverAiResult<RoverAiPayload>> execute(RoverAiRequest request) {
    executeCalls++;
    if (!holdOperations) {
      return Future.value(
        _result(request.context.correlationId, RoverAiResultStatus.success),
      );
    }
    final completer = Completer<RoverAiResult<RoverAiPayload>>();
    _pending[request.context.correlationId] = completer;
    return completer.future;
  }

  @override
  Future<RoverAiCapabilitySnapshot> getCapabilities() async {
    capabilityCalls++;
    const available = RoverAiFeatureCapability(
      availability: RoverAiCapabilityAvailability.available,
      provider: 'fake-device',
    );
    return RoverAiCapabilitySnapshot(
      platform: 'android',
      apiLevel: 36,
      manufacturer: 'Test',
      model: 'Test',
      prompt: available,
      imageDescription: available,
      ocr: available,
      objectDetection: available,
      speechRecognition: available,
      localCuration: available,
      offlineIntelligence: available,
      foregroundEligible: true,
      batterySaverEnabled: false,
      thermalState: RoverAiThermalState.nominal,
      memoryPressure: false,
      quotaLimited: false,
      checkedAtUtc: DateTime.utc(2026, 8, 31),
    );
  }

  RoverAiResult<RoverAiPayload> _result(
    String correlationId,
    RoverAiResultStatus status,
  ) {
    return RoverAiResult<RoverAiPayload>(
      correlationId: correlationId,
      status: status,
      provider: name,
      operation: RoverAiOperation.onDevicePrompt,
      processingLocation: RoverAiProcessingLocation.device,
      verificationState: RoverAiVerificationState.candidate,
      duration: const Duration(milliseconds: 2),
      fallbackUsed: false,
      diagnosticCode: status == RoverAiResultStatus.success
          ? 'completed'
          : 'cancelled',
      payload: const RoverAiTextPayload('candidate text'),
    );
  }
}
