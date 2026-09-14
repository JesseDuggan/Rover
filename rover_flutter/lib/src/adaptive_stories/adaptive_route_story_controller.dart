// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../active_roam/active_roam_session.dart';
import '../api/adaptive_route_story_models.dart';
import '../api/problem_details.dart';
import '../api/walk_repository.dart';
import '../diagnostics/field_diagnostics.dart';
import '../voice/rover_voice_controller.dart';
import 'adaptive_route_story_device_cache.dart';
import 'adaptive_route_story_diagnostics.dart';
import 'rover_phase16_flags.dart';

class AdaptiveRouteStoryController extends ChangeNotifier {
  AdaptiveRouteStoryController({
    required AdaptiveRouteStoryRepository repository,
    RoverPhase16Flags? flags,
    AdaptiveRouteStoryDeviceCache? deviceCache,
  }) : _repository = repository,
       _flags = flags ?? RoverPhase16Flags.fromEnvironment(),
       _deviceCache = deviceCache ?? AdaptiveRouteStoryDeviceCache.instance;

  final AdaptiveRouteStoryRepository _repository;
  final RoverPhase16Flags _flags;
  final AdaptiveRouteStoryDeviceCache _deviceCache;

  AdaptiveRouteStoryPackState? _packState;
  AdaptiveRouteStorySelection? _currentSelection;
  String? _errorMessage;
  bool _syncInFlight = false;
  bool _playbackInFlight = false;
  bool _usingOfflinePack = false;
  int? _routeRevision;
  String? _walkSessionId;
  DateTime? _lastStatusCheckUtc;
  DateTime? _lastSelectionCheckUtc;
  final Set<String> _prefetchedStoryIds = {};
  final Set<String> _completedStoryIds = {};
  final Set<String> _completedPlaces = {};
  double? _lastSelectionProgressMeters;
  Timer? _pollTimer;
  bool _disposed = false;

