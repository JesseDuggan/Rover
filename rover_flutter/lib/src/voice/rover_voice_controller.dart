// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../active_roam/active_roam_session.dart';
import '../api/ask_rover_models.dart';
import '../api/adaptive_route_story_models.dart';
import '../api/journey_narration_models.dart';
import '../api/location_story_models.dart';
import '../api/problem_details.dart';
import '../api/walk_repository.dart';
import '../adventure/roam.dart';
import '../diagnostics/field_diagnostics.dart';
import '../location/rover_location.dart';
import '../on_device_ai/rover_on_device_ai_coordinator.dart';
import '../preferences/preferences_controller.dart';
import 'rover_audio_services.dart';
import 'rover_premium_voice.dart';
import 'rover_voice_state.dart';

class RoverVoiceController extends ChangeNotifier {
  static const int _contextualPriority = 30;
  static const int _funFactPriority = 35;
  static const int _userRequestedPriority = 50;
  static const int _approachingStopPriority = 65;
  static const int _arrivalPriority = 80;
  static const int _navigationPriority = 90;
  static const int _safetyPriority = 100;

  RoverVoiceController({
    required this.walkRepository,
    RoverTextToSpeech? textToSpeech,
    RoverSpeechRecognizer? speechRecognizer,
    RoverAudioSessionCoordinator? audioSession,
    RoverPremiumVoiceCoordinator? premiumVoice,
    RoverOnDeviceAiCoordinator? onDeviceAiCoordinator,
    PreferencesController? preferencesController,
    Future<String?> Function()? interactionProfileIdResolver,
    Future<void> Function(String stopId)? onArrivalNarrated,
    bool adaptiveRouteStoriesEnabled = false,
  }) : _textToSpeech = textToSpeech ?? DeviceTextToSpeech(),
       _speechRecognizer = speechRecognizer ?? DeviceSpeechRecognizer(),
       _audioSession = audioSession ?? DeviceAudioSessionCoordinator(),
       _premiumVoice = premiumVoice,
       _onDeviceAiCoordinator = onDeviceAiCoordinator,
       _preferencesController = preferencesController,
       _interactionProfileIdResolver = interactionProfileIdResolver,
       _onArrivalNarrated = onArrivalNarrated,
       _adaptiveRouteStoriesEnabled = adaptiveRouteStoriesEnabled;

  final WalkRepository walkRepository;
  final RoverTextToSpeech _textToSpeech;
  final RoverSpeechRecognizer _speechRecognizer;
  final RoverAudioSessionCoordinator _audioSession;
  final RoverPremiumVoiceCoordinator? _premiumVoice;
  final RoverOnDeviceAiCoordinator? _onDeviceAiCoordinator;
  final PreferencesController? _preferencesController;
  final Future<String?> Function()? _interactionProfileIdResolver;
  final Future<void> Function(String stopId)? _onArrivalNarrated;
  final bool _adaptiveRouteStoriesEnabled;
  final Set<String> _autoNarratedStopKeys = {};
  final Set<String> _arrivalNarrationInFlightKeys = {};
  final Set<String> _prefetchedStopKeys = {};
  final Set<String> _narratedJourneyFactIds = {};
  final Set<String> _announcedManeuverKeys = {};

  RoverAudioState _state = RoverAudioState.idle;
  double _speechRate = 0.48;
  List<String> _narrationSegments = const [];
  int _segmentIndex = 0;
  String? _activeNarrationStopId;
  bool _activeNarrationAudioCacheEligible = false;
  String? _conversationId;
  String _captionText = '';
  String _transcriptText = '';
  String? _errorMessage;
  RoverVoiceTurn? _lastTurn;
  JourneyNarrationDiagnostics? _lastJourneyNarration;
  RoverLatLng? _lastJourneyEvaluationLocation;
  DateTime? _lastJourneyEvaluationAt;
  DateTime? _nextJourneyNarrationAllowedAt;
  DateTime? _arrivalAudioGateUntil;
  int _latestRouteRevision = 0;
  int _activeAudioPriority = 0;
  int _playbackGeneration = 0;
  int _staleJourneyJobs = 0;
  _ScheduledJourneyStory? _activeScheduledStory;
  _ScheduledJourneyStory? _interruptedScheduledStory;
  _ScheduledJourneyStory? _lastCompletedScheduledStory;
  _AdaptiveRouteStoryPlayback? _activeAdaptiveStory;
  _AdaptiveRouteStoryPlayback? _interruptedAdaptiveStory;
  Future<String?>? _interactionProfileId;
  bool _journeyEvaluationInFlight = false;
  bool _privacyAccepted = false;
  DateTime? _storiesQuietUntil;
  bool _isDisposed = false;

  RoverAudioState get state => _state;
  double get speechRate => _speechRate;
  String get captionText => _captionText;
  String get transcriptText => _transcriptText;
  String? get errorMessage => _errorMessage;
  String? get voiceStatusMessage => _premiumVoice?.statusMessage;
  String? get premiumProvider => _premiumVoice?.lastAudio?.provider;
  String? get premiumCacheStatus => _premiumVoice?.lastAudio?.cacheStatus;
  bool? get premiumUsedFallback => _premiumVoice?.lastAudio?.usedFallback;
  int? get premiumAudioBytes => _premiumVoice?.lastAudio?.bytes.length;
  String? get premiumPlaybackError => _premiumVoice?.lastPlaybackError;
  RoverVoiceTurn? get lastTurn => _lastTurn;
  JourneyNarrationDiagnostics? get lastJourneyNarration =>
      _lastJourneyNarration;
  bool get privacyAccepted => _privacyAccepted;
  bool get canAsk =>
      _state != RoverAudioState.listening &&
      _state != RoverAudioState.transcribing &&
      _state != RoverAudioState.thinking &&
      _state != RoverAudioState.speakingAnswer;
  bool get hasNarration => _narrationSegments.isNotEmpty;
  DateTime? get storiesQuietUntil => _storiesQuietUntil;
  bool get storiesAreQuiet =>
      _effectiveStoryDensity == 'quiet' || _temporaryQuietActive;

