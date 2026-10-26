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
import 'story_walking_gap.dart';

class AdaptiveRouteStoryController extends ChangeNotifier {
  AdaptiveRouteStoryController({
    required AdaptiveRouteStoryRepository repository,
    RoverPhase16Flags? flags,
    AdaptiveRouteStoryDeviceCache? deviceCache,
    DateTime Function()? nowUtc,
  }) : _repository = repository,
       _flags = flags ?? RoverPhase16Flags.fromEnvironment(),
       _deviceCache = deviceCache ?? AdaptiveRouteStoryDeviceCache.instance,
       _nowUtc = nowUtc ?? (() => DateTime.now().toUtc());

  final AdaptiveRouteStoryRepository _repository;
  final RoverPhase16Flags _flags;
  final DateTime Function() _nowUtc;
  bool _replenishing = false;
  DateTime? _lastReplenishAt;
  double? _lastReplenishProgress;
  int _replenishAttempts = 0;
  bool _timeoutRetryUsed = false;
  bool get _researchTimedOut =>
      pack?.warnings.any(
        (warning) => warning.toLowerCase().contains('request timed out'),
      ) ??
      false;
  Set<String>? _refreshBaseline;
  String? _refreshMessage;
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
  final StoryWalkingGap _walkingGap = StoryWalkingGap();
  RoamSession? _latestSession;
  final Set<String> _deferredStoryIds = {};
  final Map<String, String> _localPlaybackStates = {};
  static const double _catchUpMeters = 150;
  double? _lastSelectionProgressMeters;
  Timer? _pollTimer;
  bool _disposed = false;
  bool _manualSelection = false;
  bool _pollInFlight = false;

