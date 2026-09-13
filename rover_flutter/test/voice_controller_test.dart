import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:rover/src/active_roam/active_roam_session.dart';
import 'package:rover/src/adventure/roam.dart';
import 'package:rover/src/api/adaptation_models.dart';
import 'package:rover/src/api/adaptive_route_story_models.dart';
import 'package:rover/src/api/ask_rover_models.dart';
import 'package:rover/src/api/journey_narration_models.dart';
import 'package:rover/src/api/local_discovery_options.dart';
import 'package:rover/src/api/location_update_models.dart';
import 'package:rover/src/api/location_story_models.dart';
import 'package:rover/src/api/location_observation_models.dart';
import 'package:rover/src/api/profile_models.dart';
import 'package:rover/src/api/speech_models.dart';
import 'package:rover/src/api/walk_models.dart';
import 'package:rover/src/api/walk_repository.dart';
import 'package:rover/src/location/rover_location.dart';
import 'package:rover/src/on_device_ai/rover_on_device_ai_coordinator.dart';
import 'package:rover/src/preferences/preferences_controller.dart';
import 'package:rover/src/preferences/preferences_repository.dart';
import 'package:rover/src/voice/rover_audio_services.dart';
import 'package:rover/src/voice/rover_premium_voice.dart';
import 'package:rover/src/voice/rover_voice_controller.dart';
import 'package:rover/src/voice/rover_voice_state.dart';