  Future<void> syncWithSession(RoamSession session) async {
    final walkSessionId = session.apiWalkSessionId;
    if (walkSessionId != null) {
      _autoNarratedStopKeys.addAll(
        session.narratedArrivalStopIds.map(
          (stopId) => '$walkSessionId:$stopId',
        ),
      );
    }
    if (_latestRouteRevision != 0 &&
        _latestRouteRevision != session.routeRevision) {
      _latestRouteRevision = session.routeRevision;
      _staleJourneyJobs++;
      _activeScheduledStory = null;
      _interruptedScheduledStory = null;
      _activeAdaptiveStory = null;
      _interruptedAdaptiveStory = null;
      // A route update invalidates route stories, not an arrival already being heard.
      final arrivalInProgress =
          session.status == RoamSessionStatus.active &&
          _arrivalNarrationInFlightKeys.contains(
            '$walkSessionId:$_activeNarrationStopId',
          );
      if (!arrivalInProgress) {
        _playbackGeneration++;
        if (_activeAudioPriority < _navigationPriority) {
          await _premiumVoice?.stop();
          await _textToSpeech.stop();
          _setState(RoverAudioState.idle);
        }
      } else {
        FieldDiagnostics.instance.record(
          'voice',
          'route revision ${session.routeRevision}: preserving active arrival stop=$_activeNarrationStopId',
        );
      }
    }
    _latestRouteRevision = session.routeRevision;

    final recentStop = session.recentNarrationStop;
    final isArrivalSensitive = _isArrivalSensitiveSession(session);
    if (isArrivalSensitive) {
      await _interruptAdaptiveStory('arrival');
      _arrivalAudioGateUntil = DateTime.now().add(const Duration(seconds: 30));
      final recentName = recentStop?.name ?? 'none';
      final candidateId = session.arrivalCandidateStopId ?? 'none';
      FieldDiagnostics.instance.record(
        'voice',
        'arrival gate active recent=$recentName '
            'candidate=$candidateId '
            'state=$_state priority=$_activeAudioPriority',
      );
    }

    unawaited(_prefetchUpcomingNarration(session));

    RoverStop? candidateStop;
    for (final stop in session.roam.stops) {
      if (stop.id == session.arrivalCandidateStopId) {
        candidateStop = stop;
        break;
      }
    }
    if (recentStop != null && recentStop.id == session.arrivalCandidateStopId) {
      candidateStop = recentStop;
    }
    if (candidateStop != null &&
        walkSessionId != null &&
        !_autoNarratedStopKeys.contains('$walkSessionId:${candidateStop.id}')) {
      final key = '$walkSessionId:${candidateStop.id}';
      await _playAutomaticArrival(
        key,
        candidateStop,
        completed: session.completedStopIds.contains(candidateStop.id),
        candidate: true,
      );
      return;
    }

    if (recentStop != null &&
        session.apiWalkSessionId != null &&
        session.isNearRecentNarrationStop &&
        !_autoNarratedStopKeys.contains('$walkSessionId:${recentStop.id}') &&
        session.completedStopIds.contains(recentStop.id)) {
      final key = '${session.apiWalkSessionId}:${recentStop.id}';
      await _playAutomaticArrival(
        key,
        recentStop,
        completed: true,
        candidate: session.arrivalCandidateStopId == recentStop.id,
      );
      return;
    }

    if (session.status == RoamSessionStatus.completed ||
        session.status == RoamSessionStatus.ended) {
      await stopAll();
      return;
    }

    if (await _considerNavigationGuidance(session)) {
      return;
    }

    if (_adaptiveRouteStoriesEnabled) {
      return;
    }

    final stop = session.recentNarrationStop ?? session.currentStop;
    if (walkSessionId == null || !session.completedStopIds.contains(stop.id)) {
      unawaited(considerJourneyNarration(session));
      return;
    }

    final key = '$walkSessionId:${stop.id}';
    await _playAutomaticArrival(key, stop, completed: true, candidate: false);
  }

  Future<void> _playAutomaticArrival(
    String key,
    RoverStop stop, {
    required bool completed,
    required bool candidate,
  }) async {
    if (_autoNarratedStopKeys.contains(key)) {
      FieldDiagnostics.instance.record(
        'voice',
        'auto arrival narration skipped already played stop=${stop.name}',
      );
      return;
    }
    if (_arrivalNarrationInFlightKeys.isNotEmpty) {
      FieldDiagnostics.instance.record(
        'voice',
        'auto arrival narration already in progress stop=${stop.name}',
      );
      return;
    }
    _arrivalNarrationInFlightKeys.add(key);

    FieldDiagnostics.instance.record(
      'voice',
      'auto arrival narration start stop=${stop.name} '
          'completed=$completed candidate=$candidate',
    );
    try {
      if (_activeAudioPriority < _arrivalPriority) {
        await _premiumVoice?.stop();
        await _textToSpeech.stop();
      }
      final played = await replayNarration(stop, withArrivalAnnouncement: true);
      if (played) {
        _autoNarratedStopKeys.add(key);
        _arrivalAudioGateUntil = null;
        await _onArrivalNarrated?.call(stop.id);
        FieldDiagnostics.instance.record(
          'voice',
          'auto arrival narration done stop=${stop.name} state=$_state',
        );
      } else {
        FieldDiagnostics.instance.record(
          'voice',
          'auto arrival narration interrupted; retry pending stop=${stop.name}',
        );
      }
    } catch (error) {
      _errorMessage = 'Arrival narration failed. Rover will retry.';
      FieldDiagnostics.instance.record(
        'voice',
        'auto arrival narration failed; retry pending stop=${stop.name} '
            'error=$error',
      );
      _setState(RoverAudioState.idle);
      _activeAudioPriority = 0;
    } finally {
      _arrivalNarrationInFlightKeys.remove(key);
    }
  }

  Future<bool> _considerNavigationGuidance(RoamSession session) async {
    final guidance = session.navigationGuidance;
    if (guidance == null ||
        guidance.distanceMeters > 45 ||
        _arrivalAudioGateActive ||
        _isArrivalSensitiveSession(session)) {
      return false;
    }

    final key =
        '${session.apiWalkSessionId}:${session.routeRevision}:'
        '${guidance.maneuver.sequenceNumber}';
    if (!_announcedManeuverKeys.add(key)) {
      return true;
    }

    // Repeated GPS updates for an announced maneuver must not stop resumed audio.
    await _interruptScheduledStoryForNavigation(session);

    final instruction = guidance.distanceMeters <= 12
        ? guidance.maneuver.instruction
        : 'In ${guidance.distanceMeters} meters, '
              '${guidance.maneuver.instruction}';
    FieldDiagnostics.instance.record(
      'voice',
      'google navigation maneuver=${guidance.maneuver.maneuverType} '
          'distance=${guidance.distanceMeters}m sequence='
          '${guidance.maneuver.sequenceNumber}',
    );
    await _speakAnswer(
      instruction,
      priority: _navigationPriority,
      purpose: 'TurnByTurn',
      localOnly: true,
    );
    return true;
  }