  void startPolling({
    required RoamSession Function() session,
    required RoverVoiceController voiceController,
    required bool Function() isForeground,
  }) {
    _pollTimer?.cancel();
    if (_disposed) return;
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      if (_pollInFlight || !isForeground()) return;
      final current = session();
      if (current.status == RoamSessionStatus.completed ||
          current.status == RoamSessionStatus.ended) {
        return;
      }
      _pollInFlight = true;
      try {
        // Frame callbacks do not run with a locked screen. Keep navigation and
        // arrival narration synchronized from the active location session here.
        await voiceController.syncWithSession(current);
        // Story playback can last minutes. It must not hold the arrival pump.
        if (!_disposed) {
          unawaited(_syncStoriesFromPolling(session(), voiceController));
        }
      } catch (_) {
        if (!_disposed) {
          _errorMessage =
              'Walking updates could not finish. They will retry shortly.';
          notifyListeners();
        }
      } finally {
        _pollInFlight = false;
      }
    });
  }

  Future<void> _syncStoriesFromPolling(
    RoamSession session,
    RoverVoiceController voiceController,
  ) async {
    try {
      await syncWithSession(session, voiceController);
    } catch (_) {
      if (!_disposed) {
        _errorMessage =
            'Story playback could not finish. It will retry shortly.';
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _pollTimer?.cancel();
    super.dispose();
  }

  bool get enabled => _flags.enabled;
  bool get isBusy => _syncInFlight || _playbackInFlight;
  bool get isRefreshing =>
      _replenishing ||
      _refreshBaseline != null ||
      _packState?.status == 'Generating';
  String? get refreshMessage => _refreshMessage;

  Iterable<AdaptiveRouteStory> get _freshStories {
    final now = _nowUtc();
    if (!(pack?.expiresUtc.isAfter(now) ?? false)) return const [];
    return pack!.stories.where(
      (story) =>
          (story.expiresUtc?.isAfter(now) ?? true) &&
          story.sources.isNotEmpty &&
          story.variants.any((variant) => variant.narration.trim().isNotEmpty),
    );
  }

  int get unheardStoryCount =>
      _freshStories.where((story) => !_isExcluded(story)).length;

  String listeningStatus(RoamSession session) {
    if (pack != null &&
        _freshStories.isEmpty &&
        !_usingOfflinePack &&
        !_timeoutRetryUsed &&
        session.status == RoamSessionStatus.active &&
        !session.isOffRoute) {
      return isRefreshing
          ? 'Still researching stories...'
          : 'No verified stories yet. An automatic retry will follow shortly.';
    }
    if (_freshStories.isEmpty && _researchTimedOut) {
      if (isRefreshing) return 'Research took too long; retrying...';
      return _timeoutRetryUsed
          ? 'Research took too long. Please try refreshing.'
          : 'Research took too long. An automatic retry will follow shortly.';
    }
    if (isRefreshing) return 'Finding more stories...';
    if (_playbackInFlight) return 'Story playing';
    if (!_walkingGap.ready) {
      return 'Next story after ${_walkingGap.remainingMeters} m of walking';
    }
    if (_packState?.status == 'Failed') return 'Story research unavailable';
    if (pack == null) return 'Preparing stories...';
    final fresh = _freshStories.toList();
    if (fresh.isEmpty) return 'No verified stories available right now';
    final unheard = fresh.where((story) => !_isExcluded(story)).toList();
    if (unheard.isEmpty) {
      final completed = fresh.every(
        (story) =>
            _completedStoryIds.contains(story.storyId) ||
            (_packState?.playbackOutcomes.completedStoryIds.contains(
                  story.storyId,
                ) ??
                false),
      );
      return completed
          ? 'All current stories heard'
          : 'No unplayed stories remaining';
    }
    if (session.isOffRoute) {
      return unheard.any(
            (story) => session.isNearStoryAnchor(
              story.relevanceLatitude,
              story.relevanceLongitude,
            ),
          )
          ? '${unheard.length} unplayed stories available'
          : 'No unplayed stories nearby; saved stories remain available';
    }
    final progress = _routeProgressMeters(session);
    if (unheard.every((story) => story.playbackWindowStart > progress)) {
      return 'Stories ahead on your route';
    }
    if (unheard.every(
      (story) =>
          story.playbackWindowEnd < progress && !_canCatchUp(story, progress),
    )) {
      return 'Remaining stories are behind you; tap one to listen';
    }
    return '${unheard.length} unplayed ${unheard.length == 1 ? 'story' : 'stories'} available';
  }

  void _beginRefresh() {
    _refreshBaseline =
        pack?.stories.map((story) => story.storyId).toSet() ?? {};
    _refreshMessage = null;
    _notify();
  }

  void _acceptRefreshState(AdaptiveRouteStoryPackState result) {
    final previous = _packState;
    // A pending/failed response must not blank a still-valid collection.
    if (result.pack == null &&
        previous?.pack != null &&
        previous!.walkSessionId == result.walkSessionId &&
        previous.routeRevision == result.routeRevision &&
        previous.pack!.expiresUtc.isAfter(_nowUtc())) {
      result = AdaptiveRouteStoryPackState(
        walkSessionId: result.walkSessionId,
        routeRevision: result.routeRevision,
        status: result.status,
        updatedUtc: result.updatedUtc,
        pack: previous.pack,
        error: result.error,
        heardStoryIds: {
          ...previous.heardStoryIds,
          ...result.heardStoryIds,
        }.toList(),
        savedStoryIds: {
          ...previous.savedStoryIds,
          ...result.savedStoryIds,
        }.toList(),
        playbackOutcomes: previous.playbackOutcomes,
      );
    }
    _packState = result;
    final baseline = _refreshBaseline;
    if (baseline == null ||
        result.status == 'Generating' ||
        result.status == 'Pending') {
      return;
    }
    final failed =
        result.status == 'Failed' ||
        result.error != null ||
        (result.pack?.warnings.any(
              (warning) =>
                  warning.toLowerCase().contains('research failed') ||
                  warning.toLowerCase().contains('research is disabled') ||
                  warning.toLowerCase().contains('research is enabled but'),
            ) ??
            false);
    final added = _freshStories
        .where(
          (story) => !baseline.contains(story.storyId) && !_isExcluded(story),
        )
        .length;
    _refreshMessage = failed
        ? _researchUnavailableMessage
        : added == 0
        ? (_freshStories.isEmpty
              ? 'No verified stories found for this route yet. Try refreshing to research again.'
              : 'No new verified stories found. Your existing stories are still here.')
        : '$added new ${added == 1 ? 'story' : 'stories'} added';
    _refreshBaseline = null;
  }

  AdaptiveRouteStoryPackState? get packState => _packState;
  String get _researchUnavailableMessage => _freshStories.isEmpty
      ? 'Story research unavailable. Try again shortly.'
      : 'Story research unavailable. Your existing stories are still here.';
  AdaptiveRouteStoryPack? get pack => _packState?.pack;
  AdaptiveRouteStorySelection? get currentSelection => _currentSelection;
  bool get showingManualStory => _manualSelection && _currentSelection != null;
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
    _latestSession = session;
    _walkingGap.observe(session, _nowUtc());
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
        _walkingGap.reset();
        _localPlaybackStates.clear();
        _lastReplenishAt = null;
        _lastReplenishProgress = null;
        _replenishAttempts = 0;
        _timeoutRetryUsed = false;
      }
      _walkSessionId = session.apiWalkSessionId;
      _refreshBaseline = null;
      _refreshMessage = null;
      _routeRevision = session.routeRevision;
      _packState = null;
      _usingOfflinePack = false;
      _currentSelection = null;
      _manualSelection = false;
      _lastSelectionProgressMeters = null;
      _lastSelectionCheckUtc = null;
      _prefetchedStoryIds.clear();
      _deferredStoryIds.clear();
      _lastStatusCheckUtc = null;
      _notify();
    }

    final now = _nowUtc();
    final statusDue =
        (_packState?.pack == null ||
            _packState?.status == 'Generating' ||
            _packState?.status == 'Pending' ||
            _usingOfflinePack) &&
        (_lastStatusCheckUtc == null ||
            now.difference(_lastStatusCheckUtc!) >= const Duration(seconds: 4));
    final progressMeters = _routeProgressMeters(session);
    _rememberDeferredStories(progressMeters);
    final selectionDue =
        session.status == RoamSessionStatus.active &&
        !(_manualSelection && _currentSelection != null) &&
        _packState?.pack != null &&
        (_lastSelectionProgressMeters == null ||
            (progressMeters - _lastSelectionProgressMeters!).abs() >= 20 ||
            _lastSelectionCheckUtc == null ||
            now.difference(_lastSelectionCheckUtc!) >=
                const Duration(seconds: 5));
    final interruptedStory = _currentSelection;
    if (interruptedStory != null &&
        voiceController.hasInterruptedAdaptiveStory(
          interruptedStory.story.storyId,
        ) &&
        !voiceController.hasAutomaticallyResumableAdaptiveStory(
          interruptedStory.story.storyId,
        )) {
      return;
    }
    if (interruptedStory != null &&
        voiceController.hasAutomaticallyResumableAdaptiveStory(
          interruptedStory.story.storyId,
        ) &&
        // Playback windows govern starting stories, not finishing one already heard.
        !_isExcluded(interruptedStory.story) &&
        session.status == RoamSessionStatus.active &&
        (_safeForContextualStory(session) ||
            (session.isOffRoute &&
                session.isNearStoryAnchor(
                  interruptedStory.story.relevanceLatitude,
                  interruptedStory.story.relevanceLongitude,
                )))) {
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
        _acceptRefreshState(
          await _repository.getRouteStoryPackStatus(session.apiWalkSessionId!),
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
      if (!voiceController.storiesAreQuiet) {
        _maybeReplenish(session, progressMeters);
      }
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
        await _useOfflinePack(session);
        if (_packState?.pack != null) {
          _errorMessage = 'Connection interrupted. Your stories are still here; only downloaded stories can play offline.';
          FieldDiagnostics.instance.record(
            'route-story',
            'offline fallback routeRevision=${session.routeRevision} '
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
    if (!enabled || walkSessionId == null || isBusy || isRefreshing) {
      return;
    }
    _syncInFlight = true;
    _beginRefresh();
    try {
      final result = await _repository.generateRouteStoryPack(
        walkSessionId,
        const GenerateRouteStoryPackRequest(forceRefresh: true),
      );
      if (_disposed ||
          result.walkSessionId != walkSessionId ||
          result.routeRevision != session.routeRevision) {
        _refreshBaseline = null;
        return;
      }
      _acceptRefreshState(result);
      _routeRevision = session.routeRevision;
      _walkSessionId = walkSessionId;
      _usingOfflinePack = false;
      await _deviceCache.store(_packState!);
      _currentSelection = null;
      _lastSelectionProgressMeters = null;
      _errorMessage = null;
    } on RoverApiException catch (error) {
      _errorMessage = error.message;
      _refreshBaseline = null;
      _refreshMessage = _researchUnavailableMessage;
    } finally {
      // A manual attempt shares the automatic cooldown.
      _lastReplenishAt = _nowUtc();
      _lastReplenishProgress = _routeProgressMeters(session);
      _syncInFlight = false;
      _notify();
    }
  }

  bool selectStory(String storyId, RoamSession session) {
    if (_disposed ||
        isBusy ||
        _walkSessionId != session.apiWalkSessionId ||
        _routeRevision != session.routeRevision) {
      return false;
    }
    final matches = pack?.stories.where((story) => story.storyId == storyId);
    if (matches == null || matches.isEmpty) return false;
    final story = matches.first;
    final now = DateTime.now().toUtc();
    if (pack!.expiresUtc.isBefore(now) ||
        (story.expiresUtc?.isBefore(now) ?? false) ||
        story.sources.isEmpty) {
      _errorMessage =
          'This story has expired or has no sources. Refresh the story pack.';
      _notify();
      return false;
    }
    final variants =
        story.variants
            .where((variant) => variant.narration.trim().isNotEmpty)
            .toList()
          ..sort(
            (a, b) => a.estimatedDurationSeconds.compareTo(
              b.estimatedDurationSeconds,
            ),
          );
    if (variants.isEmpty) return false;
    // Reading a story should not truncate it to fit an upcoming turn.
    // Playback still goes through the voice controller's navigation gate.
    final variant =
        variants.where((variant) => variant.length == 'Standard').firstOrNull ??
        variants.last;
    _currentSelection = AdaptiveRouteStorySelection(
      story: story,
      variant: variant,
      reason: 'Selected by you.',
    );
    _manualSelection = true;
    _errorMessage = null;
    _notify();
    return true;
  }

  void closeStory() {
    if (_disposed || isBusy || !showingManualStory) return;
    _currentSelection = null;
    _manualSelection = false;
    _lastSelectionProgressMeters = null;
    _errorMessage = null;
    _notify();
  }

  String automaticStoryStatus(AdaptiveRouteStory story, RoamSession session) {
    final now = DateTime.now().toUtc();
    if ((pack?.expiresUtc.isBefore(now) ?? true) ||
        (story.expiresUtc?.isBefore(now) ?? false)) {
      return 'Expired';
    }
    final id = story.storyId;
    final outcomes = _packState?.playbackOutcomes;
    final local = _localPlaybackStates[id];
    if (local == 'Started' || local == 'Resumed') return 'Playing';
    if (local == 'Paused') return 'Paused';
    if (_completedStoryIds.contains(id) ||
        (outcomes?.completedStoryIds.contains(id) ?? false)) {
      return 'Played';
    }
    if (local == 'Skipped' ||
        (outcomes?.skippedStoryIds.contains(id) ?? false)) {
      return 'Skipped';
    }
    if (local == 'Dismissed' ||
        (outcomes?.dismissedStoryIds.contains(id) ?? false)) {
      return 'Dismissed';
    }
    if (_isExcluded(story)) return 'Previously handled';
    if (!story.canAutoplay) {
      return story.sensitivityNotice ?? 'Listen on request';
    }
    if (session.isOffRoute) {
      return session.isNearStoryAnchor(
            story.relevanceLatitude,
            story.relevanceLongitude,
          )
          ? 'Nearby while exploring'
          : 'Waiting until nearby with reliable GPS';
    }
    final progress = _routeProgressMeters(session);
    if (progress < story.playbackWindowStart) return 'Ahead on route';
    if (progress > story.playbackWindowEnd && !_canCatchUp(story, progress)) {
      return 'Automatic playback window passed';
    }
    if (local == 'Interrupted' ||
        (outcomes?.interruptedStoryIds.contains(id) ?? false)) {
      return 'Interrupted - waiting to resume';
    }
    if (local == 'Failed' || (outcomes?.failedStoryIds.contains(id) ?? false)) {
      return 'Audio failed - waiting to retry';
    }
    if (!_safeForContextualStory(session)) {
      return 'Waiting for navigation to clear';
    }
    final seconds = session.storySecondsUntilNavigation;
    if (!story.variants.any(
      (variant) =>
          variant.narration.trim().isNotEmpty &&
          (seconds == null ||
              RoverVoiceController.storyStartSeconds(story, variant) <=
                  seconds - 15),
    )) {
      return 'Waiting for a longer gap before the next turn';
    }
    return progress > story.playbackWindowEnd
        ? 'Waiting to catch up'
        : 'In playback window';
  }

  bool _isExcluded(AdaptiveRouteStory story) =>
      _completedStoryIds.contains(story.storyId) ||
      (_packState?.heardStoryIds.contains(story.storyId) ?? false) ||
      const {
        'Completed',
        'Skipped',
        'Dismissed',
      }.contains(_localPlaybackStates[story.storyId]);

  bool _canCatchUp(AdaptiveRouteStory story, double progress) {
    final now = DateTime.now().toUtc();
    return _deferredStoryIds.contains(story.storyId) &&
        !_isExcluded(story) &&
        (pack?.expiresUtc.isAfter(now) ?? false) &&
        (story.expiresUtc?.isAfter(now) ?? true) &&
        progress >= story.playbackWindowStart &&
        progress <= story.playbackWindowEnd + _catchUpMeters;
  }

  void _rememberDeferredStories(double progress) {
    // Only stories encountered in their original window get a catch-up opportunity.
    for (final story in pack?.stories ?? const <AdaptiveRouteStory>[]) {
      if (progress >= story.playbackWindowStart &&
          progress <= story.playbackWindowEnd &&
          !_isExcluded(story)) {
        _deferredStoryIds.add(story.storyId);
      }
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
    if (!_availableForOfflinePlayback(selection.story)) {
      _errorMessage = 'This story needs a connection to play.';
      _notify();
      return;
    }
    final now = DateTime.now().toUtc();
    if ((pack?.expiresUtc.isBefore(now) ?? true) ||
        (selection.story.expiresUtc?.isBefore(now) ?? false)) {
      _errorMessage = 'This story has expired. Refresh the story pack.';
      _notify();
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
          _errorMessage = 'A turn or arrival needs attention. You can read this story now; tap Play again after the guidance finishes.';
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
      final result = await voiceController.playAdaptiveRouteStoryWithResult(
        selection,
        session,
        userRequested: userRequested,
      );
      if (result == AdaptiveStoryPlaybackResult.blocked) {
        _localPlaybackStates[selection.story.storyId] = 'Waiting';
      } else if (result == AdaptiveStoryPlaybackResult.paused) {
        _localPlaybackStates[selection.story.storyId] = 'Paused';
      }
      if (result == AdaptiveStoryPlaybackResult.interrupted ||
          result == AdaptiveStoryPlaybackResult.failed) {
        final kind = result == AdaptiveStoryPlaybackResult.interrupted
            ? 'Interrupted'
            : 'Failed';
        if (result == AdaptiveStoryPlaybackResult.failed) {
          _errorMessage = 'Story audio could not be played. Please try again.';
        }
        await _record(walkSessionId, selection.story.storyId, kind);
        FieldDiagnostics.instance.record(
          'route-story',
          'playback outcome=$kind story=${selection.story.storyId}',
        );
      }
      if (result == AdaptiveStoryPlaybackResult.completed) {
        // Remember audible completion before a slow or failed acknowledgement can permit a replay.
        _completedStoryIds.add(selection.story.storyId);
        _walkingGap.completed(_latestSession ?? session, _nowUtc());
        _currentSelection = null;
        await _record(walkSessionId, selection.story.storyId, 'Completed');
        FieldDiagnostics.instance.record(
          'route-story',
          'playback completed intent=${selection.story.intent} '
              'duration=${selection.variant.estimatedDurationSeconds}s '
              'offline=$_usingOfflinePack',
        );
        await _refreshStateAfterEvent(session);
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
    if (!_walkingGap.ready) return;
    if (_manualSelection && _currentSelection != null) return;
    _rememberDeferredStories(progressMeters);
    if (session.isOffRoute) {
      _lastSelectionProgressMeters = null;
      _lastSelectionCheckUtc = _nowUtc();
      await _playNearbyStory(session, voiceController);
      return;
    }
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
    final catchUp =
        (pack?.stories ?? const <AdaptiveRouteStory>[])
            .where(
              (story) =>
                  progressMeters > story.playbackWindowEnd &&
                  _availableForOfflinePlayback(story) &&
                  _canCatchUp(story, progressMeters),
            )
            .toList()
          ..sort((a, b) => a.playbackWindowEnd.compareTo(b.playbackWindowEnd));
    for (final story in catchUp) {
      final variants =
          story.variants
              .where((variant) => variant.narration.trim().isNotEmpty)
              .toList()
            ..sort((a, b) {
              if (a.length == 'Standard' && b.length != 'Standard') return -1;
              if (b.length == 'Standard' && a.length != 'Standard') return 1;
              return b.estimatedDurationSeconds.compareTo(
                a.estimatedDurationSeconds,
              );
            });
      for (final variant in variants) {
        final selection = AdaptiveRouteStorySelection(
          story: story,
          variant: variant,
          reason: 'Catching up after a navigation or audio hold.',
        );
        if (!voiceController.canPlayAdaptiveRouteStory(
          selection,
          session,
          userRequested: false,
        )) {
          continue;
        }
        _currentSelection = selection;
        await playCurrent(session, voiceController, userRequested: false);
        return;
      }
    }
    final request = NextRouteStoryRequest(
      routeProgressMeters: progressMeters,
      secondsUntilNextManeuver: _secondsUntilNextManeuver(session),
      preferredLength: 'Standard',
      excludedStoryIds: {
        ..._completedStoryIds,
        ...?packState?.heardStoryIds,
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
        _usingOfflinePack = true;
      }
    }
    if (selection == null) {
      // The server may require a complete variant to fit before a turn. The
      // device can safely play sentence-sized pieces and resume after guidance.
      for (final story in pack?.stories ?? const <AdaptiveRouteStory>[]) {
        if (_isExcluded(story) ||
            !_availableForOfflinePlayback(story) ||
            story.claims.isEmpty ||
            story.sources.isEmpty ||
            progressMeters < story.playbackWindowStart ||
            progressMeters > story.playbackWindowEnd ||
            story.expiresUtc?.isAfter(_nowUtc()) == false) {
          continue;
        }
        final variants =
            story.variants
                .where((variant) => variant.narration.trim().isNotEmpty)
                .toList()
              ..sort(
                (a, b) => (a.length == 'Standard' ? 0 : 1).compareTo(
                  b.length == 'Standard' ? 0 : 1,
                ),
              );
        for (final variant in variants) {
          final candidate = AdaptiveRouteStorySelection(
            story: story,
            variant: variant,
            reason: 'Playing between guidance with sentence-level resumption.',
          );
          if (voiceController.canPlayAdaptiveRouteStory(candidate, session)) {
            selection = candidate;
            break;
          }
        }
        if (selection != null) break;
      }
    }
    if (selection == null) {
      FieldDiagnostics.instance.record(
        'route-story',
        'No eligible story at ${progressMeters.round()} m; '
            'stories=${pack?.stories.length ?? 0}; '
            'nextManeuverSeconds=${_secondsUntilNextManeuver(session)}',
      );
      for (final story in pack?.stories ?? const <AdaptiveRouteStory>[]) {
        FieldDiagnostics.instance.record(
          'route-story',
          '${story.storyId}: ${automaticStoryStatus(story, session)}; '
              'window=${story.playbackWindowStart.round()}-${story.playbackWindowEnd.round()} m; '
              'durations=${story.variants.map((variant) => variant.estimatedDurationSeconds).join(",")} sec',
        );
      }
      return;
    }
    if (request.excludedStoryIds.contains(selection.story.storyId)) return;
    if (_isExcluded(selection.story)) return;
    _deferredStoryIds.add(selection.story.storyId);
    _manualSelection = false;
    _currentSelection = selection;
    _notify();
    await playCurrent(session, voiceController, userRequested: false);
  }

  bool _safeForContextualStory(RoamSession session) {
    if (session.isOffRoute) {
      return false;
    }
    return (session.storyNavigationGuidance?.distanceMeters ?? 9999) > 45;
  }

  Future<void> _playNearbyStory(
    RoamSession session,
    RoverVoiceController voice,
  ) async {
    final currentPack = pack;
    final now = _nowUtc();
    if (currentPack == null || !currentPack.expiresUtc.isAfter(now)) return;
    for (final story in currentPack.stories) {
      if (_isExcluded(story) ||
          !_availableForOfflinePlayback(story) ||
          story.sources.isEmpty ||
          story.claims.isEmpty ||
          !(story.expiresUtc?.isAfter(now) ?? true) ||
          !session.isNearStoryAnchor(
            story.relevanceLatitude,
            story.relevanceLongitude,
          )) {
        continue;
      }
      final variants =
          story.variants
              .where((variant) => variant.narration.trim().isNotEmpty)
              .toList()
            ..sort(
              (a, b) => (a.length == 'Standard' ? 0 : 1).compareTo(
                b.length == 'Standard' ? 0 : 1,
              ),
            );
      for (final variant in variants) {
        final selection = AdaptiveRouteStorySelection(
          story: story,
          variant: variant,
          reason: 'Verified story near your current location.',
        );
        if (!voice.canPlayAdaptiveRouteStory(
          selection,
          session,
          userRequested: false,
        )) {
          continue;
        }
        _currentSelection = selection;
        _manualSelection = false;
        await playCurrent(session, voice, userRequested: false);
        return;
      }
    }
    FieldDiagnostics.instance.record(
      'route-story',
      'Off-route: no fresh unplayed story within 225 m with reliable GPS',
    );
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
    return session.storySecondsUntilNavigation;
  }

  void _maybeReplenish(RoamSession session, double progress) {
    if (_replenishing ||
        _usingOfflinePack ||
        _replenishAttempts >= 6 ||
        session.status != RoamSessionStatus.active ||
        session.isOffRoute ||
        pack == null ||
        _packState?.status == 'Generating') {
      return;
    }
    final now = _nowUtc();
    _lastReplenishAt ??= now;
    final timeoutRetry = _freshStories.isEmpty && !_timeoutRetryUsed;
    final cooldown = timeoutRetry
        ? const Duration(seconds: 20)
        : _lastReplenishProgress == null
        ? const Duration(minutes: 1)
        : const Duration(minutes: 3);
    if (now.difference(_lastReplenishAt!) < cooldown ||
        (!timeoutRetry &&
            _lastReplenishProgress != null &&
            progress < _lastReplenishProgress! + 150 &&
            now.difference(_lastReplenishAt!) < const Duration(minutes: 5))) {
      return;
    }
    final remainingSeconds = pack!.expiresUtc.isAfter(now)
        ? pack!.stories
              .where(
                (story) =>
                    !_isExcluded(story) &&
                    (story.expiresUtc?.isAfter(now) ?? true) &&
                    story.playbackWindowEnd >= progress &&
                    story.playbackWindowStart <= progress + 800,
              )
              .fold<int>(
                0,
                (sum, story) =>
                    sum +
                    story.variants.fold<int>(
                      0,
                      (longest, variant) =>
                          variant.estimatedDurationSeconds > longest
                          ? variant.estimatedDurationSeconds
                          : longest,
                    ),
              )
        : 0;
    if (remainingSeconds >= 180) return;
    if (timeoutRetry) _timeoutRetryUsed = true;
    _lastReplenishAt = now;
    _lastReplenishProgress = progress;
    _replenishAttempts++;
    _replenishing = true;
    _beginRefresh();
    FieldDiagnostics.instance.record(
      'route-story',
      'replenish started remainingSeconds=$remainingSeconds attempt=$_replenishAttempts',
    );
    unawaited(_replenish(session.apiWalkSessionId!, session.routeRevision));
  }

  Future<void> _replenish(String walkId, int revision) async {
    try {
      final result = await _repository.generateRouteStoryPack(
        walkId,
        const GenerateRouteStoryPackRequest(forceRefresh: true),
      );
      if (_disposed ||
          _walkSessionId != walkId ||
          _routeRevision != revision ||
          result.routeRevision != revision ||
          result.walkSessionId != walkId) {
        return;
      }
      _acceptRefreshState(result);
      await _deviceCache.store(_packState!);
      _lastSelectionProgressMeters = null;
      FieldDiagnostics.instance.record(
        'route-story',
        'replenish finished stories=${result.pack?.stories.length ?? 0}',
      );
    } catch (_) {
      if (_walkSessionId == walkId && _routeRevision == revision) {
        _refreshBaseline = null;
        _refreshMessage = _researchUnavailableMessage;
      }
      // Keep the playable queue and back off; a failed refresh is not an audio failure.
      FieldDiagnostics.instance.record(
        'route-story',
        'replenish unavailable; retained current stories',
      );
    } finally {
      _replenishing = false;
      _notify();
    }
  }

  Future<void> _record(
    String? walkSessionId,
    String storyId,
    String kind,
  ) async {
    if (walkSessionId == null) return;
    if (const {
      'Started',
      'Resumed',
      'Paused',
      'Completed',
      'Skipped',
      'Dismissed',
      'Interrupted',
      'Failed',
    }.contains(kind)) {
      _localPlaybackStates[storyId] = kind;
    }
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
    try {
      final result = await _repository.getRouteStoryPackStatus(walkSessionId);
      if (_disposed ||
          _walkSessionId != walkSessionId ||
          _routeRevision != session.routeRevision ||
          result.walkSessionId != walkSessionId ||
          result.routeRevision != session.routeRevision) {
        return;
      }
      _acceptRefreshState(result);
      _usingOfflinePack = false;
      await _deviceCache.store(_packState!);
    } on RoverApiException catch (error) {
      if (!_isConnectivityError(error)) rethrow;
      await _useOfflinePack(session);
    }
  }

  bool _availableForOfflinePlayback(AdaptiveRouteStory story) =>
      !_usingOfflinePack ||
      (story.sources.isNotEmpty &&
          story.sources.every((source) => source.canCache));

  Future<void> _useOfflinePack(RoamSession session) async {
    final cached = await _deviceCache.get(
      session.apiWalkSessionId!,
      session.routeRevision,
    );
    if (_disposed ||
        _walkSessionId != session.apiWalkSessionId ||
        _routeRevision != session.routeRevision) {
      return;
    }
    _usingOfflinePack = true;
    final previous = _packState;
    if (previous?.walkSessionId == session.apiWalkSessionId &&
        previous?.routeRevision == session.routeRevision &&
        (previous?.pack?.expiresUtc.isAfter(_nowUtc()) ?? false)) {
      // Disk downloads deliberately exclude online-only stories. A connection
      // failure must not replace the visible, in-memory collection with them.
      if (cached != null) {
        _packState = AdaptiveRouteStoryPackState(
          walkSessionId: previous!.walkSessionId,
          routeRevision: previous.routeRevision,
          status: previous.status,
          updatedUtc: previous.updatedUtc,
          pack: previous.pack,
          error: previous.error,
          heardStoryIds: {
            ...previous.heardStoryIds,
            ...cached.heardStoryIds,
          }.toList(),
          savedStoryIds: {
            ...previous.savedStoryIds,
            ...cached.savedStoryIds,
          }.toList(),
          playbackOutcomes: previous.playbackOutcomes,
        );
      }
      return;
    }
    _packState = cached;
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