void main() {
  test('departure instruction is not an imminent story interruption', () async {
    final controller = RoverVoiceController(
      walkRepository: FakeVoiceWalkRepository(),
      textToSpeech: FakeTextToSpeech(),
      speechRecognizer: FakeSpeechRecognizer(),
      audioSession: FakeAudioSession(),
    );
    final base = _session();
    final session = base.copyWith(
      distanceToNextStopMeters: 500,
      routeProgressPercentage: 0,
      roam: base.roam.copyWith(
        routeProvider: 'GoogleRoutes',
        routeManeuvers: const [
          RoverRouteManeuver(
            sequenceNumber: 1,
            instruction: 'Head north',
            distanceMeters: 120,
            durationMinutes: 2,
            maneuverType: 'DEPART',
          ),
          RoverRouteManeuver(
            sequenceNumber: 2,
            instruction: 'Turn right',
            distanceMeters: 100,
            durationMinutes: 2,
            maneuverType: 'TURN_RIGHT',
          ),
        ],
      ),
    );
    expect(session.navigationGuidance?.distanceMeters, 0);
    expect(session.storyNavigationGuidance?.distanceMeters, 120);
    expect(
      controller.canPlayAdaptiveRouteStory(_adaptiveSelection(), session),
      isTrue,
    );
    final nearTurn = session.copyWith(routeProgressPercentage: 100 / 220 * 100);
    expect(nearTurn.storyNavigationGuidance?.distanceMeters, 20);
    expect(
      controller.canPlayAdaptiveRouteStory(_adaptiveSelection(), nearTurn),
      isFalse,
    );
    controller.dispose();
  });
  test(
    'short story plays at 95 metres but arrival boundary stays protected',
    () async {
      final tts = FakeTextToSpeech();
      final controller = RoverVoiceController(
        walkRepository: FakeVoiceWalkRepository(),
        textToSpeech: tts,
        speechRecognizer: FakeSpeechRecognizer(),
        audioSession: FakeAudioSession(),
      );
      final session = _session().copyWith(
        distanceToNextStopMeters: 95,
        currentGpsAccuracyMeters: 8,
      );
      expect(session.storyArrivalBoundaryMeters, 48);
      expect(session.storySecondsUntilInterruption, 36);
      expect(
        await controller.playAdaptiveRouteStory(_adaptiveSelection(), session),
        isTrue,
      );
      expect(tts.spoken.join(' '), 'First fact. Second fact.');
      expect(
        controller.canPlayAdaptiveRouteStory(
          _adaptiveSelection(),
          session.copyWith(distanceToNextStopMeters: 48),
        ),
        isFalse,
      );
      expect(
        controller.canPlayAdaptiveRouteStory(
          _adaptiveSelection(),
          session.copyWith(distanceToNextStopMeters: 65),
        ),
        isFalse,
      );
      controller.dispose();
    },
  );
  test(
    'remembered arrival stops blocking stories after leaving geofence',
    () async {
      final controller = RoverVoiceController(
        walkRepository: FakeVoiceWalkRepository(),
        textToSpeech: FakeTextToSpeech(),
        speechRecognizer: FakeSpeechRecognizer(),
        audioSession: FakeAudioSession(),
      );
      final near = _session(completedStopIds: {'stop-1'}).copyWith(
        recentNarrationStopId: 'stop-1',
        distanceToNextStopMeters: 500,
      );
      expect(near.isNearRecentNarrationStop, isTrue);
      expect(
        controller.canPlayAdaptiveRouteStory(_adaptiveSelection(), near),
        isFalse,
      );
      final away = near.copyWith(
        simulatedLocation: const RoverLatLng(
          latitude: 37.798,
          longitude: -122.4075,
        ),
      );
      expect(away.recentNarrationStop, isNotNull);
      expect(away.isNearRecentNarrationStop, isFalse);
      expect(
        controller.canPlayAdaptiveRouteStory(_adaptiveSelection(), away),
        isTrue,
      );
      expect(
        controller.canPlayAdaptiveRouteStory(
          _adaptiveSelection(),
          away.copyWith(arrivalCandidate: true),
        ),
        isFalse,
      );
      controller.dispose();
    },
  );
  test('adaptive prefetch prepares audio without speaking', () async {
    final repository = FakeVoiceWalkRepository();
    final premium = SuccessfulPremiumVoiceCoordinator(repository);
    final tts = FakeTextToSpeech();
    final controller = RoverVoiceController(
      walkRepository: repository,
      premiumVoice: premium,
      textToSpeech: tts,
      speechRecognizer: FakeSpeechRecognizer(),
      audioSession: FakeAudioSession(),
    );
    await controller.prefetchAdaptiveRouteStory(_adaptiveSelection().story);
    expect(premium.prefetched, ['First fact.']);
    expect(premium.spoken, isEmpty);
    expect(tts.spoken, isEmpty);
    controller.dispose();
  });
  test('narration triggers once after confirmed arrival', () async {
    final tts = FakeTextToSpeech();
    final narratedStops = <String>[];
    final controller = RoverVoiceController(
      walkRepository: FakeVoiceWalkRepository(),
      textToSpeech: tts,
      speechRecognizer: FakeSpeechRecognizer(),
      audioSession: FakeAudioSession(),
      onArrivalNarrated: (stopId) async => narratedStops.add(stopId),
    );
    final session = _session(arrived: true, completedStopIds: {'stop-1'});

    await controller.syncWithSession(session);
    await controller.syncWithSession(session);

    expect(tts.spoken.length, 3);
    expect(tts.spoken.first, contains('You have arrived at Union Square.'));
    expect(tts.spoken[1], contains('Welcome to Union Square.'));
    expect(narratedStops, ['stop-1']);
    controller.dispose();
  });

  test(
    'persisted arrival marker survives voice controller recreation',
    () async {
      final tts = FakeTextToSpeech();
      final controller = RoverVoiceController(
        walkRepository: FakeVoiceWalkRepository(),
        textToSpeech: tts,
        speechRecognizer: FakeSpeechRecognizer(),
        audioSession: FakeAudioSession(),
      );
      final session = _session(arrived: true, completedStopIds: {'stop-1'})
          .copyWith(
            recentNarrationStopId: 'stop-1',
            recentNarrationStopOverride: _stop,
            narratedArrivalStopIds: {'stop-1'},
          );

      await controller.syncWithSession(session);

      expect(tts.spoken, isEmpty);
      controller.dispose();
    },
  );

  test('no narration before confirmed arrival', () async {
    final tts = FakeTextToSpeech();
    final controller = RoverVoiceController(
      walkRepository: FakeVoiceWalkRepository(),
      textToSpeech: tts,
      speechRecognizer: FakeSpeechRecognizer(),
      audioSession: FakeAudioSession(),
    );

    await controller.syncWithSession(_session());

    expect(tts.spoken, isEmpty);
    controller.dispose();
  });

  test('Google maneuver is spoken once at the turn', () async {
    final tts = FakeTextToSpeech();
    final controller = RoverVoiceController(
      walkRepository: FakeVoiceWalkRepository(),
      textToSpeech: tts,
      speechRecognizer: FakeSpeechRecognizer(),
      audioSession: FakeAudioSession(),
    );
    final session = _googleNavigationSession();

    await controller.syncWithSession(session);
    await controller.syncWithSession(session);

    expect(tts.spoken, ['Turn left onto Main Street']);
    controller.dispose();
  });

  test('Google maneuver waits while arrival is active', () async {
    final tts = FakeTextToSpeech();
    final controller = RoverVoiceController(
      walkRepository: FakeVoiceWalkRepository(),
      textToSpeech: tts,
      speechRecognizer: FakeSpeechRecognizer(),
      audioSession: FakeAudioSession(),
    );
    final session = _googleNavigationSession().copyWith(
      arrivalCandidate: true,
      arrivalCandidateStopId: 'stop-1',
    );

    await controller.syncWithSession(session);

    expect(tts.spoken, isEmpty);
    controller.dispose();
  });

  test('selected location story never speaks a mismatched place', () async {
    final tts = FakeTextToSpeech();
    final repository = MismatchedLocationStoryRepository();
    final controller = RoverVoiceController(
      walkRepository: repository,
      textToSpeech: tts,
      speechRecognizer: FakeSpeechRecognizer(),
      audioSession: FakeAudioSession(),
    );

    await controller.tellLocationStory(
      location: const RoverLatLng(latitude: 44.678, longitude: -76.395),
      routeId: null,
      routeGeometry: const [],
      selectedPlaceId: 'woodfired-cafe',
      selectedPlaceName: 'The Woodfired Cafe',
      selectedPlaceFallbackNarration:
          'The Woodfired Cafe. A cafe in Westport with sourced map context.',
      label: 'Camera Explorer',
    );

    expect(repository.lastRequest?.selectedPlaceIds, ['woodfired-cafe']);
    expect(tts.spoken, hasLength(1));
    expect(tts.spoken.single, contains('The Woodfired Cafe'));
    expect(tts.spoken.single, isNot(contains('Westport is a town')));
    controller.dispose();
  });

  test('manual camera story does not consume automatic arrival', () async {
    final tts = FakeTextToSpeech();
    final controller = RoverVoiceController(
      walkRepository: MismatchedLocationStoryRepository(),
      textToSpeech: tts,
      speechRecognizer: FakeSpeechRecognizer(),
      audioSession: FakeAudioSession(),
    );

    await controller.tellLocationStory(
      location: const RoverLatLng(latitude: 44.678, longitude: -76.395),
      routeId: 'walk-1',
      routeGeometry: const [],
      selectedPlaceId: 'stop-1',
      selectedPlaceName: 'Union Square',
      selectedPlaceFallbackNarration: 'Union Square camera story.',
      label: 'Camera Explorer',
    );
    await controller.syncWithSession(
      _session(arrived: true, completedStopIds: {'stop-1'}).copyWith(
        recentNarrationStopId: 'stop-1',
        recentNarrationStopOverride: _stop,
      ),
    );

    expect(
      tts.spoken.where((text) => text.contains('You have arrived')),
      hasLength(1),
    );
    controller.dispose();
  });

  test('upcoming stop journey result is reserved for arrival', () async {
    final tts = FakeTextToSpeech();
    final repository = ReservedArrivalVoiceWalkRepository();
    final controller = RoverVoiceController(
      walkRepository: repository,
      textToSpeech: tts,
      speechRecognizer: FakeSpeechRecognizer(),
      audioSession: FakeAudioSession(),
    );
    final session = _session().copyWith(
      simulatedLocation: const RoverLatLng(
        latitude: 37.7902,
        longitude: -122.4075,
      ),
    );

    await controller.considerJourneyNarration(session);

    expect(repository.evaluationCount, 1);
    expect(tts.spoken, isEmpty);
    expect(
      controller.lastJourneyNarration?.skippedReason,
      contains('reserved for geofence entry'),
    );
    controller.dispose();
  });

  test(
    'precise geofence entry candidate narrates once before confirmation',
    () async {
      final tts = FakeTextToSpeech();
      final controller = RoverVoiceController(
        walkRepository: FakeVoiceWalkRepository(),
        textToSpeech: tts,
        speechRecognizer: FakeSpeechRecognizer(),
        audioSession: FakeAudioSession(),
      );
      final session = _session().copyWith(
        arrivalCandidate: true,
        arrivalCandidateReadingCount: 1,
        arrivalCandidateStopId: 'stop-1',
        recentNarrationStopId: 'stop-1',
        recentNarrationStopOverride: _stop,
      );

      await controller.syncWithSession(session);
      await controller.syncWithSession(session);

      expect(tts.spoken.length, 3);
      expect(tts.spoken.first, contains('You have arrived at Union Square.'));

      await controller.syncWithSession(
        session.copyWith(completedStopIds: {'stop-1'}),
      );

      expect(tts.spoken.length, 3);
      controller.dispose();
    },
  );

  test('overlapping geofence syncs cannot restart arrival narration', () async {
    final tts = BlockingTextToSpeech();
    final controller = RoverVoiceController(
      walkRepository: FakeVoiceWalkRepository(),
      textToSpeech: tts,
      speechRecognizer: FakeSpeechRecognizer(),
      audioSession: FakeAudioSession(),
    );
    final session = _session(completedStopIds: {'stop-1'}).copyWith(
      arrivalCandidate: true,
      arrivalCandidateReadingCount: 1,
      arrivalCandidateStopId: 'stop-1',
      recentNarrationStopId: 'stop-1',
      recentNarrationStopOverride: _stop,
    );

    final firstSync = controller.syncWithSession(session);
    await tts.firstSpeakStarted.future;
    await controller.syncWithSession(session);

    expect(tts.spoken, hasLength(1));
    tts.releaseFirstSpeak.complete();
    await firstSync;

    expect(tts.spoken, hasLength(3));
    expect(
      tts.spoken.where((text) => text.contains('You have arrived')),
      hasLength(1),
    );
    controller.dispose();
  });

  test(
    'route revisions preserve active arrival without repeating it',
    () async {
      final tts = BlockingTextToSpeech();
      final narrated = <String>[];
      final controller = RoverVoiceController(
        walkRepository: FakeVoiceWalkRepository(),
        textToSpeech: tts,
        speechRecognizer: FakeSpeechRecognizer(),
        audioSession: FakeAudioSession(),
        onArrivalNarrated: (id) async {
          narrated.add(id);
        },
      );
      final session = _session(completedStopIds: {'stop-1'}).copyWith(
        routeRevision: 1,
        arrivalCandidate: true,
        arrivalCandidateStopId: 'stop-1',
        recentNarrationStopId: 'stop-1',
        recentNarrationStopOverride: _stop,
      );
      final firstSync = controller.syncWithSession(session);
      await tts.firstSpeakStarted.future;
      final stopsBefore = tts.stopCount;
      await controller.syncWithSession(session.copyWith(routeRevision: 2));
      await controller.syncWithSession(session.copyWith(routeRevision: 3));
      expect(tts.stopCount, stopsBefore);
      tts.releaseFirstSpeak.complete();
      await firstSync;
      await controller.syncWithSession(session.copyWith(routeRevision: 3));
      expect(tts.spoken, hasLength(3));
      expect(
        tts.spoken.where((text) => text.contains('You have arrived')),
        hasLength(1),
      );
      expect(narrated, ['stop-1']);
      controller.dispose();
    },
  );

  test('failed arrival playback remains eligible for retry', () async {
    final tts = FailOnceTextToSpeech();
    final controller = RoverVoiceController(
      walkRepository: FakeVoiceWalkRepository(),
      textToSpeech: tts,
      speechRecognizer: FakeSpeechRecognizer(),
      audioSession: FakeAudioSession(),
    );
    final session = _session(completedStopIds: {'stop-1'}).copyWith(
      arrivalCandidate: true,
      arrivalCandidateReadingCount: 1,
      arrivalCandidateStopId: 'stop-1',
      recentNarrationStopId: 'stop-1',
      recentNarrationStopOverride: _stop,
    );

    await controller.syncWithSession(session);
    await controller.syncWithSession(session);

    expect(tts.attempts, 4);
    expect(
      tts.spoken.where((text) => text.contains('You have arrived')),
      hasLength(1),
    );
    controller.dispose();
  });

  test('play pause resume replay and stop drive TTS safely', () async {
    final tts = FakeTextToSpeech();
    final controller = RoverVoiceController(
      walkRepository: FakeVoiceWalkRepository(),
      textToSpeech: tts,
      speechRecognizer: FakeSpeechRecognizer(),
      audioSession: FakeAudioSession(),
    );

    await controller.playNarration(_stop);
    await controller.pauseNarration();
    await controller.resumeNarration();
    await controller.replayNarration(_stop);
    await controller.stopAll();

    expect(tts.stopCount, greaterThanOrEqualTo(2));
    expect(tts.spoken, isNotEmpty);
    expect(controller.state, RoverAudioState.idle);
    controller.dispose();
  });

  test('Ask Rover interruption submits once and speaks answer', () async {
    final tts = FakeTextToSpeech();
    final speech = FakeSpeechRecognizer(transcript: 'Why are we here?');
    final repository = FakeVoiceWalkRepository();
    final controller = RoverVoiceController(
      walkRepository: repository,
      textToSpeech: tts,
      speechRecognizer: speech,
      audioSession: FakeAudioSession(),
    );

    await controller.playNarration(_stop);
    await controller.acceptPrivacyAndAsk(
      _session(arrived: true, completedStopIds: {'stop-1'}),
    );
    await Future<void>.delayed(Duration.zero);

    expect(repository.askCount, 1);
    expect(controller.lastTurn?.answerText, contains('Because'));
    expect(tts.spoken.last, contains('Because'));
    expect(controller.state, RoverAudioState.narrationPaused);
    controller.dispose();
  });

  test(
    'quiet and resume story controls stay local and preserve guidance',
    () async {
      final repository = FakeVoiceWalkRepository();
      final preferences = PreferencesController(MemoryPreferencesRepository());
      await preferences.load();
      final controller = RoverVoiceController(
        walkRepository: repository,
        textToSpeech: FakeTextToSpeech(),
        speechRecognizer: FakeSpeechRecognizer(),
        audioSession: FakeAudioSession(),
        preferencesController: preferences,
      );

      await controller.applyStoryControl(
        const RoverStoryControlCommand(RoverStoryControlAction.quietTenMinutes),
      );

      expect(controller.storiesAreQuiet, isTrue);
      expect(controller.storiesQuietUntil, isNotNull);
      expect(repository.askCount, 0);

      await controller.applyStoryControl(
        const RoverStoryControlCommand(RoverStoryControlAction.resumeStories),
      );

      expect(controller.storiesAreQuiet, isFalse);
      expect(controller.storiesQuietUntil, isNull);
      expect(repository.askCount, 0);
      controller.dispose();
    },
  );

  test('empty transcription leaves an error-safe state', () async {
    final controller = RoverVoiceController(
      walkRepository: FakeVoiceWalkRepository(),
      textToSpeech: FakeTextToSpeech(),
      speechRecognizer: FakeSpeechRecognizer(transcript: ''),
      audioSession: FakeAudioSession(),
    );

    await controller.acceptPrivacyAndAsk(_session());

    expect(controller.state, RoverAudioState.listening);
    await controller.cancelListening();
    expect(controller.state, RoverAudioState.idle);
    controller.dispose();
  });

  test('microphone denied reports an error', () async {
    final controller = RoverVoiceController(
      walkRepository: FakeVoiceWalkRepository(),
      textToSpeech: FakeTextToSpeech(),
      speechRecognizer: FakeSpeechRecognizer(
        permission: MicrophonePermissionState.denied,
      ),
      audioSession: FakeAudioSession(),
    );

    await controller.acceptPrivacyAndAsk(_session());

    expect(controller.state, RoverAudioState.error);
    expect(controller.errorMessage, contains('Microphone permission'));
    controller.dispose();
  });

  test('navigation interrupts premium story without starting Android fallback and safely resumes', () async {
    final repository = ScheduledVoiceWalkRepository();
    final tts = FakeTextToSpeech();
    final premium = BlockingPremiumVoiceCoordinator(repository);
    final controller = RoverVoiceController(
      walkRepository: repository,
      textToSpeech: tts,
      speechRecognizer: FakeSpeechRecognizer(),
      audioSession: FakeAudioSession(),
      premiumVoice: premium,
    );

    final storyPlayback = controller.considerJourneyNarration(_session());
    await premium.speakStarted.future;
    await controller.syncWithSession(_googleNavigationSession());
    premium.releaseSpeak.complete();
    await storyPlayback;

    expect(tts.spoken, ['Turn left onto Main Street']);
    expect(premium.stopCount, greaterThanOrEqualTo(2));

    await controller.considerJourneyNarration(_session());

    expect(repository.evaluationCount, 2);
    expect(tts.spoken.last, startsWith('Continuing the story.'));
    expect(
      tts.spoken.where((text) => text == 'A scheduled local story.'),
      isEmpty,
    );
    controller.dispose();
  });

  test('navigation interrupts an adaptive story and resumes at a sentence boundary', () async {
    final tts = BlockingTextToSpeech();
    final controller = RoverVoiceController(
      walkRepository: FakeVoiceWalkRepository(),
      textToSpeech: tts,
      speechRecognizer: FakeSpeechRecognizer(),
      audioSession: FakeAudioSession(),
      adaptiveRouteStoriesEnabled: true,
    );
    final selection = _adaptiveSelection();

    final playback = controller.playAdaptiveRouteStory(selection, _session());
    await tts.firstSpeakStarted.future;
    await controller.syncWithSession(_googleNavigationSession());
    tts.releaseFirstSpeak.complete();
    expect(await playback, isFalse);
    expect(
      controller.hasAutomaticallyResumableAdaptiveStory('adaptive-1'),
      isTrue,
    );

    expect(
      await controller.playAdaptiveRouteStory(selection, _session()),
      isTrue,
    );
    expect(tts.spoken[1], 'Turn left onto Main Street');
    expect(tts.spoken[2], startsWith('Continuing the story. First fact.'));
    expect(tts.spoken.last, 'Second fact.');
    controller.dispose();
  });

  test(
    'announced maneuver updates do not interrupt adaptive playback',
    () async {
      final tts = BlockingTextToSpeech(blockAt: 1);
      final controller = RoverVoiceController(
        walkRepository: FakeVoiceWalkRepository(),
        textToSpeech: tts,
        speechRecognizer: FakeSpeechRecognizer(),
        audioSession: FakeAudioSession(),
        adaptiveRouteStoriesEnabled: true,
      );
      await controller.syncWithSession(_googleNavigationSession());
      final playback = controller.playAdaptiveRouteStory(
        _adaptiveSelection(),
        _session(),
      );
      await tts.firstSpeakStarted.future;
      final stopsBefore = tts.stopCount;
      for (var i = 0; i < 3; i++) {
        await controller.syncWithSession(_googleNavigationSession());
      }
      expect(tts.stopCount, stopsBefore);
      expect(controller.hasInterruptedAdaptiveStory('adaptive-1'), isFalse);
      tts.releaseFirstSpeak.complete();
      expect(await playback, isTrue);
      expect(tts.spoken, [
        'Turn left onto Main Street',
        'First fact.',
        'Second fact.',
      ]);
      controller.dispose();
    },
  );

  test(
    'successful premium story never also invokes Android fallback',
    () async {
      final repository = ScheduledVoiceWalkRepository();
      final tts = FakeTextToSpeech();
      final premium = SuccessfulPremiumVoiceCoordinator(repository);
      final controller = RoverVoiceController(
        walkRepository: repository,
        textToSpeech: tts,
        speechRecognizer: FakeSpeechRecognizer(),
        audioSession: FakeAudioSession(),
        premiumVoice: premium,
      );

      await controller.considerJourneyNarration(_session());

      expect(premium.spoken, ['A scheduled local story.']);
      expect(tts.spoken, isEmpty);
      controller.dispose();
    },
  );
}