  Future<void> considerJourneyNarration(RoamSession session) async {
    final walkSessionId = session.apiWalkSessionId;
    if (walkSessionId == null ||
        session.status != RoamSessionStatus.active ||
        _journeyEvaluationInFlight ||
        _isDisposed) {
      return;
    }

    if (_latestRouteRevision == 0) {
      _latestRouteRevision = session.routeRevision;
    }

    if (!_shouldEvaluateJourneyNarration(session)) {
      return;
    }

    final startedAt = DateTime.now();
    final routeRevision = session.routeRevision;
    _journeyEvaluationInFlight = true;
    _lastJourneyEvaluationAt = startedAt;
    _lastJourneyEvaluationLocation = session.simulatedLocation;
    _notify();

    try {
      final profileId = await _resolveInteractionProfileId();
      final decision = await walkRepository.evaluateJourneyNarration(
        walkSessionId,
        JourneyNarrationEvaluateRequest(
          location: session.simulatedLocation,
          profileId: profileId,
          gpsAccuracyMeters: session.currentGpsAccuracyMeters,
          headingDegrees: session.currentHeadingDegrees,
          secondsUntilNextManeuver: _secondsUntilNextManeuver(session),
          storyDurationSeconds:
              _interruptedScheduledStory?.estimatedDurationSeconds,
          storyDensity: _effectiveStoryDensity,
          preferredStoryCategories:
              _preferencesController?.preferences.interests ?? const [],
          excludedStoryCategories:
              _preferencesController?.preferences.excludedStoryCategories ??
              const [],
          routeState: session.isOffRoute ? 'offRoute' : 'onRoute',
          userAttentionAvailable: session.screenAwake,
          audioAlreadyQueued: _activeAudioPriority > 0,
          interruptedStoryId: _interruptedScheduledStory?.storyId,
          interruptedStoryRouteId: _interruptedScheduledStory?.walkSessionId,
          interruptedStoryExpiresUtc: _interruptedScheduledStory?.expiresUtc,
          interruptedStoryStillRelevant: _interruptedStoryIsRelevant(session),
          alreadyNarratedFactIds: _narratedJourneyFactIds.toList(),
          requestedAtUtc: startedAt.toUtc(),
        ),
      );
      final latency = DateTime.now().difference(startedAt);
      final stale = _latestRouteRevision != routeRevision;
      if (stale) {
        _staleJourneyJobs++;
      }
      _lastJourneyNarration = JourneyNarrationDiagnostics.fromDecision(
        decision,
        latency: latency,
        staleJobs: _staleJourneyJobs,
        played: false,
        skippedReason: stale ? 'Route changed before playback.' : null,
      );
      _notify();

      if (decision.schedulerApplied && decision.scheduleAction == 'Discard') {
        _interruptedScheduledStory = null;
        return;
      }

      if (decision.schedulerApplied && decision.scheduleAction == 'Resume') {
        await _resumeInterruptedScheduledStory(session);
        return;
      }

      if (stale ||
          !decision.shouldNarrate ||
          decision.narrationText == null ||
          decision.narrationText!.trim().isEmpty) {
        return;
      }

      if (_isReservedArrivalDecision(decision, session)) {
        _lastJourneyNarration = _lastJourneyNarration?.copyWith(
          skippedReason:
              'Upcoming stop narration is reserved for geofence entry.',
        );
        FieldDiagnostics.instance.record(
          'voice',
          'journey narration skipped; reserved arrival stop=${session.currentStop.name}',
        );
        _notify();
        return;
      }

      if (_arrivalAudioGateActive) {
        _lastJourneyNarration = _lastJourneyNarration?.copyWith(
          skippedReason: 'Arrival audio is pending.',
        );
        FieldDiagnostics.instance.record(
          'voice',
          'journey narration skipped; arrival audio pending',
        );
        _notify();
        return;
      }

      final factIds = decision.factIdsUsed.toSet();
      if (factIds.isNotEmpty &&
          factIds.every(_narratedJourneyFactIds.contains)) {
        _lastJourneyNarration = _lastJourneyNarration?.copyWith(
          skippedReason: 'Duplicate facts suppressed.',
        );
        _notify();
        return;
      }

      final priority = _priorityFor(decision.priority);
      if (!_canStartPriority(priority)) {
        _lastJourneyNarration = _lastJourneyNarration?.copyWith(
          skippedReason: 'Higher-priority audio is active.',
        );
        FieldDiagnostics.instance.record(
          'voice',
          'journey narration skipped; active priority=$_activeAudioPriority '
              'requested=$priority',
        );
        _notify();
        return;
      }

      final scheduledStory = decision.schedulerApplied
          ? _ScheduledJourneyStory(
              storyId:
                  decision.storyId ??
                  '${session.apiWalkSessionId}:${decision.placeId ?? 'story'}',
              walkSessionId: walkSessionId,
              routeRevision: routeRevision,
              text: decision.narrationText!.trim(),
              factIds: factIds,
              origin: session.simulatedLocation,
              expiresUtc:
                  decision.storyExpiresUtc ??
                  DateTime.now().toUtc().add(const Duration(minutes: 10)),
              estimatedDurationSeconds: decision.estimatedDurationSeconds ?? 30,
              priority: priority,
              cooldownSeconds: decision.cooldownSeconds,
              category: _categoryForNarrationKind(decision.kind),
              audioCacheEligible: decision.audioCacheEligible,
            )
          : null;
      _activeScheduledStory = scheduledStory;
      if (scheduledStory != null) {
        unawaited(_recordStoryInteraction(scheduledStory, 'Offered'));
        unawaited(_recordStoryInteraction(scheduledStory, 'Started'));
      }
      final played = await _speakAnswer(
        decision.narrationText!.trim(),
        priority: priority,
        purpose: 'JourneyNarration',
        audioCacheEligible: decision.audioCacheEligible,
        cacheExpiresUtc: decision.storyExpiresUtc,
        storyId: decision.storyId,
        variantId: decision.storyId == null
            ? null
            : '${decision.storyId}:standard',
      );
      if (!played) {
        if (identical(_activeScheduledStory, scheduledStory)) {
          _activeScheduledStory = null;
        }
        return;
      }
      _activeScheduledStory = null;
      _interruptedScheduledStory = null;
      _lastCompletedScheduledStory = scheduledStory;
      if (scheduledStory != null) {
        unawaited(_recordStoryInteraction(scheduledStory, 'Completed'));
      }
      _narratedJourneyFactIds.addAll(factIds);
      _nextJourneyNarrationAllowedAt = DateTime.now().add(
        Duration(seconds: decision.cooldownSeconds),
      );
      _lastJourneyNarration = _lastJourneyNarration?.copyWith(played: true);
      _notify();
    } on RoverApiException catch (exception) {
      _lastJourneyNarration = JourneyNarrationDiagnostics(
        kind: 'Error',
        priority: 'ContextualStory',
        reason: exception.message,
        factIds: const [],
        cacheStatus: 'miss',
        generationLatencyMs: DateTime.now()
            .difference(startedAt)
            .inMilliseconds,
        played: false,
        staleJobs: _staleJourneyJobs,
        cooldownRemainingSeconds: _cooldownRemainingSeconds,
      );
      _notify();
    } finally {
      _journeyEvaluationInFlight = false;
      _notify();
    }
  }

  Future<void> prepareAndPlayNarration(RoverStop stop) async {
    if (_state == RoverAudioState.speakingNarration ||
        _state == RoverAudioState.preparingNarration) {
      return;
    }

    _activeNarrationStopId = stop.id;
    _activeNarrationAudioCacheEligible = _stopAudioCacheEligible(stop);
    _narrationSegments = _segmentsFor(stop);
    _segmentIndex = 0;
    _captionText = _narrationSegments.join(' ');
    await _speakNarrationFromCurrentSegment();
  }

  Future<void> playNarration(RoverStop stop) async {
    if (_activeNarrationStopId != stop.id || _narrationSegments.isEmpty) {
      await prepareAndPlayNarration(stop);
      return;
    }
    await _speakNarrationFromCurrentSegment();
  }

  Future<void> pauseNarration() async {
    if (_state != RoverAudioState.speakingNarration) {
      return;
    }
    await _premiumVoice?.pause();
    await _textToSpeech.pause();
    _setState(RoverAudioState.narrationPaused);
  }

  Future<void> resumeNarration() async {
    if (_state != RoverAudioState.narrationPaused) {
      return;
    }
    await _speakNarrationFromCurrentSegment();
  }

  Future<bool> replayNarration(
    RoverStop stop, {
    bool withArrivalAnnouncement = false,
  }) async {
    await _premiumVoice?.stop();
    await _textToSpeech.stop();
    _activeNarrationStopId = stop.id;
    _activeNarrationAudioCacheEligible = _stopAudioCacheEligible(stop);
    _narrationSegments = _segmentsFor(
      stop,
      withArrivalAnnouncement: withArrivalAnnouncement,
    );
    _segmentIndex = 0;
    _captionText = _narrationSegments.join(' ');
    return _speakNarrationFromCurrentSegment();
  }

  Future<void> stopAll() async {
    _playbackGeneration++;
    _activeScheduledStory = null;
    _interruptedScheduledStory = null;
    await _speechRecognizer.cancel();
    await _premiumVoice?.stop();
    await _textToSpeech.stop();
    _setState(RoverAudioState.idle);
  }

  Future<void> acceptPrivacyAndAsk(RoamSession session) async {
    _privacyAccepted = true;
    await askRover(session);
  }