  void startPolling({
    required RoamSession Function() session,
    required RoverVoiceController voiceController,
    required bool Function() isForeground,
  }) {
    _pollTimer?.cancel();
    if (!enabled || _disposed) return;
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!isForeground()) return;
      final current = session();
      if (current.status == RoamSessionStatus.completed ||
          current.status == RoamSessionStatus.ended) {
        return;
      }
      unawaited(syncWithSession(current, voiceController));
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _pollTimer?.cancel();
    super.dispose();
  }

  bool get enabled => _flags.enabled;
  bool get isBusy => _syncInFlight || _playbackInFlight;
  AdaptiveRouteStoryPackState? get packState => _packState;
  AdaptiveRouteStoryPack? get pack => _packState?.pack;
  AdaptiveRouteStorySelection? get currentSelection => _currentSelection;
  String? get errorMessage => _errorMessage ?? _packState?.error;
  bool get usingOfflinePack => _usingOfflinePack;
  int get queuedEventCount => _deviceCache.queuedEventCount;
  String get researchStatus {
    final currentPack = pack;
    if (currentPack == null && readinessLabel == 'failed') {
      return errorMessage ?? 'Route story generation failed.';
    }
    if (currentPack == null) return 'Local research: waiting for story pack.';
    final count = currentPack.stories
        .where(
          (story) => story.sources.any(
            (source) => source.providerName == 'OnlineResearch',
          ),
        )
        .length;
    final details = currentPack.warnings
        .where(
          (warning) =>
              warning.toLowerCase().contains('local research') ||
              warning.toLowerCase().contains('local online research'),
        )
        .join(' ');
    if (count > 0) return 'Local research: $count stories in this pack.';
    if (details.isNotEmpty) return details;
    return _usingOfflinePack
        ? 'Local research: online-only stories are not in this download.'
        : 'Local research: no researched stories in this pack; outcome not reported. Refresh to check.';
  }

  String get readinessLabel => !enabled
      ? 'disabled'
      : _usingOfflinePack
      ? 'offline'
      : _packState?.status.toLowerCase() ?? 'pending';
  bool get offlineEligible {
    final stories = pack?.stories ?? const <AdaptiveRouteStory>[];
    return stories.isNotEmpty &&
        stories.every(
          (story) =>
              story.sources.isNotEmpty &&
              story.sources.every((source) => source.canCache),
        );
  }

  Future<void> syncWithSession(
    RoamSession session,
    RoverVoiceController voiceController,
  ) async {
    if (_disposed ||
        !enabled ||
        session.apiWalkSessionId == null ||
        session.roam.stops.isEmpty ||
        _syncInFlight ||
        _playbackInFlight) {
      return;
    }

    if (_routeRevision != session.routeRevision ||
        _walkSessionId != session.apiWalkSessionId) {
      if (_walkSessionId != session.apiWalkSessionId) {
        _completedStoryIds.clear();
        _completedPlaces.clear();
      }
      _walkSessionId = session.apiWalkSessionId;
      _routeRevision = session.routeRevision;
      _packState = null;
      _currentSelection = null;
      _lastSelectionProgressMeters = null;
      _lastSelectionCheckUtc = null;
      _prefetchedStoryIds.clear();
      _lastStatusCheckUtc = null;
      _notify();
    }

    final now = DateTime.now().toUtc();
    final statusDue =
        _packState?.pack == null &&
        (_lastStatusCheckUtc == null ||
            now.difference(_lastStatusCheckUtc!) >= const Duration(seconds: 4));
    final progressMeters = _routeProgressMeters(session);
    final selectionDue =
        session.status == RoamSessionStatus.active &&
        _packState?.pack != null &&
        (_lastSelectionProgressMeters == null ||
            (progressMeters - _lastSelectionProgressMeters!).abs() >= 20 ||
            _lastSelectionCheckUtc == null ||
            now.difference(_lastSelectionCheckUtc!) >=
                const Duration(seconds: 5));
    final interruptedStory = _currentSelection;
    if (interruptedStory != null &&
        voiceController.hasAutomaticallyResumableAdaptiveStory(
          interruptedStory.story.storyId,
        ) &&
        _safeForContextualStory(session)) {
      await playCurrent(session, voiceController, userRequested: false);
      return;
    }
    if (!statusDue && !selectionDue) {
      return;
    }

    _syncInFlight = true;
    _notify();
    try {
      await _flushQueuedEvents();
      if (statusDue) {
        final statusStarted = DateTime.now();
        _lastStatusCheckUtc = now;
        _packState = await _repository.getRouteStoryPackStatus(
          session.apiWalkSessionId!,
        );
        _usingOfflinePack = false;
        final cached = await _deviceCache.store(_packState!);
        FieldDiagnostics.instance.record(
          'route-story',
          'pack status=${_packState!.status} '
              'stories=${_packState!.pack?.stories.length ?? 0} '
              'deviceCached=$cached '
              'research=$researchStatus '
              'latencyMs=${DateTime.now().difference(statusStarted).inMilliseconds}',
        );
      }
      final upcoming =
          (_packState?.pack?.stories ?? const <AdaptiveRouteStory>[])
              .where(
                (story) =>
                    story.playbackWindowEnd >= progressMeters &&
                    !(_packState?.heardStoryIds.contains(story.storyId) ??
                        false),
              )
              .toList()
            ..sort(
              (a, b) => a.opensAtRouteMeters.compareTo(b.opensAtRouteMeters),
            );
      for (final story in upcoming.take(2)) {
        if (_prefetchedStoryIds.add(story.storyId)) {
          unawaited(voiceController.prefetchAdaptiveRouteStory(story));
        }
      }
      if (selectionDue ||
          (session.status == RoamSessionStatus.active &&
              _packState?.pack != null &&
              _lastSelectionProgressMeters == null)) {
        await _selectAndPlay(session, voiceController, progressMeters);
      }
      _errorMessage = null;
    } on RoverApiException catch (error) {
      if (_isConnectivityError(error)) {
        final cached = await _deviceCache.get(
          session.apiWalkSessionId!,
          session.routeRevision,
        );
        if (cached != null) {
          _packState = cached;
          _usingOfflinePack = true;
          _errorMessage = 'Using downloaded route stories while offline.';
          FieldDiagnostics.instance.record(
            'route-story',
            'offline cache hit routeRevision=${session.routeRevision} '
                'queuedEvents=${_deviceCache.queuedEventCount}',
          );
          if (session.status == RoamSessionStatus.active) {
            await _selectAndPlay(session, voiceController, progressMeters);
          }
        } else {
          _errorMessage = error.message;
        }
      } else {
        _errorMessage = error.message;
      }
      FieldDiagnostics.instance.record(
        'route-story',
        'Phase 16 sync deferred: ${error.message}',
      );
    } finally {
      _syncInFlight = false;
      _notify();
    }
  }

  Future<void> refreshPack(RoamSession session) async {
    final walkSessionId = session.apiWalkSessionId;
    if (!enabled || walkSessionId == null || _syncInFlight) return;
    _syncInFlight = true;
    _notify();
    try {
      _packState = await _repository.generateRouteStoryPack(
        walkSessionId,
        const GenerateRouteStoryPackRequest(forceRefresh: true),
      );
      _routeRevision = session.routeRevision;
      _usingOfflinePack = false;
      await _deviceCache.store(_packState!);
      _currentSelection = null;
      _lastSelectionProgressMeters = null;
      _errorMessage = null;
    } on RoverApiException catch (error) {
      _errorMessage = error.message;
    } finally {
      _syncInFlight = false;
      _notify();
    }
  }

  Future<void> playCurrent(
    RoamSession session,
    RoverVoiceController voiceController, {
    bool userRequested = true,
  }) async {
    final selection = _currentSelection;
    final walkSessionId = session.apiWalkSessionId;
    if (selection == null || walkSessionId == null || _playbackInFlight) {
      return;
    }
    _playbackInFlight = true;
    _notify();
    try {
      if (!voiceController.canPlayAdaptiveRouteStory(
        selection,
        session,
        userRequested: userRequested,
      )) {
        if (userRequested) {
          _errorMessage = 'Answer shown below. Audio is waiting for enough time before the next turn or arrival.';
        }
        return;
      }
      _errorMessage = null;
      FieldDiagnostics.instance.record(
        'route-story',
        'playback start trigger=${userRequested ? "manual" : "automatic"} '
            'story=${selection.story.storyId} intent=${selection.story.intent}',
      );
      await _record(walkSessionId, selection.story.storyId, 'Started');
      final played = await voiceController.playAdaptiveRouteStory(
        selection,
        session,
        userRequested: userRequested,
      );
      if (played) {
        // Remember audible completion before a slow or failed acknowledgement can permit a replay.
        _completedStoryIds.add(selection.story.storyId);
        if (selection.story.placeId.isNotEmpty) {
          _completedPlaces.add(
            '${selection.story.placeId}|${selection.story.intent}',
          );
        }
        _currentSelection = null;
        await _record(walkSessionId, selection.story.storyId, 'Completed');
        FieldDiagnostics.instance.record(
          'route-story',
          'playback completed intent=${selection.story.intent} '
              'duration=${selection.variant.estimatedDurationSeconds}s '
              'offline=$_usingOfflinePack',
        );
        try {
          _packState = await _repository.getRouteStoryPackStatus(walkSessionId);
          await _deviceCache.store(_packState!);
        } on RoverApiException catch (error) {
          if (!_isConnectivityError(error)) rethrow;
          _packState = await _deviceCache.get(
            walkSessionId,
            session.routeRevision,
          );
          _usingOfflinePack = _packState != null;
        }
        _currentSelection = null;
      }
    } on RoverApiException catch (error) {
      _errorMessage = error.message;
    } finally {
      _playbackInFlight = false;
      _notify();
    }
  }

  Future<void> pauseCurrent(
    RoamSession session,
    RoverVoiceController voiceController,
  ) async {
    final selection = _currentSelection;
    if (selection == null) return;
    await voiceController.pauseAdaptiveRouteStory();
    await _record(session.apiWalkSessionId, selection.story.storyId, 'Paused');
    _notify();
  }

  Future<void> resumeCurrent(
    RoamSession session,
    RoverVoiceController voiceController,
  ) async {
    final selection = _currentSelection;
    if (selection == null) return;
    await _record(session.apiWalkSessionId, selection.story.storyId, 'Resumed');
    await playCurrent(session, voiceController);
  }

  Future<void> skipCurrent(RoamSession session) async {
    final selection = _currentSelection;
    if (selection == null) return;
    await _record(session.apiWalkSessionId, selection.story.storyId, 'Skipped');
    FieldDiagnostics.instance.record(
      'route-story',
      'playback skipped intent=${selection.story.intent} '
          'offline=$_usingOfflinePack',
    );
    await _refreshStateAfterEvent(session);
    _currentSelection = null;
    _notify();
  }

  Future<void> tellMore(
    RoamSession session,
    RoverVoiceController voiceController,
  ) async {
    final selection = _currentSelection;
    if (selection == null) return;
    final variants = selection.story.variants;
    final deeper =
        variants.where((variant) => variant.length == 'Deep').firstOrNull ??
        variants.where((variant) => variant.length == 'Standard').firstOrNull;
    if (deeper == null) return;
    _currentSelection = AdaptiveRouteStorySelection(
      story: selection.story,
      variant: deeper,
      reason: 'User requested a deeper grounded variant.',
    );
    await _record(
      session.apiWalkSessionId,
      selection.story.storyId,
      'TellMore',
    );
    await playCurrent(session, voiceController);
  }

  Future<void> saveCurrent(RoamSession session) async {
    final selection = _currentSelection;
    if (selection == null) return;
    await _record(session.apiWalkSessionId, selection.story.storyId, 'Saved');
    await _refreshStateAfterEvent(session);
    _notify();
  }

  Future<void> recordSourcesViewed(RoamSession session) async {
    final selection = _currentSelection;
    if (selection == null) return;
    await _record(
      session.apiWalkSessionId,
      selection.story.storyId,
      'SourcesViewed',
    );
  }

  Future<void> askAboutRoute(
    RoamSession session,
    RoverVoiceController voiceController,
    String question,
  ) async {
    final walkSessionId = session.apiWalkSessionId;
    final trimmed = question.trim();
    if (walkSessionId == null || trimmed.isEmpty || _playbackInFlight) return;
    _currentSelection = null;
    _errorMessage = null;
    _playbackInFlight = true;
    _notify();
    try {
      AdaptiveRouteStorySelection? selection;
      try {
        final answer = await _repository.askRouteStory(
          walkSessionId,
          RouteStoryQuestionRequest(
            question: trimmed,
            routeProgressMeters: _routeProgressMeters(session),
            secondsUntilNextManeuver: _secondsUntilNextManeuver(session),
          ),
        );
        selection = answer.selection;
        if (selection == null) {
          _errorMessage =
              answer.unavailableReason ??
              'No grounded route story was available.';
        }
      } on RoverApiException catch (error) {
        if (!_isConnectivityError(error)) rethrow;
        _errorMessage = 'Route questions need a connection to match your question. Downloaded walking stories remain available.';
      }
      if (selection == null) {
        return;
      }
      _currentSelection = selection;
      FieldDiagnostics.instance.record(
        'route-story',
        'question matched intent=${selection.story.intent} '
            'length=${selection.variant.length} offline=$_usingOfflinePack',
      );
    } on RoverApiException catch (error) {
      _errorMessage = error.message;
      return;
    } finally {
      _playbackInFlight = false;
      _notify();
    }
    await playCurrent(session, voiceController);
  }

  Future<void> _selectAndPlay(
    RoamSession session,
    RoverVoiceController voiceController,
    double progressMeters,
  ) async {
    if (!_safeForContextualStory(session)) {
      FieldDiagnostics.instance.record(
        'route-story',
        'Automatic playback held: offRoute=${session.isOffRoute}; '
            'arrivalCandidate=${session.arrivalCandidate}; '
            'candidateStop=${session.arrivalCandidateStopId ?? "none"}; '
            'nearRecentArrival=${session.isNearRecentNarrationStop}; '
            'nextStopMeters=${session.distanceToNextStopMeters}; '
            'nextTurnMeters=${session.storyNavigationGuidance?.distanceMeters}',
      );
      _lastSelectionProgressMeters = null;
      return;
    }
    _lastSelectionProgressMeters = progressMeters;
    _lastSelectionCheckUtc = DateTime.now().toUtc();
    final request = NextRouteStoryRequest(
      routeProgressMeters: progressMeters,
      secondsUntilNextManeuver: _secondsUntilNextManeuver(session),
      preferredLength: 'Standard',
      excludedStoryIds: {
        ..._completedStoryIds,
        ...?packState?.heardStoryIds,
        for (final story in pack?.stories ?? const <AdaptiveRouteStory>[])
          if (_completedPlaces.contains('${story.placeId}|${story.intent}'))
            story.storyId,
      }.toList(),
    );
    AdaptiveRouteStorySelection? selection;
    if (_usingOfflinePack) {
      selection = await _deviceCache.select(
        session.apiWalkSessionId!,
        session.routeRevision,
        request,
      );
    } else {
      try {
        selection = await _repository.getNextRouteStory(
          session.apiWalkSessionId!,
          request,
        );
      } on RoverApiException catch (error) {
        if (!_isConnectivityError(error)) rethrow;
        selection = await _deviceCache.select(
          session.apiWalkSessionId!,
          session.routeRevision,
          request,
        );
        _usingOfflinePack = selection != null;
      }
    }
    if (selection == null) {
      FieldDiagnostics.instance.record(
        'route-story',
        'No eligible story at ${progressMeters.round()} m; '
            'stories=${pack?.stories.length ?? 0}; '
            'nextManeuverSeconds=${_secondsUntilNextManeuver(session)}',
      );
      return;
    }
    if (request.excludedStoryIds.contains(selection.story.storyId)) return;
    _currentSelection = selection;
    _notify();
    await playCurrent(session, voiceController, userRequested: false);
  }

  bool _safeForContextualStory(RoamSession session) {
    if (session.isOffRoute || session.arrivalCandidate) return false;
    if (session.arrivalCandidateStopId != null ||
        session.isNearRecentNarrationStop) {
      return false;
    }
    final distance = session.distanceToNextStopMeters;
    if (distance != null && distance <= session.storyArrivalBoundaryMeters) {
      return false;
    }
    return (session.storyNavigationGuidance?.distanceMeters ?? 9999) > 45;
  }

  static double _routeProgressMeters(RoamSession session) {
    final total = session.roam.routeManeuvers.fold<int>(
      0,
      (sum, maneuver) => sum + maneuver.distanceMeters,
    );
    final distance = total > 0
        ? total.toDouble()
        : session.roam.distanceMiles * 1609.344;
    return distance *
        ((session.routeProgressPercentage ?? session.progressPercentage ?? 0) /
            100);
  }

  static int? _secondsUntilNextManeuver(RoamSession session) {
    return session.storySecondsUntilInterruption;
  }

  Future<void> _record(
    String? walkSessionId,
    String storyId,
    String kind,
  ) async {
    if (walkSessionId == null) return;
    final request = RouteStoryPlaybackEventRequest(
      storyId: storyId,
      kind: kind,
      occurredUtc: DateTime.now().toUtc(),
    );
    try {
      await _repository.recordRouteStoryPlayback(walkSessionId, request);
      await _deviceCache.applyEvent(
        walkSessionId,
        _routeRevision ?? 0,
        request,
        queueForSync: false,
      );
    } on RoverApiException catch (error) {
      if (!_isConnectivityError(error)) rethrow;
      _usingOfflinePack = true;
      await _deviceCache.applyEvent(
        walkSessionId,
        _routeRevision ?? 0,
        request,
        queueForSync: true,
      );
      FieldDiagnostics.instance.record(
        'route-story',
        'playback event queued kind=$kind '
            'queuedEvents=${_deviceCache.queuedEventCount}',
      );
    }
  }

  Future<void> _flushQueuedEvents() => _deviceCache.flushEvents(
    (event) => _repository.recordRouteStoryPlayback(
      event.walkSessionId,
      event.request,
    ),
  );

  Future<void> _refreshStateAfterEvent(RoamSession session) async {
    final walkSessionId = session.apiWalkSessionId;
    if (walkSessionId == null || _packState == null) return;
    if (_usingOfflinePack) {
      _packState = await _deviceCache.get(walkSessionId, session.routeRevision);
      return;
    }
    try {
      _packState = await _repository.getRouteStoryPackStatus(walkSessionId);
      await _deviceCache.store(_packState!);
    } on RoverApiException catch (error) {
      if (!_isConnectivityError(error)) rethrow;
      _packState = await _deviceCache.get(walkSessionId, session.routeRevision);
      _usingOfflinePack = _packState != null;
    }
  }

  static bool _isConnectivityError(RoverApiException error) =>
      error is RoverApiConnectionException || error is RoverApiTimeoutException;

  void _notify() {
    if (_disposed) return;
    AdaptiveRouteStoryDiagnostics.instance.update(
      _packState,
      isOfflineEligible: offlineEligible,
      isDeviceCached: _deviceCache.packCount > 0,
      usingOfflinePack: _usingOfflinePack,
      queuedEventCount: _deviceCache.queuedEventCount,
      errorMessage: errorMessage,
    );
    if (!hasListeners) return;
    notifyListeners();
  }
}