final _stop = RoverStop(
  id: 'stop-1',
  name: 'Union Square',
  image: 'mock://union',
  shortDescription: 'Public art and plaza history.',
  estimatedVisitMinutes: 10,
  coordinates: const RoverLatLng(latitude: 37.788, longitude: -122.4075),
  category: 'History',
  whySelected: 'It anchors the walk.',
  narration: 'Welcome to Union Square. Look around for the monument.',
  contentType: 'Landmark',
);

AdaptiveRouteStorySelection _adaptiveSelection() {
  final now = DateTime.utc(2026, 9, 7);
  return AdaptiveRouteStorySelection(
    story: AdaptiveRouteStory(
      storyId: 'adaptive-1',
      segmentId: 'segment-1',
      placeId: 'place-1',
      title: 'Two facts',
      intent: 'HiddenHistory',
      category: 'history',
      latitude: 37.788,
      longitude: -122.4075,
      opensAtRouteMeters: 0,
      closesAtRouteMeters: 500,
      variants: const [
        RouteStoryNarrationVariant(
          length: 'Standard',
          estimatedDurationSeconds: 20,
          narration: 'First fact. Second fact.',
          claimIds: [],
        ),
      ],
      claims: const [],
      sources: [
        RouteStorySource(
          sourceId: 'source-1',
          providerName: 'Wikipedia',
          attribution: 'Wikipedia',
          retrievedUtc: now,
          confidence: 0.9,
        ),
      ],
      evidenceScore: 0.9,
    ),
    variant: const RouteStoryNarrationVariant(
      length: 'Standard',
      estimatedDurationSeconds: 20,
      narration: 'First fact. Second fact.',
      claimIds: [],
    ),
    reason: 'test',
  );
}

