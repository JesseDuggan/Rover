import 'dart:async';

import 'package:flutter/foundation.dart';

import '../active_roam/active_roam_session.dart';
import '../diagnostics/field_diagnostics.dart';
import '../location/rover_location.dart';
import 'rover_curator.dart';
import 'rover_ai_guardian.dart';
import 'rover_ai_models.dart';
import 'rover_ai_provider.dart';
import 'rover_phase13_flags.dart';
import 'rover_scout.dart';

enum RoverStoryControlAction {
  none,
  tellMore,
  shortVersion,
  preferCategory,
  currentLocalInformation,
  preferSimilar,
  reduceWeather,
  skip,
  dismissCategory,
  quietTenMinutes,
  resumeStories,
}

class RoverStoryControlCommand {
  const RoverStoryControlCommand(this.action, {this.category});

  final RoverStoryControlAction action;
  final String? category;

  bool get isStoryControl => action != RoverStoryControlAction.none;
}

class RoverOnDeviceAiCoordinator implements Listenable {
  RoverOnDeviceAiCoordinator({
    required this.flags,
    required this.provider,
    RoverAiGuardian? guardian,
    FieldDiagnostics? diagnostics,
    this.maximumConcurrentOperations = 2,
    this.maximumOperationTimeout = const Duration(seconds: 15),
    this.storyControlsEnabled = const bool.fromEnvironment(
      'ROVER_PHASE15_ENABLED',
      defaultValue: false,
    ),
  }) : _guardian = guardian ?? RoverAiGuardian(flags),
       _diagnostics = diagnostics ?? FieldDiagnostics.instance;

  final RoverPhase13Flags flags;
  final int maximumConcurrentOperations;
  final Duration maximumOperationTimeout;
  final bool storyControlsEnabled;
  final RoverAiProvider provider;
  final RoverAiGuardian _guardian;
  final RoverScoutService _scout = const RoverScoutService();
  final RoverCuratorService _curator = const RoverCuratorService();
  final FieldDiagnostics _diagnostics;
  final _RoverAiChangeNotifier _changes = _RoverAiChangeNotifier();
  final Map<String, _RoverAiInFlightOperation> _inFlight = {};
  final Set<String> _previouslyNarratedContentIds = {};
  RoverSituationSnapshot? _lastSituationSnapshot;
  RoverCuratorDecision? _lastCurationDecision;

  int get inFlightCount => _inFlight.length;
  RoverSituationSnapshot? get lastSituationSnapshot => _lastSituationSnapshot;
  RoverCuratorDecision? get lastCurationDecision => _lastCurationDecision;
  bool get deterministicCurationEnabled => flags.enabled && flags.curatorLocal;
  bool get autonomousCurationSpeechEnabled => false;

  RoverStoryControlCommand interpretStoryControl(String input) {
    if (!storyControlsEnabled) {
      return const RoverStoryControlCommand(RoverStoryControlAction.none);
    }
    final text = input.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    if (text.isEmpty) {
      return const RoverStoryControlCommand(RoverStoryControlAction.none);
    }
    if (text.contains('quiet for ten minutes') ||
        text.contains('quiet for 10 minutes')) {
      return const RoverStoryControlCommand(
        RoverStoryControlAction.quietTenMinutes,
      );
    }
    if (text.contains('resume stories')) {
      return const RoverStoryControlCommand(
        RoverStoryControlAction.resumeStories,
      );
    }
    if (text.contains("don't tell me stories like") ||
        text.contains('do not tell me stories like')) {
      return const RoverStoryControlCommand(
        RoverStoryControlAction.dismissCategory,
      );
    }
    if (text.contains('tell me more stories like')) {
      return const RoverStoryControlCommand(
        RoverStoryControlAction.preferSimilar,
      );
    }
    if (text.contains('fewer weather updates')) {
      return const RoverStoryControlCommand(
        RoverStoryControlAction.reduceWeather,
        category: 'weather',
      );
    }
    if (text.contains('more history')) {
      return const RoverStoryControlCommand(
        RoverStoryControlAction.preferCategory,
        category: 'history',
      );
    }
    if (text.contains('what is happening around here today') ||
        text.contains("what's happening around here today")) {
      return const RoverStoryControlCommand(
        RoverStoryControlAction.currentLocalInformation,
      );
    }
    if (text.contains('short version')) {
      return const RoverStoryControlCommand(
        RoverStoryControlAction.shortVersion,
      );
    }
    if (text.startsWith('skip this')) {
      return const RoverStoryControlCommand(RoverStoryControlAction.skip);
    }
    if (text.contains('tell me more')) {
      return const RoverStoryControlCommand(RoverStoryControlAction.tellMore);
    }
    return const RoverStoryControlCommand(RoverStoryControlAction.none);
  }