  Future<void> askRover(RoamSession session) async {
    if (!canAsk || session.apiWalkSessionId == null) {
      return;
    }

    try {
      if (_state == RoverAudioState.speakingNarration ||
          _state == RoverAudioState.narrationPaused) {
        await _textToSpeech.stop();
        _setState(RoverAudioState.narrationPaused);
      }

      final permission = await _speechRecognizer.ensurePermission();
      if (permission != MicrophonePermissionState.granted) {
        _errorMessage =
            permission == MicrophonePermissionState.permanentlyDenied
            ? 'Microphone permission is blocked. Open settings to allow Ask Rover.'
            : 'Microphone permission is needed for Ask Rover.';
        _setState(RoverAudioState.error);
        return;
      }

      _transcriptText = '';
      _setState(RoverAudioState.listening);
      final initialized = await _speechRecognizer.initialize(
        onResult: (text, finalResult) {
          _transcriptText = text;
          if (finalResult && text.trim().isNotEmpty) {
            unawaited(_submitQuestion(session, text.trim()));
          } else {
            _notify();
          }
        },
        onError: (message) {
          _errorMessage = message.isEmpty
              ? 'Speech recognition failed.'
              : message;
          _setState(RoverAudioState.error);
        },
      );
      if (!initialized) {
        _errorMessage = 'Speech recognition is unavailable on this device.';
        _setState(RoverAudioState.error);
        return;
      }
      await _speechRecognizer.listen();
    } catch (error) {
      _errorMessage = 'Ask Rover could not start.';
      _setState(RoverAudioState.error);
    }
  }

  Future<void> cancelListening() async {
    await _speechRecognizer.cancel();
    _setState(
      hasNarration ? RoverAudioState.narrationPaused : RoverAudioState.idle,
    );
  }

  Future<void> submitEditedQuestion(
    RoamSession session,
    String questionText,
  ) async {
    if (questionText.trim().isEmpty || !canAsk) {
      _errorMessage = 'Ask Rover needs a transcribed question first.';
      _setState(RoverAudioState.error);
      return;
    }
    await _submitQuestion(session, questionText.trim());
  }

  Future<void> tellNearbyStory(
    RoamSession session, {
    String? selectedPlaceId,
  }) async {
    await tellLocationStory(
      location: session.simulatedLocation,
      routeId: session.apiWalkSessionId,
      routeGeometry: session.roam.routeGeometry,
      selectedPlaceId: selectedPlaceId,
      label: 'Tell Me Nearby',
    );
  }

  Future<void> tellLocationStory({
    required RoverLatLng location,
    required String? routeId,
    required List<RoverLatLng> routeGeometry,
    String? selectedPlaceId,
    String? selectedPlaceName,
    String? selectedPlaceFallbackNarration,
    String label = 'Location Story',
  }) async {
    if (!canAsk) {
      return;
    }

    _setState(RoverAudioState.thinking);
    try {
      final response = await walkRepository.createLocationStory(
        LocationStoryRequest(
          location: location,
          radiusMeters: 1500,
          routeId: routeId,
          routeGeometry: routeGeometry,
          interests: const [],
          selectedPlaceIds: selectedPlaceId == null
              ? const []
              : [selectedPlaceId],
          narrationStyle: 'short-spoken',
        ),
      );
      final responseMatchesSelection =
          selectedPlaceId == null ||
          (response.placeId?.toLowerCase() == selectedPlaceId.toLowerCase());
      final String answer;
      if (!responseMatchesSelection) {
        final fallback = selectedPlaceFallbackNarration?.trim();
        FieldDiagnostics.instance.record(
          'voice',
          'location story selection mismatch; requested=$selectedPlaceId '
              'received=${response.placeId ?? 'none'}; '
              'fallback=${fallback?.isNotEmpty == true}',
        );
        if (fallback == null || fallback.isEmpty) {
          _errorMessage =
              'Rover could not load the selected ${selectedPlaceName ?? 'place'} story.';
          _setState(RoverAudioState.error);
          return;
        }
        answer = fallback;
      } else {
        final attribution = response.requiredAttribution.isEmpty
            ? ''
            : ' Sources: ${response.requiredAttribution.join(', ')}.';
        answer = '${response.shortSpokenNarration}$attribution';
      }
      _lastTurn = RoverVoiceTurn(
        questionText: selectedPlaceName == null
            ? label
            : '$label: $selectedPlaceName',
        answerText: answer,
        provider: response.offlineCached
            ? 'ROVER offline cache'
            : 'Location Intelligence',
        suggestedAction: 'Informational',
        safetyNotice: response.warnings.isEmpty
            ? null
            : response.warnings.take(2).join(' '),
      );
      _captionText = answer;
      if (response.offlineCached) {
        FieldDiagnostics.instance.record(
          'voice',
          'offline cached story playback place=${response.placeId ?? 'unknown'} '
              'verified=${response.lastVerifiedUtc?.toIso8601String() ?? 'unknown'}',
        );
      }
      await _speakAnswer(
        answer,
        priority: _userRequestedPriority,
        purpose: 'TellMeNearby',
        localOnly: response.offlineCached,
      );
    } on RoverApiException catch (exception) {
      _errorMessage =
          'Tell Me Nearby could not load live location context: ${exception.message}';
      _setState(RoverAudioState.error);
    }
  }

  Future<void> replayAnswer() async {
    final answer = _lastTurn?.answerText;
    if (answer == null || answer.isEmpty) {
      return;
    }
    await _speakAnswer(
      answer,
      priority: _userRequestedPriority,
      purpose: 'AskRoverAnswer',
    );
  }

  Future<void> continueNarration() async {
    if (_narrationSegments.isEmpty) {
      return;
    }
    await resumeNarration();
  }

  Future<void> prefetchAdaptiveRouteStory(AdaptiveRouteStory story) async {
    if (_isDisposed ||
        (story.expiresUtc?.isAfter(DateTime.now().toUtc()) == false))
      return;
    final variants = story.variants
        .where(
          (variant) =>
              variant.length.toLowerCase() == 'standard' ||
              variant.length.toLowerCase() == 'quick',
        )
        .take(2);
    for (final variant in variants) {
      final segments = _storySegments(variant.narration);
      if (segments.isEmpty || _isDisposed) continue;
      await _premiumVoice?.prefetch(
        text: segments.first,
        purpose: 'AdaptiveRouteStory',
        audioCacheEligible: story.sources.every((source) => source.canCache),
        cacheExpiresUtc: story.expiresUtc,
        storyId: story.storyId,
        variantId: '${story.storyId}:${variant.length.toLowerCase()}:0',
      );
    }
  }