RoamSession _session({
  bool arrived = false,
  Set<String> completedStopIds = const {},
}) {
  return RoamSession(
    roam: RoverRoam(
      title: 'Test',
      summary: 'Test walk',
      walkingMinutes: 10,
      distanceMiles: 0.2,
      startingPoint: 'Here',
      stops: [_stop],
      routeGeometry: [_stop.coordinates, _stop.coordinates],
      accessibilityNotes: const [],
      warnings: const [],
      routeProvider: 'Mock',
      walkSessionId: 'walk-1',
    ),
    status: RoamSessionStatus.active,
    currentStopIndex: 0,
    completedStopIds: completedStopIds,
    skippedStopIds: const {},
    simulatedLocation: _stop.coordinates,
    audioStatus: AudioPlaybackStatus.stopped,
    screenAwake: true,
    arrivedAtCurrentStop: arrived,
    apiWalkSessionId: 'walk-1',
  );
}

RoamSession _googleNavigationSession() {
  final session = _session();
  return session.copyWith(
    roam: session.roam.copyWith(
      routeProvider: 'GoogleRoutes',
      routeManeuvers: const [
        RoverRouteManeuver(
          sequenceNumber: 1,
          instruction: 'Turn left onto Main Street',
          distanceMeters: 120,
          durationMinutes: 2,
          maneuverType: 'TURN_LEFT',
        ),
      ],
    ),
    progressPercentage: 0,
  );
}