  @override
  void addListener(VoidCallback listener) => _changes.addListener(listener);

  @override
  void removeListener(VoidCallback listener) =>
      _changes.removeListener(listener);

  bool isOperationEnabled(RoverAiOperation operation) =>
      flags.enables(operation);

  RoverSituationSnapshot? observeSituation({
    required RoamSession session,
    RoverLocationReading? reading,
    List<String> nearbyVerifiedPoiIds = const [],
    RoverConnectivityState? connectivityState,
    RoverOfflineCacheState? offlineCacheState,
    DateTime? capturedAtUtc,
  }) {
    if (!deterministicCurationEnabled) {
      return null;
    }
    final previousSummary = _lastSituationSnapshot?.diagnosticSummary;
    final snapshot = _scout.derive(
      session: session,
      reading: reading,
      previous: _lastSituationSnapshot,
      nearbyVerifiedPoiIds: nearbyVerifiedPoiIds,
      connectivityState:
          connectivityState ??
          _lastSituationSnapshot?.connectivityState ??
          RoverConnectivityState.unknown,
      offlineCacheState:
          offlineCacheState ??
          _lastSituationSnapshot?.offlineCacheState ??
          RoverOfflineCacheState.unknown,
      capturedAtUtc: capturedAtUtc,
    );
    _lastSituationSnapshot = snapshot;
    if (snapshot.diagnosticSummary != previousSummary) {
      _diagnostics.record('scout', snapshot.diagnosticSummary);
      _changes.notifyChanged();
    }
    return snapshot;
  }

  RoverCuratorDecision curate({
    required List<RoverCuratorStoryCandidate> candidates,
    required RoverCuratorPreferences preferences,
    RoverSituationSnapshot? situation,
    Set<String> previouslyNarratedContentIds = const {},
    DateTime? nowUtc,
  }) {
    if (!deterministicCurationEnabled) {
      return const RoverCuratorDecision(
        rankedCandidates: [],
        excludedCandidateCount: 0,
        diagnosticCode: 'curator_disabled',
        suppressionReason: 'Deterministic local curation is disabled.',
      );
    }
    final effectiveSituation = situation ?? _lastSituationSnapshot;
    if (effectiveSituation == null) {
      return const RoverCuratorDecision(
        rankedCandidates: [],
        excludedCandidateCount: 0,
        diagnosticCode: 'situation_unavailable',
        suppressionReason: 'A Scout situation snapshot is not available.',
      );
    }
    final narrated = <String>{
      ..._previouslyNarratedContentIds,
      ...previouslyNarratedContentIds,
    };
    final decision = _curator.rank(
      situation: effectiveSituation,
      candidates: candidates,
      preferences: preferences,
      previouslyNarratedContentIds: narrated,
      nowUtc: nowUtc,
    );
    _lastCurationDecision = decision;
    _diagnostics.record('curator', decision.diagnosticSummary);
    _changes.notifyChanged();
    return decision;
  }

  void markContentNarrated(Iterable<String> contentIds) {
    _previouslyNarratedContentIds.addAll(
      contentIds.where((id) => id.trim().isNotEmpty),
    );
  }

  Future<RoverAiCapabilitySnapshot> getCapabilitiesForDiagnostics() async {
    final snapshot = await provider.getCapabilities().timeout(
      maximumOperationTimeout,
    );
    _diagnostics.record(
      'on-device-ai',
      'capabilities checked; platform ${snapshot.platform}; '
          'foreground ${snapshot.foregroundEligible}; '
          'thermal ${snapshot.thermalState.name}',
    );
    return snapshot;
  }

  Future<String?> getBridgeVersionForDiagnostics() {
    final diagnosticsProvider = provider;
    if (diagnosticsProvider is RoverAiDiagnosticsProvider) {
      return (diagnosticsProvider as RoverAiDiagnosticsProvider)
          .getBridgeVersion();
    }
    return Future.value();
  }

  Future<RoverAiResult<RoverAiPayload>> execute(RoverAiRequest request) {
    final correlationId = request.context.correlationId;
    if (_inFlight.containsKey(correlationId)) {
      return Future.value(
        _result(
          request,
          status: RoverAiResultStatus.busy,
          diagnosticCode: 'duplicate_correlation',
        ),
      );
    }
    if (_inFlight.length >= maximumConcurrentOperations) {
      return Future.value(
        _result(
          request,
          status: RoverAiResultStatus.busy,
          diagnosticCode: 'operation_limit_reached',
        ),
      );
    }

    final inFlight = _RoverAiInFlightOperation();
    _inFlight[correlationId] = inFlight;
    unawaited(_run(request, inFlight));
    return inFlight.completer.future;
  }