  Future<bool> playAdaptiveRouteStory(
    AdaptiveRouteStorySelection selection,
    RoamSession session, {
    bool userRequested = false,
  }) async {
    if (selection.story.expiresUtc?.isAfter(DateTime.now().toUtc()) == false)
      return false;
    if (!canPlayAdaptiveRouteStory(
      selection,
      session,
      userRequested: userRequested,
    )) {
      return false;
    }
    final interrupted = _interruptedAdaptiveStory;
    final playback =
        interrupted?.selection.story.storyId == selection.story.storyId
        ? interrupted!
        : _AdaptiveRouteStoryPlayback(
            selection: selection,
            walkSessionId: session.apiWalkSessionId ?? '',
            routeRevision: session.routeRevision,
            segments: _storySegments(selection.variant.narration),
          );
    _interruptedAdaptiveStory = null;
    _activeAdaptiveStory = playback;
    final priority = userRequested
        ? _userRequestedPriority
        : _contextualPriority;
    _lastTurn = RoverVoiceTurn(
      questionText: userRequested
          ? 'Route story: ${selection.story.title}'
          : 'Along the route',
      answerText: selection.variant.narration,
      provider: 'Adaptive Route Story Pack',
      suggestedAction: 'Informational',
      safetyNotice: null,
    );
    _captionText = selection.variant.narration;
    final audioCacheEligible = selection.story.sources.every(
      (source) => source.canCache,
    );
    while (playback.segmentIndex < playback.segments.length) {
      if (selection.story.expiresUtc?.isAfter(DateTime.now().toUtc()) == false)
        return false;
      final prefix = playback.wasInterrupted ? 'Continuing the story. ' : '';
      playback.wasInterrupted = false;
      final nextIndex = playback.segmentIndex + 1;
      final premium = _premiumVoice;
      if (premium != null && nextIndex < playback.segments.length) {
        unawaited(
          premium.prefetch(
            text: playback.segments[nextIndex],
            purpose: 'AdaptiveRouteStory',
            audioCacheEligible: audioCacheEligible,
            cacheExpiresUtc: selection.story.expiresUtc,
            storyId: selection.story.storyId,
            variantId:
                '${selection.story.storyId}:${selection.variant.length.toLowerCase()}:$nextIndex',
          ),
        );
      }
      final played = await _speakAnswer(
        '$prefix${playback.segments[playback.segmentIndex]}',
        priority: priority,
        purpose: 'AdaptiveRouteStory',
        audioCacheEligible: audioCacheEligible,
        cacheExpiresUtc: selection.story.expiresUtc,
        storyId: selection.story.storyId,
        variantId:
            '${selection.story.storyId}:${selection.variant.length.toLowerCase()}:${playback.segmentIndex}',
      );
      if (!played) return false;
      playback.segmentIndex++;
    }
    _activeAdaptiveStory = null;
    return true;
  }

  bool hasInterruptedAdaptiveStory(String storyId) =>
      _interruptedAdaptiveStory?.selection.story.storyId == storyId;

  bool hasAutomaticallyResumableAdaptiveStory(String storyId) {
    final interrupted = _interruptedAdaptiveStory;
    return interrupted?.selection.story.storyId == storyId &&
        !interrupted!.userPaused;
  }

  bool canPlayAdaptiveRouteStory(
    AdaptiveRouteStorySelection selection,
    RoamSession session, {
    bool userRequested = false,
  }) {
    final availableSeconds = session.storySecondsUntilInterruption;
    if (availableSeconds != null &&
        selection.variant.estimatedDurationSeconds > availableSeconds - 15) {
      return false;
    }
    if (_isArrivalSensitiveSession(session) ||
        (session.storyNavigationGuidance?.distanceMeters ?? 9999) <= 45) {
      return false;
    }
    return userRequested || !session.isOffRoute;
  }

  Future<void> pauseAdaptiveRouteStory() async {
    if (_state != RoverAudioState.speakingAnswer) return;
    await _interruptAdaptiveStory('user pause');
    _setState(RoverAudioState.narrationPaused);
  }

  Future<void> setSpeechRate(double value) async {
    _speechRate = value.clamp(0.3, 0.65);
    await _textToSpeech.configure(rate: _speechRate);
    _notify();
  }

  Future<bool> applyStoryControl(RoverStoryControlCommand command) =>
      _applyStoryControl(command);

  Future<void> _submitQuestion(RoamSession session, String questionText) async {
    if (_state == RoverAudioState.thinking ||
        _state == RoverAudioState.speakingAnswer) {
      return;
    }

    await _speechRecognizer.stop();
    final command = _onDeviceAiCoordinator?.interpretStoryControl(questionText);
    if (command != null && await _applyStoryControl(command)) {
      return;
    }
    _setState(RoverAudioState.thinking);
    try {
      final response = await walkRepository.askRover(
        session.apiWalkSessionId!,
        AskRoverRequest(
          questionText: questionText,
          currentStopId: session.currentStop.id,
          location: session.simulatedLocation,
          recordedAtUtc: DateTime.now().toUtc(),
          conversationId: _conversationId,
        ),
      );
      _conversationId = response.conversationId;
      _lastTurn = RoverVoiceTurn(
        questionText: questionText,
        answerText: response.answerText,
        provider: response.provider,
        suggestedAction: response.suggestedAction,
        safetyNotice: response.safetyNotice,
      );
      _captionText = response.answerText;
      await _speakAnswer(
        response.answerText,
        priority: _userRequestedPriority,
        purpose: 'AskRoverAnswer',
      );
    } on RoverApiException catch (exception) {
      _errorMessage = exception.message;
      _setState(RoverAudioState.error);
    }
  }

  Future<bool> _speakNarrationFromCurrentSegment() async {
    if (_narrationSegments.isEmpty) {
      _setState(RoverAudioState.idle);
      FieldDiagnostics.instance.record(
        'voice',
        'narration empty; state=$_state',
      );
      return false;
    }

    final playbackGeneration = ++_playbackGeneration;
    _activeAudioPriority = _arrivalPriority;
    _setState(RoverAudioState.preparingNarration);
    await _audioSession.configure();
    if (playbackGeneration != _playbackGeneration) return false;
    await _textToSpeech.configure(rate: _speechRate);
    if (playbackGeneration != _playbackGeneration) return false;
    await _premiumVoice?.stop();
    if (playbackGeneration != _playbackGeneration) return false;
    await _textToSpeech.stop();
    if (playbackGeneration != _playbackGeneration) return false;
    _setState(RoverAudioState.speakingNarration);
    final activeStopId = _activeNarrationStopId ?? 'none';
    FieldDiagnostics.instance.record(
      'voice',
      'narration playback start stop=$activeStopId '
          'segments=${_narrationSegments.length}',
    );
    while (_segmentIndex < _narrationSegments.length &&
        _state == RoverAudioState.speakingNarration &&
        !_isDisposed) {
      final segment = _narrationSegments[_segmentIndex];
      _captionText = segment;
      _notify();
      _activeAudioPriority = _arrivalPriority;
      final premiumSpoken =
          await _premiumVoice?.speak(
            text: segment,
            purpose: 'StopNarration',
            walkSessionId: null,
            stopId: _activeNarrationStopId,
            audioCacheEligible: _activeNarrationAudioCacheEligible,
          ) ??
          false;
      if (playbackGeneration != _playbackGeneration ||
          _state != RoverAudioState.speakingNarration) {
        return false;
      }
      final premiumStatus = premiumSpoken ? 'played' : 'fallback';
      final premiumDetail = _premiumVoice?.statusMessage ?? 'not configured';
      final segmentStopId = _activeNarrationStopId ?? 'none';
      FieldDiagnostics.instance.record(
        'voice',
        'segment ${_segmentIndex + 1}/${_narrationSegments.length} '
            'premium=$premiumStatus provider="$premiumDetail" '
            'stop=$segmentStopId',
      );
      _notify();
      if (!premiumSpoken) {
        await _textToSpeech.speak(segment);
        if (playbackGeneration != _playbackGeneration) {
          return false;
        }
      }
      if (_state == RoverAudioState.speakingNarration) {
        _segmentIndex++;
      }
    }
    if (_state == RoverAudioState.speakingNarration) {
      _setState(RoverAudioState.idle);
      _activeAudioPriority = 0;
      final finishedStopId = _activeNarrationStopId ?? 'none';
      FieldDiagnostics.instance.record(
        'voice',
        'narration playback finished stop=$finishedStopId',
      );
      return true;
    }
    return false;
  }