class FakeTextToSpeech implements RoverTextToSpeech {
  final spoken = <String>[];
  int stopCount = 0;
  int pauseCount = 0;

  @override
  Future<void> configure({required double rate}) async {}

  @override
  Future<void> dispose() async {}

  @override
  Future<void> pause() async {
    pauseCount++;
  }

  @override
  Future<void> speak(String text) async {
    spoken.add(text);
  }

  @override
  Future<void> stop() async {
    stopCount++;
  }
}

class BlockingTextToSpeech extends FakeTextToSpeech {
  BlockingTextToSpeech({this.blockAt = 0});
  final int blockAt;
  final firstSpeakStarted = Completer<void>();
  final releaseFirstSpeak = Completer<void>();

  @override
  Future<void> speak(String text) async {
    spoken.add(text);
    if (spoken.length == blockAt + 1 && !firstSpeakStarted.isCompleted) {
      firstSpeakStarted.complete();
      await releaseFirstSpeak.future;
    }
  }
}

class FailOnceTextToSpeech extends FakeTextToSpeech {
  int attempts = 0;

  @override
  Future<void> speak(String text) async {
    attempts++;
    if (attempts == 1) {
      throw StateError('simulated playback failure');
    }
    spoken.add(text);
  }
}

class FakeSpeechRecognizer implements RoverSpeechRecognizer {
  FakeSpeechRecognizer({
    this.transcript = 'What is this?',
    this.permission = MicrophonePermissionState.granted,
  });