  Future<void> cancel(String correlationId) async {
    final inFlight = _inFlight[correlationId];
    if (inFlight == null) {
      return;
    }
    inFlight.cancelled = true;
    if (!inFlight.completer.isCompleted && inFlight.request != null) {
      inFlight.completer.complete(
        _result(
          inFlight.request!,
          status: RoverAiResultStatus.cancelled,
          diagnosticCode: 'cancelled',
        ),
      );
    }
    await _cancelProvider(correlationId);
  }

  Future<void> _cancelProvider(String correlationId) async {
    try {
      await provider.cancel(correlationId).timeout(const Duration(seconds: 1));
    } catch (_) {
      // Native cancellation failure must not prevent a bounded fallback result.
    }
  }

  Future<void> dispose() async {
    final ids = _inFlight.keys.toList(growable: false);
    await Future.wait(ids.map(cancel));
    _changes.dispose();
  }

  Future<void> _run(
    RoverAiRequest request,
    _RoverAiInFlightOperation inFlight,
  ) async {
    inFlight.request = request;
    final stopwatch = Stopwatch()..start();
    final timeout = request.timeout < maximumOperationTimeout
        ? request.timeout
        : maximumOperationTimeout;
    RoverAiResult<RoverAiPayload> result;
    try {
      final preflight = _guardian.evaluate(request);
      if (!preflight.allowed) {
        result = _decisionResult(request, preflight);
      } else {
        final capabilities = await provider.getCapabilities().timeout(timeout);
        final decision = _guardian.evaluate(
          request,
          capabilities: capabilities,
        );
        if (inFlight.cancelled) {
          result = _result(
            request,
            status: RoverAiResultStatus.cancelled,
            diagnosticCode: 'cancelled',
          );
        } else if (!decision.allowed) {
          result = _decisionResult(request, decision);
        } else {
          final remaining = timeout - stopwatch.elapsed;
          if (remaining <= Duration.zero)
            throw TimeoutException('Operation budget exhausted');
          result = await provider.execute(request).timeout(remaining);
        }
      }
    } on TimeoutException {
      await _cancelProvider(request.context.correlationId);
      result = _result(
        request,
        status: RoverAiResultStatus.timeout,
        diagnosticCode: 'operation_timeout',
      );
    } catch (_) {
      result = _result(
        request,
        status: RoverAiResultStatus.error,
        diagnosticCode: 'provider_error',
      );
    } finally {
      stopwatch.stop();
      _inFlight.remove(request.context.correlationId);
    }

    if (inFlight.cancelled) {
      result = _result(
        request,
        status: RoverAiResultStatus.cancelled,
        diagnosticCode: 'cancelled',
      );
    }
    result = result.withDuration(stopwatch.elapsed);
    _record(result);
    if (!inFlight.completer.isCompleted) {
      inFlight.completer.complete(result);
    }
  }

  RoverAiResult<RoverAiPayload> _decisionResult(
    RoverAiRequest request,
    RoverAiGuardianDecision decision,
  ) {
    return _result(
      request,
      status: decision.status,
      diagnosticCode: decision.diagnosticCode,
      policyDecisions: decision.policyDecisions,
    );
  }

  RoverAiResult<RoverAiPayload> _result(
    RoverAiRequest request, {
    required RoverAiResultStatus status,
    required String diagnosticCode,
    List<String> policyDecisions = const [],
  }) {
    return RoverAiResult<RoverAiPayload>(
      correlationId: request.context.correlationId,
      status: status,
      provider: provider.name,
      operation: request.operation,
      processingLocation: RoverAiProcessingLocation.none,
      verificationState: RoverAiVerificationState.notApplicable,
      duration: Duration.zero,
      fallbackUsed: true,
      diagnosticCode: diagnosticCode,
      policyDecisions: policyDecisions,
    );
  }

  void _record(RoverAiResult<RoverAiPayload> result) {
    _diagnostics.record(
      'on-device-ai',
      '${result.operation.name} ${result.status.name}; '
          'provider ${result.provider}; '
          '${result.duration.inMilliseconds} ms; '
          'fallback ${result.fallbackUsed}; '
          'code ${result.diagnosticCode}',
    );
  }
}

class _RoverAiInFlightOperation {
  final completer = Completer<RoverAiResult<RoverAiPayload>>();
  RoverAiRequest? request;
  bool cancelled = false;
}

class _RoverAiChangeNotifier extends ChangeNotifier {
  void notifyChanged() => notifyListeners();
}