  Future<bool> _speakAnswer(
    String answerText, {
    required int priority,
    required String purpose,
    bool localOnly = false,
    bool audioCacheEligible = false,
    DateTime? cacheExpiresUtc,
    String? storyId,
    String? variantId,
  }) async {
    if (!_canStartPriority(priority)) {
      return false;
    }

    final playbackGeneration = ++_playbackGeneration;
    _activeAudioPriority = priority;
    _setState(RoverAudioState.speakingAnswer);
    await _audioSession.configure();
    if (playbackGeneration != _playbackGeneration) return false;
    await _textToSpeech.configure(rate: _speechRate);
    if (playbackGeneration != _playbackGeneration) return false;
    await _premiumVoice?.stop();
    if (playbackGeneration != _playbackGeneration) return false;
    await _textToSpeech.stop();
    if (playbackGeneration != _playbackGeneration) return false;
    final premiumSpoken = localOnly
        ? false
        : await _premiumVoice?.speak(
                text: answerText,
                purpose: purpose,
                audioCacheEligible: audioCacheEligible,
                cacheExpiresUtc: cacheExpiresUtc,
                storyId: storyId,
                variantId: variantId,
              ) ??
              false;
    if (playbackGeneration != _playbackGeneration ||
        _state != RoverAudioState.speakingAnswer) {
      return false;
    }
    _notify();
    if (!premiumSpoken) {
      await _textToSpeech.speak(answerText);
      if (playbackGeneration != _playbackGeneration ||
          _state != RoverAudioState.speakingAnswer) {
        return false;
      }
    }
    if (_state == RoverAudioState.speakingAnswer) {
      _setState(
        hasNarration ? RoverAudioState.narrationPaused : RoverAudioState.idle,
      );
      _activeAudioPriority = 0;
    }
    return true;
  }

  Future<void> _interruptScheduledStoryForNavigation(
    RoamSession session,
  ) async {
    final story = _activeScheduledStory;
    if (_activeAudioPriority >= _navigationPriority) {
      return;
    }

    await _interruptAdaptiveStory('navigation');
    if (story == null) return;

    _interruptedScheduledStory = story;
    _activeScheduledStory = null;
    _playbackGeneration++;
    await _premiumVoice?.stop();
    await _textToSpeech.stop();
    _activeAudioPriority = 0;
    _setState(RoverAudioState.idle);
    unawaited(_recordStoryInteraction(story, 'Interrupted'));
    FieldDiagnostics.instance.record(
      'voice',
      'scheduled story interrupted by navigation story=${story.storyId} '
          'routeRevision=${session.routeRevision}',
    );
  }

  Future<void> _interruptAdaptiveStory(String reason) async {
    final playback = _activeAdaptiveStory;
    if (playback == null) return;
    playback.wasInterrupted = true;
    playback.userPaused = reason == 'user pause';
    _interruptedAdaptiveStory = playback;
    _activeAdaptiveStory = null;
    _playbackGeneration++;
    await _premiumVoice?.stop();
    await _textToSpeech.stop();
    _activeAudioPriority = 0;
    _setState(RoverAudioState.idle);
    FieldDiagnostics.instance.record(
      'voice',
      'adaptive story interrupted reason=$reason '
          'story=${playback.selection.story.storyId} '
          'segment=${playback.segmentIndex}',
    );
  }

  Future<void> _resumeInterruptedScheduledStory(RoamSession session) async {
    final story = _interruptedScheduledStory;
    if (story == null || !_interruptedStoryIsRelevant(session)) {
      _interruptedScheduledStory = null;
      return;
    }

    _interruptedScheduledStory = null;
    _activeScheduledStory = story;
    unawaited(_recordStoryInteraction(story, 'Started'));
    final played = await _speakAnswer(
      'Continuing the story. ${story.text}',
      priority: story.priority,
      purpose: 'JourneyNarrationResume',
      audioCacheEligible: story.audioCacheEligible,
      cacheExpiresUtc: story.expiresUtc,
      storyId: story.storyId,
      variantId: '${story.storyId}:standard',
    );
    _activeScheduledStory = null;
    if (!played) {
      return;
    }

    _narratedJourneyFactIds.addAll(story.factIds);
    _lastCompletedScheduledStory = story;
    unawaited(_recordStoryInteraction(story, 'Completed'));
    _nextJourneyNarrationAllowedAt = DateTime.now().add(
      Duration(seconds: story.cooldownSeconds),
    );
    _lastJourneyNarration = _lastJourneyNarration?.copyWith(played: true);
    FieldDiagnostics.instance.record(
      'voice',
      'scheduled story resumed story=${story.storyId}',
    );
    _notify();
  }

  bool _interruptedStoryIsRelevant(RoamSession session) {
    final story = _interruptedScheduledStory;
    if (story == null || session.apiWalkSessionId != story.walkSessionId) {
      return false;
    }
    if (session.routeRevision != story.routeRevision ||
        DateTime.now().toUtc().isAfter(story.expiresUtc) ||
        session.status != RoamSessionStatus.active ||
        session.isOffRoute ||
        _isArrivalSensitiveSession(session)) {
      return false;
    }
    return session.simulatedLocation.distanceTo(story.origin) <= 650;
  }

  int? _secondsUntilNextManeuver(RoamSession session) {
    final guidance = session.navigationGuidance;
    if (guidance == null) {
      return null;
    }
    return (guidance.distanceMeters / 1.4).ceil();
  }

  bool _shouldEvaluateJourneyNarration(RoamSession session) {
    if (storiesAreQuiet) {
      return false;
    }
    if (_arrivalAudioGateActive || _isArrivalSensitiveSession(session)) {
      return false;
    }

    if (_state == RoverAudioState.listening ||
        _state == RoverAudioState.transcribing ||
        _state == RoverAudioState.thinking ||
        _state == RoverAudioState.speakingAnswer ||
        _state == RoverAudioState.speakingNarration) {
      return false;
    }

    if (_interruptedScheduledStory != null) {
      return true;
    }

    final now = DateTime.now();
    final cooldown = _nextJourneyNarrationAllowedAt;
    if (cooldown != null && now.isBefore(cooldown)) {
      return false;
    }

    final distanceToNext = session.distanceToNextStopMeters;
    if (distanceToNext != null &&
        distanceToNext <= session.storyArrivalBoundaryMeters) {
      return false;
    }

    if (session.currentGpsAccuracyMeters != null &&
        session.currentGpsAccuracyMeters! > 80) {
      return false;
    }

    if (_lastJourneyEvaluationAt == null ||
        now.difference(_lastJourneyEvaluationAt!).inSeconds >= 120 ||
        _latestRouteRevision != session.routeRevision) {
      return true;
    }

    final lastLocation = _lastJourneyEvaluationLocation;
    if (lastLocation == null) {
      return true;
    }

    return session.simulatedLocation.distanceTo(lastLocation) >= 80;
  }