  final String transcript;
  final MicrophonePermissionState permission;
  void Function(String text, bool finalResult)? _onResult;

  @override
  Future<void> cancel() async {}

  @override
  Future<MicrophonePermissionState> ensurePermission() async => permission;

  @override
  Future<bool> initialize({
    required void Function(String text, bool finalResult) onResult,
    required void Function(String message) onError,
  }) async {
    _onResult = onResult;
    return true;
  }

  @override
  Future<void> listen() async {
    _onResult?.call(transcript, true);
  }

  @override
  Future<void> stop() async {}
}

class FakeAudioSession implements RoverAudioSessionCoordinator {
  @override
  Future<void> configure() async {}
}

class ScheduledVoiceWalkRepository extends FakeVoiceWalkRepository {
  int evaluationCount = 0;

  @override
  Future<JourneyNarrationDecision> evaluateJourneyNarration(
    String walkSessionId,
    JourneyNarrationEvaluateRequest request,
  ) async {
    evaluationCount++;
    if (request.interruptedStoryId != null) {
      return const JourneyNarrationDecision(
        shouldNarrate: false,
        kind: 'QuietWalk',
        priority: 'ContextualStory',
        cooldownSeconds: 90,
        factIdsUsed: [],
        sourceReferences: [],
        warnings: [],
        schedulerApplied: true,
        scheduleAction: 'Resume',
        scheduleReason: 'The same story remains relevant.',
      );
    }

    return JourneyNarrationDecision(
      shouldNarrate: true,
      kind: 'LocalHistory',
      priority: 'ContextualStory',
      narrationText: 'A scheduled local story.',
      placeId: 'place-1',
      cooldownSeconds: 90,
      factIdsUsed: const ['fact-1'],
      sourceReferences: const [],
      warnings: const [],
      schedulerApplied: true,
      scheduleAction: 'Narrate',
      scheduleReason: 'The story fits before navigation.',
      storyId: 'story-1',
      storyExpiresUtc: DateTime.now().toUtc().add(const Duration(minutes: 5)),
      estimatedDurationSeconds: 20,
    );
  }
}

class ReservedArrivalVoiceWalkRepository extends FakeVoiceWalkRepository {
  int evaluationCount = 0;

  @override
  Future<JourneyNarrationDecision> evaluateJourneyNarration(
    String walkSessionId,
    JourneyNarrationEvaluateRequest request,
  ) async {
    evaluationCount++;
    return const JourneyNarrationDecision(
      shouldNarrate: true,
      kind: 'NearbyLandmark',
      priority: 'ContextualStory',
      narrationText: 'Union Square is the next stop.',
      placeId: 'stop-1',
      cooldownSeconds: 90,
      factIdsUsed: ['stop-1:identity'],
      sourceReferences: [],
      warnings: [],
    );
  }
}

class BlockingPremiumVoiceCoordinator extends RoverPremiumVoiceCoordinator {
  BlockingPremiumVoiceCoordinator(WalkRepository repository)
    : super(walkRepository: repository);

  final speakStarted = Completer<void>();
  final releaseSpeak = Completer<void>();
  int stopCount = 0;

  @override
  Future<void> prefetch({
    required String text,
    required String purpose,
    String? walkSessionId,
    String? stopId,
    bool audioCacheEligible = false,
    DateTime? cacheExpiresUtc,
    String? storyId,
    String? variantId,
  }) async {}

  @override
  Future<bool> speak({
    required String text,
    required String purpose,
    String? walkSessionId,
    String? stopId,
    bool audioCacheEligible = false,
    DateTime? cacheExpiresUtc,
    String? storyId,
    String? variantId,
  }) async {
    if (!speakStarted.isCompleted) {
      speakStarted.complete();
      await releaseSpeak.future;
      return false;
    }
    return false;
  }

  @override
  Future<void> stop() async {
    stopCount++;
  }
}

class SuccessfulPremiumVoiceCoordinator extends RoverPremiumVoiceCoordinator {
  SuccessfulPremiumVoiceCoordinator(WalkRepository repository)
    : super(walkRepository: repository);

  final spoken = <String>[];
  final prefetched = <String>[];

  @override
  Future<void> prefetch({
    required String text,
    required String purpose,
    String? walkSessionId,
    String? stopId,
    bool audioCacheEligible = false,
    DateTime? cacheExpiresUtc,
    String? storyId,
    String? variantId,
  }) async {
    prefetched.add(text);
  }

  @override
  Future<bool> speak({
    required String text,
    required String purpose,
    String? walkSessionId,
    String? stopId,
    bool audioCacheEligible = false,
    DateTime? cacheExpiresUtc,
    String? storyId,
    String? variantId,
  }) async {
    spoken.add(text);
    return true;
  }

  @override
  Future<void> stop() async {}
}

class FakeVoiceWalkRepository implements WalkRepository {
  int askCount = 0;

  @override
  Future<GuestProfile> createOrGetGuestProfile(String installationId) {
    throw UnimplementedError();
  }