  Future<bool> _applyStoryControl(RoverStoryControlCommand command) async {
    switch (command.action) {
      case RoverStoryControlAction.quietTenMinutes:
        _storiesQuietUntil = DateTime.now().add(const Duration(minutes: 10));
        await _stopOptionalStory();
        await _acknowledgeStoryControl(
          'Stories are quiet for ten minutes. Navigation and arrival guidance remain on.',
        );
        return true;
      case RoverStoryControlAction.resumeStories:
        _storiesQuietUntil = null;
        final preferences = _preferencesController?.preferences;
        if (preferences?.storyDensity.toLowerCase() == 'quiet') {
          await _preferencesController?.save(
            preferences!.copyWith(storyDensity: 'Highlights'),
          );
        }
        await _acknowledgeStoryControl('Stories are available again.');
        return true;
      case RoverStoryControlAction.skip:
        final skippedStory =
            _activeScheduledStory ?? _interruptedScheduledStory;
        if (skippedStory != null) {
          unawaited(_recordStoryInteraction(skippedStory, 'Skipped'));
        }
        _narratedJourneyFactIds.addAll(
          _activeScheduledStory?.factIds ?? const <String>{},
        );
        await _stopOptionalStory();
        _captionText = 'Story skipped.';
        _notify();
        return true;
      case RoverStoryControlAction.shortVersion:
        final short = _shortVersionOf(
          _activeScheduledStory?.text ?? _lastTurn?.answerText ?? _captionText,
        );
        if (short.isEmpty) {
          return false;
        }
        await _stopOptionalStory();
        await _speakAnswer(
          short,
          priority: _userRequestedPriority,
          purpose: 'AskRoverAnswer',
        );
        return true;
      case RoverStoryControlAction.preferCategory:
        await _includeStoryCategory(command.category ?? 'history');
        await _acknowledgeStoryControl(
          'I will favor ${command.category ?? 'history'} stories.',
        );
        return true;
      case RoverStoryControlAction.reduceWeather:
        await _excludeStoryCategory('weather');
        await _acknowledgeStoryControl(
          'I will reduce optional weather stories. Important safety updates remain on.',
        );
        return true;
      case RoverStoryControlAction.preferSimilar:
        final category = _currentStoryCategory;
        if (category == null) return false;
        await _includeStoryCategory(category);
        await _acknowledgeStoryControl(
          'I will favor more $category stories like this.',
        );
        return true;
      case RoverStoryControlAction.dismissCategory:
        final category = _currentStoryCategory;
        if (category == null) return false;
        final dismissedStory =
            _activeScheduledStory ??
            _interruptedScheduledStory ??
            _lastCompletedScheduledStory;
        if (dismissedStory != null) {
          unawaited(_recordStoryInteraction(dismissedStory, 'Dismissed'));
        }
        await _excludeStoryCategory(category);
        await _stopOptionalStory();
        await _acknowledgeStoryControl(
          'I will leave out optional $category stories.',
        );
        return true;
      case RoverStoryControlAction.tellMore:
        final expandedStory =
            _activeScheduledStory ??
            _interruptedScheduledStory ??
            _lastCompletedScheduledStory;
        if (expandedStory != null) {
          unawaited(_recordStoryInteraction(expandedStory, 'TellMore'));
        }
        return false;
      case RoverStoryControlAction.currentLocalInformation:
      case RoverStoryControlAction.none:
        return false;
    }
  }

  Future<void> _stopOptionalStory() async {
    _playbackGeneration++;
    _activeScheduledStory = null;
    _interruptedScheduledStory = null;
    await _premiumVoice?.stop();
    await _textToSpeech.stop();
    _activeAudioPriority = 0;
    _setState(RoverAudioState.idle);
  }

  Future<void> _acknowledgeStoryControl(String text) async {
    _captionText = text;
    await _speakAnswer(
      text,
      priority: _userRequestedPriority,
      purpose: 'AskRoverAnswer',
      localOnly: true,
    );
  }

  Future<void> _includeStoryCategory(String category) async {
    final controller = _preferencesController;
    if (controller == null) return;
    final preferences = controller.preferences;
    final interests = {...preferences.interests, category}.toList()..sort();
    final excluded = preferences.excludedStoryCategories
        .where((item) => item.toLowerCase() != category.toLowerCase())
        .toList();
    await controller.save(
      preferences.copyWith(
        interests: interests,
        excludedStoryCategories: excluded,
      ),
    );
  }

  Future<void> _excludeStoryCategory(String category) async {
    final controller = _preferencesController;
    if (controller == null) return;
    final preferences = controller.preferences;
    final excluded = {...preferences.excludedStoryCategories, category}.toList()
      ..sort();
    await controller.save(
      preferences.copyWith(
        interests: preferences.interests
            .where((item) => item.toLowerCase() != category.toLowerCase())
            .toList(),
        excludedStoryCategories: excluded,
      ),
    );
  }

  String get _effectiveStoryDensity {
    if (_temporaryQuietActive) return 'quiet';
    return (_preferencesController?.preferences.storyDensity ?? 'Highlights')
        .trim()
        .toLowerCase();
  }

  bool get _temporaryQuietActive {
    final until = _storiesQuietUntil;
    if (until == null) return false;
    if (!DateTime.now().isBefore(until)) {
      _storiesQuietUntil = null;
      return false;
    }
    return true;
  }

  String? get _currentStoryCategory {
    final recordedCategory =
        (_activeScheduledStory ??
                _interruptedScheduledStory ??
                _lastCompletedScheduledStory)
            ?.category;
    if (recordedCategory != null) return recordedCategory;
    return switch (_lastJourneyNarration?.kind.toLowerCase()) {
      'localhistory' => 'history',
      'weatherortimecontext' => 'weather',
      'funfact' => 'unusual facts',
      'nearbylandmark' => 'local history',
      _ => null,
    };
  }

  Future<String?> _resolveInteractionProfileId() {
    final resolver = _interactionProfileIdResolver;
    if (resolver == null ||
        !(_onDeviceAiCoordinator?.storyControlsEnabled ?? false)) {
      return Future<String?>.value(null);
    }
    return _interactionProfileId ??= resolver().catchError((Object error) {
      FieldDiagnostics.instance.record('memory', 'profile unavailable: $error');
      return null;
    });
  }

  Future<void> _recordStoryInteraction(
    _ScheduledJourneyStory story,
    String kind,
  ) async {
    final profileId = await _resolveInteractionProfileId();
    if (profileId == null) return;
    try {
      final now = DateTime.now().toUtc();
      await walkRepository.recordStoryInteraction(
        profileId,
        StoryInteractionRequest(
          eventId:
              '${story.storyId}:${kind.toLowerCase()}:${now.microsecondsSinceEpoch}',
          storyId: story.storyId,
          category: story.category,
          kind: kind,
          occurredAtUtc: now,
        ),
      );
    } on Object catch (error) {
      FieldDiagnostics.instance.record(
        'memory',
        'story interaction not recorded kind=$kind error=$error',
      );
    }
  }

  static String _categoryForNarrationKind(String kind) {
    return switch (kind.toLowerCase()) {
      'localhistory' => 'history',
      'weatherortimecontext' => 'weather',
      'funfact' => 'unusual-facts',
      'approachingstop' || 'arrivalstory' => 'route-stops',
      _ => 'local-places',
    };
  }

  static bool _stopAudioCacheEligible(RoverStop stop) {
    final providers = <String>[
      stop.discoveryProviderName ?? '',
      stop.contentSource ?? '',
      ...stop.requiredAttribution,
    ].join(' ').toLowerCase();
    return !providers.contains('google') &&
        !providers.contains('weather') &&
        !providers.contains('event');
  }

  String _shortVersionOf(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return '';
    final end = RegExp(r'[.!?](?:\s|$)').firstMatch(trimmed)?.end;
    final sentence = end == null ? trimmed : trimmed.substring(0, end).trim();
    return sentence.length <= 220
        ? sentence
        : '${sentence.substring(0, 217).trimRight()}...';
  }

  bool get _arrivalAudioGateActive {
    final gateUntil = _arrivalAudioGateUntil;
    if (gateUntil == null) {
      return false;
    }

    if (DateTime.now().isAfter(gateUntil)) {
      _arrivalAudioGateUntil = null;
      return false;
    }

    return true;
  }

  bool _isArrivalSensitiveSession(RoamSession session) {
    if (session.hasPendingArrivalNarration(
      hasNarrated: (id) =>
          _autoNarratedStopKeys.contains('${session.apiWalkSessionId}:$id'),
    )) {
      return true;
    }

    final distanceToNext = session.distanceToNextStopMeters;
    if (distanceToNext != null &&
        distanceToNext <= session.storyArrivalBoundaryMeters) {
      return true;
    }

    return false;
  }