  @override
  Future<GuestProfile> updateProfilePreferences(
    String profileId,
    UpdateProfilePreferencesRequest request,
  ) {
    throw UnimplementedError();
  }

  @override
  Future<GuestProfile> saveDiscovery(
    String profileId,
    SaveDiscoveryRequest request,
  ) {
    throw UnimplementedError();
  }

  @override
  Future<void> recordStoryInteraction(
    String profileId,
    StoryInteractionRequest request,
  ) async {}

  @override
  Future<void> deleteProfile(String profileId) {
    throw UnimplementedError();
  }

  @override
  Future<RenderedSpeechAudio> renderSpeech(RenderSpeechRequest request) {
    return Future.value(
      const RenderedSpeechAudio(
        bytes: [1, 2, 3],
        contentType: 'audio/mpeg',
        provider: 'Test',
        cacheStatus: 'miss',
        usedFallback: false,
      ),
    );
  }

  @override
  Future<AskRoverResponse> askRover(
    String walkSessionId,
    AskRoverRequest request,
  ) async {
    askCount++;
    return AskRoverResponse.fromJson({
      'conversationId': request.conversationId ?? 'conv-1',
      'turnId': 'turn-1',
      'answerText': 'Because this stop anchors the current walk.',
      'createdAtUtc': '2026-08-27T15:00:00Z',
      'currentStopId': request.currentStopId,
      'provider': 'Mock',
      'suggestedAction': 'Informational',
      'safetyNotice': null,
    });
  }

  @override
  Future<JourneyNarrationDecision> evaluateJourneyNarration(
    String walkSessionId,
    JourneyNarrationEvaluateRequest request,
  ) async {
    return const JourneyNarrationDecision(
      shouldNarrate: false,
      kind: 'QuietWalk',
      priority: 'ContextualStory',
      cooldownSeconds: 90,
      factIdsUsed: [],
      sourceReferences: [],
      warnings: [],
    );
  }

  @override
  Future<LocationStoryResponse> createLocationStory(
    LocationStoryRequest request,
  ) {
    throw UnimplementedError();
  }

  @override
  Future<LocationObservationResolution> resolveLocationObservation(
    LocationObservationResolveRequest request,
  ) {
    throw UnimplementedError();
  }

  @override
  Future<LocationStoryContext> getLocationContext({
    required double latitude,
    required double longitude,
    required int radiusMeters,
    String? routeId,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<LocalDiscoveryOptionsResult> getLocalDiscoveryOptions({
    required double latitude,
    required double longitude,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<WalkAdaptationProposal> evaluateAdaptation(
    String walkSessionId,
    WalkAdaptationEvaluateRequest request,
  ) {
    throw UnimplementedError();
  }

  @override
  Future<WalkSession> acceptAdaptation(
    String walkSessionId,
    String adaptationId,
    int routeRevision,
  ) {
    throw UnimplementedError();
  }

  @override
  Future<WalkAdaptationProposal> rejectAdaptation(
    String walkSessionId,
    String adaptationId,
  ) {
    throw UnimplementedError();
  }

  @override
  Future<WalkSession> arriveAtStop(
    String walkSessionId,
    String stopId, {
    double? latitude,
    double? longitude,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<WalkSession> cancelWalk(String walkSessionId) {
    throw UnimplementedError();
  }

  @override
  Future<WalkSession> completeWalk(String walkSessionId) {
    throw UnimplementedError();
  }

  @override
  Future<WalkSession> createWalk(CreateWalkRequest request) {
    throw UnimplementedError();
  }

  @override
  Future<Map<String, dynamic>> getHealth() {
    throw UnimplementedError();
  }

  @override
  Future<WalkStop?> getNextStop(String walkSessionId) {
    throw UnimplementedError();
  }

  @override
  Future<List<WalkStop>> getStops(String walkSessionId) {
    throw UnimplementedError();
  }

  @override
  Future<WalkSession> getWalk(String walkSessionId) {
    throw UnimplementedError();
  }

  @override
  Future<WalkSession> startWalk(String walkSessionId) {
    throw UnimplementedError();
  }

  @override
  Future<LocationUpdateResult> updateLocation(
    String walkSessionId,
    LocationUpdateRequest request,
  ) {
    throw UnimplementedError();
  }
}

class MismatchedLocationStoryRepository extends FakeVoiceWalkRepository {
  LocationStoryRequest? lastRequest;

  @override
  Future<LocationStoryResponse> createLocationStory(
    LocationStoryRequest request,
  ) async {
    lastRequest = request;
    return const LocationStoryResponse(
      storyTitle: 'Westport',
      shortSpokenNarration: 'Westport is a town in Ontario.',
      placeId: 'wikipedia-westport',
      factIdsUsed: ['wikipedia:westport:summary'],
      sourceReferences: [],
      confidence: 0.9,
      requiredAttribution: [],
      warnings: [],
    );
  }
}