  bool _isReservedArrivalDecision(
    JourneyNarrationDecision decision,
    RoamSession session,
  ) {
    if (decision.kind == 'ApproachingStop' || decision.kind == 'ArrivalStory') {
      return true;
    }

    final placeId = decision.placeId;
    if (placeId == null || placeId.trim().isEmpty) {
      return false;
    }
    return _normalizePlaceIdentity(placeId) ==
        _normalizePlaceIdentity(session.currentStop.id);
  }

  static String _normalizePlaceIdentity(String value) {
    final normalized = value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    final googlePlaceId = normalized.indexOf('chij');
    return googlePlaceId < 0 ? normalized : normalized.substring(googlePlaceId);
  }

  bool _canStartPriority(int priority) {
    if (_state != RoverAudioState.speakingAnswer &&
        _state != RoverAudioState.preparingNarration &&
        _state != RoverAudioState.speakingNarration) {
      return true;
    }
    if (priority < _activeAudioPriority) {
      return false;
    }
    return true;
  }

  int get _cooldownRemainingSeconds {
    final cooldown = _nextJourneyNarrationAllowedAt;
    if (cooldown == null) {
      return 0;
    }
    return cooldown.difference(DateTime.now()).inSeconds.clamp(0, 9999);
  }

  static int _priorityFor(String value) {
    return switch (value) {
      'Safety' => _safetyPriority,
      'Navigation' => _navigationPriority,
      'Arrival' => _arrivalPriority,
      'ApproachingStop' => _approachingStopPriority,
      'UserRequested' => _userRequestedPriority,
      'FunFact' => _funFactPriority,
      _ => _contextualPriority,
    };
  }

  List<String> _segmentsFor(
    RoverStop stop, {
    bool withArrivalAnnouncement = false,
  }) {
    final source = (stop.narration?.trim().isNotEmpty ?? false)
        ? stop.narration!.trim()
        : '${stop.name}. ${stop.shortDescription}';
    final segments = source
        .split(RegExp(r'(?<=[.!?])\s+'))
        .map((segment) => segment.trim())
        .where((segment) => segment.isNotEmpty)
        .toList(growable: false);
    if (!withArrivalAnnouncement) {
      return segments;
    }

    return <String>['You have arrived at ${stop.name}.', ...segments];
  }

  static List<String> _storySegments(String narration) {
    final segments = narration
        .split(RegExp(r'(?<=[.!?])\s+'))
        .map((segment) => segment.trim())
        .where((segment) => segment.isNotEmpty)
        .toList(growable: false);
    return segments.isEmpty ? <String>[narration.trim()] : segments;
  }

  Future<void> _prefetchUpcomingNarration(RoamSession session) async {
    final premiumVoice = _premiumVoice;
    final walkSessionId = session.apiWalkSessionId;
    if (premiumVoice == null ||
        walkSessionId == null ||
        session.status != RoamSessionStatus.active ||
        session.isOffRoute ||
        _isArrivalSensitiveSession(session) ||
        (session.navigationGuidance?.distanceMeters ?? 9999) <= 45) {
      return;
    }

    final stop = session.currentStop;
    if (session.completedStopIds.contains(stop.id)) {
      return;
    }

    final distance = session.distanceToNextStopMeters;
    if (distance != null && distance > 220) {
      return;
    }

    final segments = _segmentsFor(stop);
    if (segments.isEmpty) {
      return;
    }

    final key = '$walkSessionId:${stop.id}:${segments.first.hashCode}';
    if (_prefetchedStopKeys.contains(key)) {
      return;
    }
    _prefetchedStopKeys.add(key);
    await premiumVoice.prefetch(
      text: segments.first,
      purpose: 'StopNarration',
      stopId: stop.id,
      audioCacheEligible: _stopAudioCacheEligible(stop),
    );
  }

  void _setState(RoverAudioState value) {
    _state = value;
    if (value != RoverAudioState.error) {
      _errorMessage = null;
    }
    _notify();
  }

  void _notify() {
    if (!_isDisposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    unawaited(_speechRecognizer.cancel());
    unawaited(_textToSpeech.dispose());
    super.dispose();
  }
}

Future<bool> openRoverMicrophoneSettings() {
  return openNativeVoiceSettings();
}

class _ScheduledJourneyStory {
  const _ScheduledJourneyStory({
    required this.storyId,
    required this.walkSessionId,
    required this.routeRevision,
    required this.text,
    required this.factIds,
    required this.origin,
    required this.expiresUtc,
    required this.estimatedDurationSeconds,
    required this.priority,
    required this.cooldownSeconds,
    required this.category,
    required this.audioCacheEligible,
  });

  final String storyId;
  final String walkSessionId;
  final int routeRevision;
  final String text;
  final Set<String> factIds;
  final RoverLatLng origin;
  final DateTime expiresUtc;
  final int estimatedDurationSeconds;
  final int priority;
  final int cooldownSeconds;
  final String category;
  final bool audioCacheEligible;
}

class _AdaptiveRouteStoryPlayback {
  _AdaptiveRouteStoryPlayback({
    required this.selection,
    required this.walkSessionId,
    required this.routeRevision,
    required this.segments,
  });

  final AdaptiveRouteStorySelection selection;
  final String walkSessionId;
  final int routeRevision;
  final List<String> segments;
  int segmentIndex = 0;
  bool wasInterrupted = false;
  bool userPaused = false;
}

class JourneyNarrationDiagnostics {
  const JourneyNarrationDiagnostics({
    required this.kind,
    required this.priority,
    required this.reason,
    required this.factIds,
    required this.cacheStatus,
    required this.generationLatencyMs,
    required this.played,
    required this.staleJobs,
    required this.cooldownRemainingSeconds,
    this.skippedReason,
  });

  final String kind;
  final String priority;
  final String reason;
  final List<String> factIds;
  final String cacheStatus;
  final int generationLatencyMs;
  final bool played;
  final int staleJobs;
  final int cooldownRemainingSeconds;
  final String? skippedReason;

  String get summary {
    final ids = factIds.isEmpty ? 'none' : factIds.take(2).join(', ');
    return [
      'Narration: $kind',
      'priority $priority',
      'facts $ids',
      'latency ${generationLatencyMs}ms',
      played ? 'played' : 'not played',
      if (cooldownRemainingSeconds > 0) 'cooldown ${cooldownRemainingSeconds}s',
      if (staleJobs > 0) 'stale jobs $staleJobs',
      ?skippedReason,
      if (reason.isNotEmpty) reason,
    ].join('; ');
  }

  JourneyNarrationDiagnostics copyWith({bool? played, String? skippedReason}) {
    return JourneyNarrationDiagnostics(
      kind: kind,
      priority: priority,
      reason: reason,
      factIds: factIds,
      cacheStatus: cacheStatus,
      generationLatencyMs: generationLatencyMs,
      played: played ?? this.played,
      staleJobs: staleJobs,
      cooldownRemainingSeconds: cooldownRemainingSeconds,
      skippedReason: skippedReason ?? this.skippedReason,
    );
  }

  factory JourneyNarrationDiagnostics.fromDecision(
    JourneyNarrationDecision decision, {
    required Duration latency,
    required int staleJobs,
    required bool played,
    String? skippedReason,
  }) {
    return JourneyNarrationDiagnostics(
      kind: decision.kind,
      priority: decision.priority,
      reason: decision.warnings.take(2).join(' '),
      factIds: decision.factIdsUsed,
      cacheStatus: decision.sourceReferences.isEmpty ? 'none' : 'sources',
      generationLatencyMs: latency.inMilliseconds,
      played: played,
      staleJobs: staleJobs,
      cooldownRemainingSeconds: decision.cooldownSeconds,
      skippedReason: skippedReason,
    );
  }
}
