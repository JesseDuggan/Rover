import 'support/route_fixtures.dart';
import 'voice_controller_test.dart'
    show
        BlockingTextToSpeech,
        FakeVoiceWalkRepository,
        FakeSpeechRecognizer,
        FakeAudioSession;

import 'dart:io';
import 'dart:async';

import 'package:flutter/services.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:rover/src/active_roam/active_roam_session.dart';
import 'package:rover/src/adventure/roam.dart';
import 'package:rover/src/adaptive_stories/adaptive_route_story_controller.dart';
import 'package:rover/src/adaptive_stories/adaptive_route_story_device_cache.dart';
import 'package:rover/src/api/adaptive_route_story_models.dart';
import 'package:rover/src/api/walk_repository.dart';
import 'package:rover/src/api/problem_details.dart';
import 'package:rover/src/location/rover_location.dart';
import 'package:rover/src/voice/rover_voice_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('real voice resumes after POI narration and starts another story after exit', () async {
    var now = DateTime.now().toUtc();
    final directory = await Directory.systemTemp.createTemp('poi-continuity');
    final first = AdaptiveRouteStory.fromJson({
      ..._feedbackStory('before-poi').toJson(),
      'variants': [
        {
          'length': 'Standard',
          'estimatedDurationSeconds': 30,
          'narration': 'First fact. Second fact.',
        },
      ],
    });
    final second = _feedbackStory('after-poi');
    final repository = _StoryRepository()
      ..stories = [first, second]
      ..selection = AdaptiveRouteStorySelection(
        story: first,
        variant: first.variants.first,
        reason: 'test',
      );
    final tts = _StopCompletesStoryTts();
    final voice = RoverVoiceController(
      walkRepository: FakeVoiceWalkRepository(),
      textToSpeech: tts,
      speechRecognizer: FakeSpeechRecognizer(),
      audioSession: FakeAudioSession(),
      adaptiveRouteStoriesEnabled: true,
    );
    final cache = AdaptiveRouteStoryDeviceCache(
      file: File('${directory.path}/cache.json'),
    );
    final controller = AdaptiveRouteStoryController(
      repository: repository,
      deviceCache: cache,
      nowUtc: () => now,
    );
    var session = demoSession().copyWith(
      apiWalkSessionId: 'walk-test',
      status: RoamSessionStatus.active,
      routeProgressPercentage: 0,
      currentGpsAccuracyMeters: 5,
    );
    try {
      controller.startPolling(
        session: () => session,
        voiceController: voice,
        isForeground: () => true,
      );
      await tts.firstSpeakStarted.future.timeout(const Duration(seconds: 8));
      session = session.copyWith(
        simulatedLocation: session.currentStop.coordinates,
        arrivalCandidate: true,
        arrivalCandidateStopId: session.currentStop.id,
      );
      await _until(() => repository.events.contains('Completed'));
      expect(
        tts.spoken,
        containsAllInOrder([
          'First fact.',
          'You have arrived at ${session.currentStop.name}.',
          'Continuing the story. First fact.',
          'Second fact.',
        ]),
      );
      expect(
        repository.events,
        containsAllInOrder(['Started', 'Interrupted', 'Started', 'Completed']),
      );
      await _until(() => !controller.isBusy);
      now = now.add(const Duration(seconds: 30));
      session = session.copyWith(
        simulatedLocation: RoverLatLng(
          latitude: session.currentStop.coordinates.latitude + 0.00055,
          longitude: session.currentStop.coordinates.longitude,
        ),
        arrivalCandidate: false,
        clearArrivalCandidateStopId: true,
      );
      repository.selection = AdaptiveRouteStorySelection(
        story: second,
        variant: second.variants.first,
        reason: 'test',
      );
      await _until(
        () =>
            repository.events.where((kind) => kind == 'Completed').length == 2,
      );
      // Completion is reported before its cache write finishes on Windows.
      await _until(() => !controller.isBusy);
      expect(tts.spoken.last, 'A verified fact.');
      expect(
        tts.spoken.where((text) => text.startsWith('You have arrived')),
        hasLength(1),
      );
    } finally {
      controller.dispose();
      voice.dispose();
      cache.dispose();
      await directory.delete(recursive: true);
    }
  });
  test('arrival polling interrupts playback and resumes beyond its start window without UI frames', () async {
    final directory = await Directory.systemTemp.createTemp('arrival-poll');
    final story = _feedbackStory('arrival-test');
    final repository = _StoryRepository()
      ..stories = [story]
      ..selection = AdaptiveRouteStorySelection(
        story: story,
        variant: story.variants.first,
        reason: 'test',
      );
    final cache = AdaptiveRouteStoryDeviceCache(
      file: File('${directory.path}/cache.json'),
    );
    final controller = AdaptiveRouteStoryController(
      repository: repository,
      deviceCache: cache,
    );
    final voice = _PollingInterruptionVoice();
    var session = demoSession().copyWith(
      apiWalkSessionId: 'walk-test',
      status: RoamSessionStatus.active,
      routeProgressPercentage: 0,
    );
    try {
      controller.startPolling(
        session: () => session,
        voiceController: voice,
        isForeground: () => true,
      );
      await voice.started.future.timeout(const Duration(seconds: 8));
      session = session.copyWith(
        arrivalCandidate: true,
        arrivalCandidateStopId: session.currentStop.id,
        routeProgressPercentage: 80,
      );
      await voice.resumed.future.timeout(const Duration(seconds: 8));
      expect(voice.arrivals, 1);
      expect(voice.plays, 2);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(
        repository.events,
        containsAllInOrder(['Started', 'Interrupted', 'Started', 'Completed']),
      );
    } finally {
      controller.dispose();
      voice.dispose();
      cache.dispose();
      await directory.delete(recursive: true);
    }
  });
  for (final scenario in [
    'valid',
    'ahead',
    'expired',
    'skipped',
    'unsourced',
    'no claims',
    'sensitive',
  ]) {
    test(
      'sentence-sized cached fallback when server selects nothing: $scenario',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'story-sentence',
        );
        final story = AdaptiveRouteStory.fromJson({
          ..._feedbackStory('sentence', ahead: scenario == 'ahead').toJson(),
          'audienceSuitability': scenario == 'sensitive'
              ? 'sensitive'
              : 'family',
          if (scenario == 'expired')
            'expiresUtc': DateTime.now()
                .toUtc()
                .subtract(const Duration(minutes: 1))
                .toIso8601String(),
          if (scenario == 'unsourced') 'sources': [],
          'claims': scenario == 'no claims'
              ? []
              : [
                  {
                    'claimId': 'claim',
                    'text': 'A verified fact.',
                    'sourceIds': ['source'],
                    'confidence': 0.9,
                  },
                ],
          'variants': [
            {
              'length': 'Standard',
              'estimatedDurationSeconds': 120,
              'narration': 'A verified fact. Another verified fact.',
              'claimIds': ['claim'],
            },
          ],
        });
        final repository = _StoryRepository()
          ..stories = [story]
          ..heard = scenario == 'skipped' ? [story.storyId] : [];
        final cache = AdaptiveRouteStoryDeviceCache(
          file: File('${directory.path}/cache.json'),
        );
        final controller = AdaptiveRouteStoryController(
          repository: repository,
          deviceCache: cache,
        );
        final voice = RoverVoiceController(
          walkRepository: _WalkRepository(),
          adaptiveRouteStoriesEnabled: true,
        );
        final base = demoSession();
        final session = base.copyWith(
          apiWalkSessionId: 'walk-test',
          status: RoamSessionStatus.active,
          routeProgressPercentage: 0,
          roam: base.roam.copyWith(
            routeProvider: 'GoogleRoutes',
            routeManeuvers: const [
              RoverRouteManeuver(
                sequenceNumber: 0,
                instruction: 'Walk ahead',
                distanceMeters: 60,
                durationMinutes: 1,
                maneuverType: 'DEPART',
              ),
              RoverRouteManeuver(
                sequenceNumber: 1,
                instruction: 'Turn left',
                distanceMeters: 100,
                durationMinutes: 1,
                maneuverType: 'TURN_LEFT',
              ),
            ],
          ),
        );
        try {
          expect(session.storySecondsUntilNavigation, lessThan(120));
          await controller.syncWithSession(session, voice);
          expect(repository.selections, 1);
          expect(repository.events.contains('Completed'), scenario == 'valid');
          if (scenario == 'valid') {
            expect(repository.events, ['Started', 'Completed']);
          } else {
            expect(repository.events, isEmpty);
          }
        } finally {
          controller.dispose();
          voice.dispose();
          cache.dispose();
          await directory.delete(recursive: true);
        }
      },
    );
  }
  for (final timedOut in [true, false]) {
    test(
      'empty packs retry once early without movement (timeout=$timedOut)',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'timeout-retry',
        );
        final repository = _StoryRepository()
          ..warnings = [
            timedOut
                ? 'Local research failed during story validation: request timed out.'
                : 'Local research found no usable cited passages.',
          ];
        final cache = AdaptiveRouteStoryDeviceCache(
          file: File('${directory.path}/cache.json'),
        );
        var now = DateTime.now().toUtc();
        final controller = AdaptiveRouteStoryController(
          repository: repository,
          deviceCache: cache,
          nowUtc: () => now,
        );
        final voice = _PlaybackVoice();
        final session = demoSession().copyWith(
          apiWalkSessionId: 'walk-test',
          status: RoamSessionStatus.active,
          routeProgressPercentage: 0,
        );
        try {
          await controller.syncWithSession(session, voice);
          expect(
            controller.listeningStatus(session),
            contains('automatic retry'),
          );
          now = now.add(const Duration(seconds: 19));
          await controller.syncWithSession(session, voice);
          expect(repository.generations, 0);
          now = now.add(const Duration(seconds: 2));
          await controller.syncWithSession(session, voice);
          await Future<void>.delayed(Duration.zero);
          expect(repository.generations, 1);
          now = now.add(const Duration(seconds: 25));
          await controller.syncWithSession(session, voice);
          expect(repository.generations, 1);
          expect(
            controller.listeningStatus(session),
            timedOut
                ? contains('Please try refreshing')
                : 'No verified stories available right now',
          );
        } finally {
          controller.dispose();
          voice.dispose();
          cache.dispose();
          await directory.delete(recursive: true);
        }
      },
    );
  }
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('ai.myrover.rover/voice'),
        (_) async => null,
      );
  test('refresh reports new, unchanged, pending and failed results without dropping stories', () async {
    final directory = await Directory.systemTemp.createTemp('story-feedback');
    final repository = _StoryRepository()..stories = [_feedbackStory('one')];
    final cache = AdaptiveRouteStoryDeviceCache(
      file: File('${directory.path}/cache.json'),
    );
    var now = DateTime.now().toUtc();
    final controller = AdaptiveRouteStoryController(
      repository: repository,
      deviceCache: cache,
      nowUtc: () => now,
    );
    final voice = _PlaybackVoice();
    final session = demoSession().copyWith(
      apiWalkSessionId: 'walk-test',
      status: RoamSessionStatus.active,
    );
    try {
      repository.stories = [];
      await controller.syncWithSession(session, voice);
      await controller.refreshPack(session);
      expect(controller.refreshMessage, contains('No verified stories found'));
      expect(controller.refreshMessage, isNot(contains('existing stories')));
      repository.stories = [_feedbackStory('one')];
      await controller.refreshPack(session);
      expect(controller.unheardStoryCount, 1);
      await controller.refreshPack(session);
      expect(controller.refreshMessage, contains('No new verified stories'));
      repository.stories = [_feedbackStory('one'), _feedbackStory('two')];
      await controller.refreshPack(session);
      expect(controller.refreshMessage, '1 new story added');
      repository.statusOverride = 'Generating';
      await controller.refreshPack(session);
      expect(controller.isRefreshing, isTrue);
      expect(controller.pack!.stories.length, 2);
      expect(controller.listeningStatus(session), 'Finding more stories...');
      final attempts = repository.generations;
      await controller.refreshPack(session);
      expect(repository.generations, attempts);
      repository.statusOverride = 'Failed';
      now = now.add(const Duration(seconds: 6));
      await controller.syncWithSession(session, voice);
      expect(controller.isRefreshing, isFalse);
      expect(controller.pack!.stories.length, 2);
      expect(controller.refreshMessage, contains('research unavailable'));
    } finally {
      controller.dispose();
      voice.dispose();
      cache.dispose();
      await directory.delete(recursive: true);
    }
  });

  test(
    'listening status distinguishes heard, skipped and stories ahead',
    () async {
      final directory = await Directory.systemTemp.createTemp('story-status');
      final repository = _StoryRepository()
        ..stories = [_feedbackStory('one', ahead: true)];
      final cache = AdaptiveRouteStoryDeviceCache(
        file: File('${directory.path}/cache.json'),
      );
      final controller = AdaptiveRouteStoryController(
        repository: repository,
        deviceCache: cache,
      );
      final voice = _PlaybackVoice();
      final session = demoSession().copyWith(
        apiWalkSessionId: 'walk-test',
        status: RoamSessionStatus.active,
        routeProgressPercentage: 0,
      );
      try {
        await controller.syncWithSession(session, voice);
        expect(
          controller.listeningStatus(session),
          'Stories ahead on your route',
        );
        repository.heard = ['one'];
        repository.outcomes = const AdaptiveStoryPlaybackOutcomes(
          skippedStoryIds: ['one'],
        );
        await controller.refreshPack(session);
        expect(
          controller.listeningStatus(session),
          'No unplayed stories remaining',
        );
        repository.outcomes = const AdaptiveStoryPlaybackOutcomes(
          completedStoryIds: ['one'],
        );
        await controller.refreshPack(session);
        expect(
          controller.listeningStatus(session),
          'All current stories heard',
        );
      } finally {
        controller.dispose();
        voice.dispose();
        cache.dispose();
        await directory.delete(recursive: true);
      }
    },
  );

  test(
    'slow walking permits a bounded refill without another 150 metres',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'story-slow-walk',
      );
      final repository = _StoryRepository();
      final cache = AdaptiveRouteStoryDeviceCache(
        file: File('${directory.path}/cache.json'),
      );
      var now = DateTime.now().toUtc();
      final controller = AdaptiveRouteStoryController(
        repository: repository,
        deviceCache: cache,
        nowUtc: () => now,
      );
      final voice = _PlaybackVoice();
      final session = demoSession().copyWith(
        apiWalkSessionId: 'walk-test',
        status: RoamSessionStatus.active,
        routeProgressPercentage: 0,
      );
      try {
        await controller.syncWithSession(session, voice);
        now = now.add(const Duration(minutes: 1));
        await controller.syncWithSession(session, voice);
        await Future<void>.delayed(Duration.zero);
        expect(repository.generations, 1);
        now = now.add(const Duration(minutes: 3));
        await controller.syncWithSession(session, voice);
        expect(repository.generations, 1);
        now = now.add(const Duration(minutes: 2));
        await controller.syncWithSession(session, voice);
        await Future<void>.delayed(Duration.zero);
        expect(repository.generations, 2);
      } finally {
        controller.dispose();
        voice.dispose();
        cache.dispose();
        await directory.delete(recursive: true);
      }
    },
  );
  for (final scenario in ['nearby', 'distant', 'poor-gps', 'expired']) {
    test('off-route stories use actual location: $scenario', () async {
      final directory = await Directory.systemTemp.createTemp(
        'story-wandering',
      );
      final session = demoSession().copyWith(
        apiWalkSessionId: 'walk-test',
        status: RoamSessionStatus.active,
        isOffRoute: true,
        currentGpsAccuracyMeters: scenario == 'poor-gps' ? 90 : 8,
      );
      final story = AdaptiveRouteStory.fromJson({
        'storyId': 'nearby',
        'placeId': 'nearby',
        'anchor': {
          'latitude':
              session.simulatedLocation.latitude +
              (scenario == 'distant' ? 1 : 0),
          'longitude': session.simulatedLocation.longitude,
        },
        'opensAtRouteMeters': 9000,
        'closesAtRouteMeters': 9500,
        if (scenario == 'expired')
          'expiresUtc': DateTime.now()
              .toUtc()
              .subtract(const Duration(minutes: 1))
              .toIso8601String(),
        'sources': [
          {'sourceId': 'source', 'url': 'https://example.org/story'},
        ],
        'claims': [
          {
            'claimId': 'claim',
            'text': 'A local fact.',
            'sourceIds': ['source'],
          },
        ],
        'variants': [
          {
            'length': 'Standard',
            'estimatedDurationSeconds': 20,
            'narration': 'A local fact.',
          },
        ],
      });
      final repository = _StoryRepository()..stories = [story];
      final cache = AdaptiveRouteStoryDeviceCache(
        file: File('${directory.path}/cache.json'),
      );
      final controller = AdaptiveRouteStoryController(
        repository: repository,
        deviceCache: cache,
      );
      final voice = _PlaybackVoice();
      try {
        await controller.syncWithSession(session, voice);
        expect(voice.plays, scenario == 'nearby' ? 1 : 0);
        expect(repository.selections, 0);
      } finally {
        controller.dispose();
        voice.dispose();
        cache.dispose();
        await directory.delete(recursive: true);
      }
    });
  }
  test('low coverage replenishes without blocking selection and rejects stale route results', () async {
    final directory = await Directory.systemTemp.createTemp('story-refill');
    final repository = _StoryRepository();
    final pending = Completer<AdaptiveRouteStoryPackState>();
    repository.generationResult = pending.future;
    final cache = AdaptiveRouteStoryDeviceCache(
      file: File('${directory.path}/cache.json'),
    );
    var now = DateTime.now().toUtc();
    final controller = AdaptiveRouteStoryController(
      repository: repository,
      deviceCache: cache,
      nowUtc: () => now,
    );
    final voice = _PlaybackVoice();
    final session = demoSession().copyWith(
      apiWalkSessionId: 'walk-test',
      status: RoamSessionStatus.active,
      distanceToNextStopMeters: 500,
      routeProgressPercentage: 0,
    );
    try {
      await controller.syncWithSession(session, voice);
      expect(repository.generations, 0);
      now = now.add(const Duration(minutes: 4));
      await controller.syncWithSession(
        session.copyWith(routeProgressPercentage: 20),
        voice,
      );
      expect(repository.generations, 1);
      final selected = repository.selections;
      await controller.syncWithSession(
        session.copyWith(routeProgressPercentage: 30),
        voice,
      );
      expect(repository.selections, greaterThan(selected));
      expect(repository.generations, 1);
      await controller.syncWithSession(
        session.copyWith(routeRevision: 2, routeProgressPercentage: 40),
        voice,
      );
      final newState = controller.packState;
      pending.complete(await repository.getRouteStoryPackStatus('walk-test'));
      await Future<void>.delayed(Duration.zero);
      expect(identical(controller.packState, newState), isTrue);
    } finally {
      controller.dispose();
      voice.dispose();
      cache.dispose();
      await directory.delete(recursive: true);
    }
  });

  test('automatic replenishment backs off and is capped per walk', () async {
    final directory = await Directory.systemTemp.createTemp(
      'story-refill-budget',
    );
    final repository = _StoryRepository();
    final cache = AdaptiveRouteStoryDeviceCache(
      file: File('${directory.path}/cache.json'),
    );
    var now = DateTime.now().toUtc();
    final controller = AdaptiveRouteStoryController(
      repository: repository,
      deviceCache: cache,
      nowUtc: () => now,
    );
    final voice = _PlaybackVoice();
    final session = demoSession().copyWith(
      apiWalkSessionId: 'walk-test',
      status: RoamSessionStatus.active,
      distanceToNextStopMeters: 500,
      routeProgressPercentage: 0,
    );
    try {
      await controller.syncWithSession(session, voice);
      for (var i = 1; i <= 10; i++) {
        now = now.add(const Duration(minutes: 4));
        await controller.syncWithSession(
          session.copyWith(routeProgressPercentage: i * 10.0),
          voice,
        );
        await Future<void>.delayed(Duration.zero);
      }
      expect(repository.generations, 6);
    } finally {
      controller.dispose();
      voice.dispose();
      cache.dispose();
      await directory.delete(recursive: true);
    }
  });
  for (final scenario in [
    (150.0, false, false, 100),
    (150.0, false, false, 10),
    (251.0, false, false, 100),
    (150.0, true, false, 100),
    (150.0, false, true, 100),
  ]) {
    final (distance, expired, skipped, maximumSeconds) = scenario;
    test(
      'navigation-held story catch-up at $distance metres, expired=$expired, skipped=$skipped, maximumSeconds=$maximumSeconds',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'story-catch-up',
        );
        final story = AdaptiveRouteStory.fromJson({
          'storyId': 'delayed',
          'audienceSuitability': 'family',
          'opensAtRouteMeters': 0,
          'closesAtRouteMeters': 100,
          if (expired)
            'expiresUtc': DateTime.now()
                .toUtc()
                .subtract(const Duration(minutes: 1))
                .toIso8601String(),
          'sources': [
            {'sourceId': 'source', 'url': 'https://example.org/story'},
          ],
          'variants': [
            {
              'length': 'Quick',
              'estimatedDurationSeconds': 5,
              'narration': 'A local fact.',
            },
            {
              'length': 'Standard',
              'estimatedDurationSeconds': 40,
              'narration': 'A detailed account of local history.',
            },
          ],
        });
        final repository = _StoryRepository()..stories = [story];
        final cache = AdaptiveRouteStoryDeviceCache(
          file: File('${directory.path}/cache.json'),
        );
        final controller = AdaptiveRouteStoryController(
          repository: repository,
          deviceCache: cache,
        );
        final voice = _PlaybackVoice()..maximumSeconds = maximumSeconds;
        final session = demoSession().copyWith(
          apiWalkSessionId: 'walk-test',
          status: RoamSessionStatus.active,
          distanceToNextStopMeters: 500,
        );
        final maneuverDistance = session.roam.routeManeuvers.fold<int>(
          0,
          (sum, item) => sum + item.distanceMeters,
        );
        final total = maneuverDistance > 0
            ? maneuverDistance.toDouble()
            : session.roam.distanceMiles * 1609.344;
        try {
          await controller.syncWithSession(
            session.copyWith(
              routeProgressPercentage: 50 / total * 100,
              isOffRoute: true,
            ),
            voice,
          );
          expect(voice.plays, 0);
          if (skipped) {
            expect(controller.selectStory(story.storyId, session), isTrue);
            await controller.skipCurrent(session);
          }
          await controller.syncWithSession(
            session.copyWith(
              routeProgressPercentage: distance / total * 100,
              isOffRoute: false,
            ),
            voice,
          );
          expect(voice.plays, distance <= 250 && !expired && !skipped ? 1 : 0);
          if (voice.plays > 0) {
            expect(
              voice.lastLength,
              maximumSeconds >= 40 ? 'Standard' : 'Quick',
            );
          }
          expect(
            controller.automaticStoryStatus(
              story,
              session.copyWith(routeProgressPercentage: distance / total * 100),
            ),
            expired
                ? 'Expired'
                : skipped
                ? 'Skipped'
                : distance <= 250
                ? 'Played'
                : 'Automatic playback window passed',
          );
        } finally {
          controller.dispose();
          voice.dispose();
          cache.dispose();
          await directory.delete(recursive: true);
        }
      },
    );
  }

  test(
    'outcome labels distinguish completed, skipped and legacy exclusions',
    () async {
      final directory = await Directory.systemTemp.createTemp('story-labels');
      final stories = ['played', 'skipped', 'legacy']
          .map(
            (id) => AdaptiveRouteStory.fromJson({
              'storyId': id,
              'closesAtRouteMeters': 10000,
            }),
          )
          .toList();
      final repository = _StoryRepository()
        ..stories = stories
        ..heard = ['played', 'skipped', 'legacy']
        ..outcomes = const AdaptiveStoryPlaybackOutcomes(
          completedStoryIds: ['played'],
          skippedStoryIds: ['skipped'],
        );
      final cache = AdaptiveRouteStoryDeviceCache(
        file: File('${directory.path}/cache.json'),
      );
      final controller = AdaptiveRouteStoryController(
        repository: repository,
        deviceCache: cache,
      );
      final voice = _PlaybackVoice();
      final session = demoSession().copyWith(
        apiWalkSessionId: 'walk-test',
        status: RoamSessionStatus.notStarted,
      );
      try {
        await controller.syncWithSession(session, voice);
        expect(
          stories.map(
            (story) => controller.automaticStoryStatus(story, session),
          ),
          ['Played', 'Skipped', 'Previously handled'],
        );
      } finally {
        controller.dispose();
        voice.dispose();
        cache.dispose();
        await directory.delete(recursive: true);
      }
    },
  );
  test(
    'ready stories can be read outside their automatic window without playback',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'story-manual-test',
      );
      final story = AdaptiveRouteStory.fromJson({
        'storyId': 'sourced-story',
        'audienceSuitability': 'family',
        'title': 'Local history',
        'opensAtRouteMeters': 0,
        'closesAtRouteMeters': 1,
        'sources': [
          {'sourceId': 'source', 'url': 'https://example.org/history'},
        ],
        'variants': [
          {
            'length': 'Quick',
            'estimatedDurationSeconds': 5,
            'narration': 'Brief sourced text.',
          },
          {
            'length': 'Standard',
            'estimatedDurationSeconds': 20,
            'narration': 'Longer sourced text.',
          },
        ],
      });
      final expired = AdaptiveRouteStory.fromJson({
        ...story.toJson(),
        'storyId': 'expired',
        'expiresUtc': DateTime.now()
            .toUtc()
            .subtract(const Duration(hours: 1))
            .toIso8601String(),
      });
      final repository = _StoryRepository()..stories = [story, expired];
      final cache = AdaptiveRouteStoryDeviceCache(
        file: File('${directory.path}/cache.json'),
      );
      final controller = AdaptiveRouteStoryController(
        repository: repository,
        deviceCache: cache,
      );
      final voice = _PlaybackVoice();
      final session = demoSession().copyWith(
        apiWalkSessionId: 'walk-test',
        status: RoamSessionStatus.active,
        distanceToNextStopMeters: 500,
        routeProgressPercentage: 50,
      );
      try {
        await controller.syncWithSession(session, voice);
        expect(
          controller.automaticStoryStatus(story, session),
          'Automatic playback window passed',
        );
        expect(controller.selectStory('not-in-pack', session), isFalse);
        expect(controller.selectStory('expired', session), isFalse);
        expect(
          controller.selectStory(
            story.storyId,
            session.copyWith(routeRevision: 2),
          ),
          isFalse,
        );
        expect(controller.selectStory(story.storyId, session), isTrue);
        expect(controller.currentSelection!.variant.length, 'Standard');
        final nearTurn = session.copyWith(
          routeProgressPercentage: 0,
          roam: session.roam.copyWith(
            routeProvider: 'Google',
            routeManeuvers: const [
              RoverRouteManeuver(
                sequenceNumber: 1,
                instruction: 'Turn left',
                distanceMeters: 100,
                durationMinutes: 1,
                maneuverType: 'TURN_LEFT',
              ),
            ],
          ),
        );
        expect(nearTurn.storySecondsUntilNavigation, 0);
        expect(controller.selectStory(story.storyId, nearTurn), isTrue);
        expect(controller.currentSelection!.variant.length, 'Standard');
        expect(
          controller.currentSelection!.variant.narration,
          'Longer sourced text.',
        );
        final checks = repository.selections;
        await controller.syncWithSession(
          session.copyWith(routeProgressPercentage: 75),
          voice,
        );
        expect(repository.selections, checks);
        expect(voice.plays, 0);
        expect(repository.events, isEmpty);
        controller.closeStory();
        expect(controller.currentSelection, isNull);
        await controller.syncWithSession(session, voice);
        expect(repository.selections, greaterThan(checks));
        expect(repository.events, isEmpty);
        expect(controller.selectStory(story.storyId, session), isTrue);
        await controller.playCurrent(session, voice);
        expect(voice.plays, 1);
        expect(repository.events, contains('Completed'));
      } finally {
        controller.dispose();
        voice.dispose();
        cache.dispose();
        await directory.delete(recursive: true);
      }
    },
  );

  for (final offline in [false, true]) {
    for (final outcome in [
      AdaptiveStoryPlaybackResult.interrupted,
      AdaptiveStoryPlaybackResult.failed,
      AdaptiveStoryPlaybackResult.blocked,
      AdaptiveStoryPlaybackResult.paused,
    ]) {
      test('reports $outcome without completion, offline=$offline', () async {
        final directory = await Directory.systemTemp.createTemp(
          'story-outcome',
        );
        final file = File('${directory.path}/cache.json');
        final story = AdaptiveRouteStory.fromJson({
          'storyId': 'outcome-story',
          'sources': [
            {'sourceId': 'source', 'url': 'https://example.org/history'},
          ],
          'variants': [
            {
              'length': 'Quick',
              'estimatedDurationSeconds': 5,
              'narration': 'A sourced fact.',
            },
          ],
        });
        final repository = _StoryRepository()..stories = [story];
        final cache = AdaptiveRouteStoryDeviceCache(file: file);
        final controller = AdaptiveRouteStoryController(
          repository: repository,
          deviceCache: cache,
        );
        final voice = _PlaybackVoice()..result = outcome;
        final session = demoSession().copyWith(
          apiWalkSessionId: 'walk-test',
          status: RoamSessionStatus.notStarted,
          distanceToNextStopMeters: 500,
        );
        try {
          await controller.syncWithSession(session, voice);
          expect(controller.selectStory(story.storyId, session), isTrue);
          repository.offlineEvents = offline;
          await controller.playCurrent(session, voice);
          final expected = [
            'Started',
            if (outcome == AdaptiveStoryPlaybackResult.interrupted)
              'Interrupted',
            if (outcome == AdaptiveStoryPlaybackResult.failed) 'Failed',
          ];
          if (offline) {
            final restored = AdaptiveRouteStoryDeviceCache(file: file);
            final sent = <String>[];
            await restored.flushEvents((event) async {
              expect(event.walkSessionId, 'walk-test');
              expect(event.request.storyId, story.storyId);
              sent.add(event.request.kind);
            });
            expect(sent, expected);
            expect(restored.queuedEventCount, 0);
            restored.dispose();
          } else {
            expect(repository.events, expected);
          }
          expect(controller.currentSelection, isNotNull);
          expect(controller.isBusy, isFalse);
          if (outcome == AdaptiveStoryPlaybackResult.failed) {
            expect(controller.errorMessage, contains('could not be played'));
          }
          if (outcome == AdaptiveStoryPlaybackResult.paused) {
            await controller.syncWithSession(
              session.copyWith(
                status: RoamSessionStatus.active,
                routeProgressPercentage: 75,
              ),
              voice,
            );
            expect(voice.plays, 1);
          }
          repository.offlineEvents = false;
          voice.result = AdaptiveStoryPlaybackResult.completed;
          await controller.playCurrent(session, voice);
          expect(
            repository.events.where((event) => event == 'Completed'),
            hasLength(1),
          );
          expect(controller.currentSelection, isNull);
        } finally {
          controller.dispose();
          voice.dispose();
          cache.dispose();
          await directory.delete(recursive: true);
        }
      });
    }
  }

  test('routine arrival does not block story selection', () async {
    final directory = await Directory.systemTemp.createTemp(
      'story-arrival-test',
    );
    final story = AdaptiveRouteStory.fromJson({
      'storyId': 'sourced-story',
      'audienceSuitability': 'family',
      'opensAtRouteMeters': 0,
      'closesAtRouteMeters': 10000,
      'sources': [
        {'sourceId': 'source', 'sourceUrl': 'https://example.org/history'},
      ],
      'variants': [
        {
          'length': 'Quick',
          'estimatedDurationSeconds': 5,
          'narration': 'Sourced text.',
        },
      ],
    });
    final repository = _StoryRepository()..stories = [story];
    final cache = AdaptiveRouteStoryDeviceCache(
      file: File('${directory.path}/cache.json'),
    );
    final controller = AdaptiveRouteStoryController(
      repository: repository,
      deviceCache: cache,
    );
    final voice = _PlaybackVoice();
    final session = demoSession().copyWith(
      apiWalkSessionId: 'walk-test',
      status: RoamSessionStatus.active,
      arrivalCandidate: true,
      distanceToNextStopMeters: 20,
    );
    try {
      await controller.syncWithSession(session, voice);
      expect(
        controller.automaticStoryStatus(story, session),
        'In playback window',
      );
      expect(controller.selectStory(story.storyId, session), isTrue);
      await controller.playCurrent(session, voice);
      expect(controller.errorMessage, isNull);
      expect(controller.currentSelection, isNull);
      expect(repository.events, ['Started', 'Completed']);
    } finally {
      controller.dispose();
      voice.dispose();
      cache.dispose();
      await directory.delete(recursive: true);
    }
  });
  test('polls unchanged sessions and exposes terminal errors, then stops on disposal', () async {
    final directory = await Directory.systemTemp.createTemp('story-poll-test');
    final repository = _StoryRepository()..statusOverride = 'Generating';
    final cache = AdaptiveRouteStoryDeviceCache(
      file: File('${directory.path}/cache.json'),
    );
    final controller = AdaptiveRouteStoryController(
      repository: repository,
      deviceCache: cache,
    );
    final voice = _PlaybackVoice();
    final session = demoSession().copyWith(
      apiWalkSessionId: 'walk-test',
      status: RoamSessionStatus.notStarted,
    );
    var foreground = false;
    var disposed = false;
    try {
      await controller.syncWithSession(session, voice);
      expect(controller.readinessLabel, 'generating');
      repository.statusOverride = 'Failed';
      controller.startPolling(
        session: () => session,
        voiceController: voice,
        isForeground: () => foreground,
      );
      await Future<void>.delayed(const Duration(milliseconds: 5200));
      expect(repository.statusChecks, 1);
      foreground = true;
      await Future<void>.delayed(const Duration(milliseconds: 5200));
      expect(repository.statusChecks, greaterThanOrEqualTo(2));
      expect(controller.readinessLabel, 'failed');
      expect(controller.errorMessage, 'Generation timed out.');
      expect(controller.researchStatus, 'Generation timed out.');
      controller.dispose();
      disposed = true;
      final checksAtDisposal = repository.statusChecks;
      await Future<void>.delayed(const Duration(milliseconds: 5200));
      expect(repository.statusChecks, checksAtDisposal);
    } finally {
      if (!disposed) controller.dispose();
      voice.dispose();
      cache.dispose();
      await directory.delete(recursive: true);
    }
  });
  test(
    'refreshing packs continue status checks while retaining stories',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'story-refresh-test',
      );
      final repository = _StoryRepository()..refreshing = true;
      final cache = AdaptiveRouteStoryDeviceCache(
        file: File('${directory.path}/cache.json'),
      );
      final controller = AdaptiveRouteStoryController(
        repository: repository,
        deviceCache: cache,
      );
      final voice = _PlaybackVoice();
      final session = demoSession().copyWith(
        apiWalkSessionId: 'walk-test',
        status: RoamSessionStatus.notStarted,
      );
      try {
        await controller.syncWithSession(session, voice);
        expect(controller.pack, isNotNull);
        expect(controller.readinessLabel, 'generating');
        repository.refreshing = false;
        await Future<void>.delayed(const Duration(milliseconds: 4100));
        await controller.syncWithSession(session, voice);
        expect(repository.statusChecks, 2);
        expect(controller.readinessLabel, 'ready');
      } finally {
        controller.dispose();
        voice.dispose();
        cache.dispose();
        await directory.delete(recursive: true);
      }
    },
  );

  for (final status in [
    'Pending',
    'Generating',
    'Failed',
    'connection',
    'timeout',
  ]) {
    test(
      'completion retains online stories after $status status response',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'story-retention',
        );
        final online = AdaptiveRouteStory.fromJson({
          ..._feedbackStory('online').toJson(),
          'sources': [
            {
              'sourceId': 'web',
              'providerName': 'OnlineResearch',
              'url': 'https://example.org/history',
              'allowsOfflineUse': false,
            },
          ],
        });
        final downloaded = _feedbackStory('downloaded');
        final repository = _StoryRepository()..stories = [online, downloaded];
        final cache = AdaptiveRouteStoryDeviceCache(
          file: File('${directory.path}/cache.json'),
        );
        var now = DateTime.now().toUtc();
        final controller = AdaptiveRouteStoryController(
          repository: repository,
          deviceCache: cache,
          nowUtc: () => now,
        );
        final voice = _PlaybackVoice();
        final session = demoSession().copyWith(
          apiWalkSessionId: 'walk-test',
          status: RoamSessionStatus.notStarted,
          distanceToNextStopMeters: 500,
        );
        try {
          await controller.syncWithSession(session, voice);
          expect(controller.selectStory('online', session), isTrue);
          if (status == 'connection') {
            repository.statusError = const RoverApiConnectionException(
              'Offline',
            );
          } else if (status == 'timeout') {
            repository.statusError = const RoverApiTimeoutException(
              'Timed out',
            );
          } else {
            repository.statusOverride = status;
          }
          await controller.playCurrent(session, voice);
          expect(voice.plays, 1);
          expect(controller.currentSelection, isNull);
          expect(controller.pack!.stories.map((story) => story.storyId), [
            'online',
            'downloaded',
          ]);
          expect(controller.unheardStoryCount, 1);
          final stored = await cache.get('walk-test', session.routeRevision);
          expect(stored!.pack!.stories.map((story) => story.storyId), [
            'downloaded',
          ]);

          if (repository.statusError != null) {
            expect(controller.usingOfflinePack, isTrue);
            expect(controller.selectStory('online', session), isTrue);
            await controller.playCurrent(session, voice);
            expect(
              voice.plays,
              1,
              reason: 'Retained online text is not an offline download.',
            );
            controller.closeStory();
            repository.statusError = null;
            now = now.add(const Duration(seconds: 5));
            await controller.syncWithSession(session, voice);
            expect(controller.usingOfflinePack, isFalse);
            expect(controller.pack!.stories, hasLength(2));
          }
        } finally {
          controller.dispose();
          voice.dispose();
          cache.dispose();
          await directory.delete(recursive: true);
        }
      },
    );
  }

  test(
    'failed save and status sync preserve an online-only collection',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'story-save-retention',
      );
      final online = AdaptiveRouteStory.fromJson({
        ..._feedbackStory('online').toJson(),
        'sources': [
          {
            'sourceId': 'web',
            'providerName': 'OnlineResearch',
            'allowsOfflineUse': false,
          },
        ],
      });
      final repository = _StoryRepository()..stories = [online];
      final cache = AdaptiveRouteStoryDeviceCache(
        file: File('${directory.path}/cache.json'),
      );
      var now = DateTime.now().toUtc();
      final controller = AdaptiveRouteStoryController(
        repository: repository,
        deviceCache: cache,
        nowUtc: () => now,
      );
      final voice = _PlaybackVoice();
      final session = demoSession().copyWith(
        apiWalkSessionId: 'walk-test',
        status: RoamSessionStatus.notStarted,
      );
      try {
        await controller.syncWithSession(session, voice);
        expect(controller.selectStory('online', session), isTrue);
        repository.offlineEvents = true;
        repository.statusError = const RoverApiConnectionException('Offline');
        await controller.saveCurrent(session);
        expect(controller.pack!.stories.single.storyId, 'online');
        expect(controller.queuedEventCount, 1);
        controller.closeStory();
        now = now.add(const Duration(seconds: 5));
        await controller.syncWithSession(session, voice);
        expect(controller.pack!.stories.single.storyId, 'online');
        expect(await cache.get('walk-test', session.routeRevision), isNull);
        await controller.syncWithSession(
          session.copyWith(apiWalkSessionId: 'other-walk'),
          voice,
        );
        expect(
          controller.pack,
          isNull,
          reason: 'Never retain another walk\'s stories.',
        );
      } finally {
        controller.dispose();
        voice.dispose();
        cache.dispose();
        await directory.delete(recursive: true);
      }
    },
  );

  test('completed audio cannot replay when server status is stale', () async {
    var now = DateTime.now().toUtc();
    final directory = await Directory.systemTemp.createTemp(
      'story-repeat-test',
    );
    final story = AdaptiveRouteStory.fromJson({
      'storyId': 'story-1',
      'placeId': 'history-1',
      'intent': 'HiddenHistory',
      'opensAtRouteMeters': 0,
      'closesAtRouteMeters': 10000,
    });
    final selection = AdaptiveRouteStorySelection(
      story: story,
      variant: RouteStoryNarrationVariant.fromJson({
        'length': 'Quick',
        'estimatedDurationSeconds': 5,
        'narration': 'A sourced story.',
      }),
      reason: 'test',
    );
    final repository = _StoryRepository()..selection = selection;
    final cache = AdaptiveRouteStoryDeviceCache(
      file: File('${directory.path}/cache.json'),
    );
    final controller = AdaptiveRouteStoryController(
      repository: repository,
      deviceCache: cache,
      nowUtc: () => now,
    );
    final voice = _PlaybackVoice();
    try {
      final session = demoSession().copyWith(
        apiWalkSessionId: 'walk-test',
        status: RoamSessionStatus.active,
        distanceToNextStopMeters: 500,
        routeProgressPercentage: 25,
        currentGpsAccuracyMeters: 5,
      );
      await controller.syncWithSession(session, voice);
      now = now.add(const Duration(seconds: 30));
      await controller.syncWithSession(
        session.copyWith(
          routeProgressPercentage: 50,
          simulatedLocation: RoverLatLng(
            latitude: session.simulatedLocation.latitude + 0.00055,
            longitude: session.simulatedLocation.longitude,
          ),
        ),
        voice,
      );
      expect(voice.plays, 1);
      expect(repository.lastRequest!.excludedStoryIds, contains('story-1'));
      expect(controller.currentSelection, isNull);
      repository.selection = AdaptiveRouteStorySelection(
        story: AdaptiveRouteStory.fromJson({
          ...story.toJson(),
          'storyId': 'story-2',
        }),
        variant: selection.variant,
        reason: 'Another story about the same place',
      );
      now = now.add(const Duration(seconds: 15));
      await controller.syncWithSession(
        session.copyWith(
          routeProgressPercentage: 55,
          simulatedLocation: RoverLatLng(
            latitude: session.simulatedLocation.latitude + 0.00065,
            longitude: session.simulatedLocation.longitude,
          ),
        ),
        voice,
      );
      expect(
        voice.plays,
        2,
        reason: 'Distinct stories at the same place remain eligible.',
      );
    } finally {
      controller.dispose();
      voice.dispose();
      cache.dispose();
      await directory.delete(recursive: true);
    }
  });
  test('selection continues through routine arrival and nearby stop', () async {
    final directory = await Directory.systemTemp.createTemp('route-retry-test');
    final repository = _StoryRepository();
    final cache = AdaptiveRouteStoryDeviceCache(
      file: File('${directory.path}/cache.json'),
    );
    final controller = AdaptiveRouteStoryController(
      repository: repository,
      deviceCache: cache,
    );
    final voice = RoverVoiceController(walkRepository: _WalkRepository());
    try {
      final safe = demoSession().copyWith(
        apiWalkSessionId: 'walk-test',
        status: RoamSessionStatus.active,
        distanceToNextStopMeters: 500,
        routeProgressPercentage: 25,
      );
      await controller.syncWithSession(safe, voice);
      expect(repository.selections, 1);
      await controller.syncWithSession(
        safe.copyWith(routeProgressPercentage: 50, arrivalCandidate: true),
        voice,
      );
      expect(repository.selections, 2);
      await controller.syncWithSession(
        safe.copyWith(routeProgressPercentage: 50),
        voice,
      );
      expect(repository.selections, 2);
      final stop = safe.currentStop;
      final near = safe.copyWith(
        routeProgressPercentage: 75,
        recentNarrationStopId: stop.id,
        simulatedLocation: stop.coordinates,
      );
      await controller.syncWithSession(near, voice);
      expect(repository.selections, 3);
      await controller.syncWithSession(
        near.copyWith(
          simulatedLocation: RoverLatLng(
            latitude: stop.coordinates.latitude + 0.01,
            longitude: stop.coordinates.longitude,
          ),
        ),
        voice,
      );
      expect(repository.selections, 3);
      await controller.syncWithSession(
        safe.copyWith(
          routeProgressPercentage: 80,
          distanceToNextStopMeters: 95,
          currentGpsAccuracyMeters: 8,
        ),
        voice,
      );
      expect(repository.selections, 4);
      expect(
        repository.lastRequest?.secondsUntilNextManeuver,
        safe.storySecondsUntilNavigation,
      );
      await controller.syncWithSession(
        near.copyWith(
          routeProgressPercentage: 85,
          arrivalCandidate: true,
          arrivalCandidateStopId: stop.id,
          narratedArrivalStopIds: {stop.id},
        ),
        voice,
      );
      expect(repository.selections, 5);
    } finally {
      controller.dispose();
      voice.dispose();
      cache.dispose();
      await directory.delete(recursive: true);
    }
  });
}

class _WalkRepository implements WalkRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

AdaptiveRouteStory _feedbackStory(String id, {bool ahead = false}) =>
    AdaptiveRouteStory.fromJson({
      'storyId': id,
      'audienceSuitability': 'family',
      'placeId': id,
      'title': id,
      'opensAtRouteMeters': ahead ? 2000 : 0,
      'closesAtRouteMeters': ahead ? 3000 : 1000,
      'sources': [
        {'sourceId': 'source', 'url': 'https://example.org/story'},
      ],
      'variants': [
        {
          'length': 'Standard',
          'estimatedDurationSeconds': 30,
          'narration': 'A verified fact.',
        },
      ],
    });

Future<void> _until(bool Function() ready) async {
  final end = DateTime.now().add(const Duration(seconds: 12));
  while (!ready()) {
    if (DateTime.now().isAfter(end)) {
      throw TimeoutException('Playback did not advance.');
    }
    await Future<void>.delayed(const Duration(milliseconds: 25));
  }
}

class _StopCompletesStoryTts extends BlockingTextToSpeech {
  @override
  Future<void> stop() async {
    await super.stop();
    if (firstSpeakStarted.isCompleted && !releaseFirstSpeak.isCompleted) {
      releaseFirstSpeak.complete();
    }
  }
}

class _StoryRepository implements AdaptiveRouteStoryRepository {
  List<String> warnings = const [];
  int generations = 0;
  Future<AdaptiveRouteStoryPackState>? generationResult;
  @override
  Future<AdaptiveRouteStoryPackState> generateRouteStoryPack(
    String id,
    GenerateRouteStoryPackRequest request,
  ) {
    generations++;
    return generationResult ?? getRouteStoryPackStatus(id);
  }

  List<String> heard = const [];
  AdaptiveStoryPlaybackOutcomes outcomes =
      const AdaptiveStoryPlaybackOutcomes();
  List<AdaptiveRouteStory> stories = const [];
  final List<String> events = [];
  String? statusOverride;
  RoverApiException? statusError;
  bool refreshing = false;
  bool offlineEvents = false;
  int statusChecks = 0;
  AdaptiveRouteStorySelection? selection;
  int selections = 0;
  NextRouteStoryRequest? lastRequest;
  @override
  Future<AdaptiveRouteStoryPackState> getRouteStoryPackStatus(String id) async {
    statusChecks++;
    if (statusError != null) throw statusError!;
    final now = DateTime.now().toUtc();
    if (statusOverride != null) {
      return AdaptiveRouteStoryPackState(
        walkSessionId: id,
        routeRevision: 1,
        status: statusOverride!,
        updatedUtc: now,
        heardStoryIds: const [],
        savedStoryIds: const [],
        error: statusOverride == 'Failed' ? 'Generation timed out.' : null,
      );
    }
    return AdaptiveRouteStoryPackState(
      walkSessionId: id,
      routeRevision: 1,
      status: refreshing ? 'Generating' : 'Ready',
      updatedUtc: now,
      heardStoryIds: heard,
      playbackOutcomes: outcomes,
      savedStoryIds: const [],
      pack: AdaptiveRouteStoryPack(
        schemaVersion: '3.0',
        packId: 'test',
        idempotencyKey: 'test',
        walkSessionId: id,
        routeId: 'test',
        routeRevision: 1,
        promptVersion: 'test',
        generatedUtc: now,
        expiresUtc: now.add(const Duration(hours: 1)),
        stories: stories,
        warnings: warnings,
      ),
    );
  }

  @override
  Future<AdaptiveRouteStorySelection?> getNextRouteStory(
    String id,
    NextRouteStoryRequest request,
  ) async {
    selections++;
    lastRequest = request;
    return selection;
  }

  @override
  Future<void> recordRouteStoryPlayback(
    String id,
    RouteStoryPlaybackEventRequest request,
  ) async {
    if (offlineEvents) throw const RoverApiConnectionException('Offline');
    events.add(request.kind);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _PlaybackVoice extends RoverVoiceController {
  _PlaybackVoice() : super(walkRepository: _WalkRepository());
  int plays = 0;
  String? lastLength;
  int? maximumSeconds;
  AdaptiveStoryPlaybackResult result = AdaptiveStoryPlaybackResult.completed;
  @override
  bool hasInterruptedAdaptiveStory(String storyId) =>
      result == AdaptiveStoryPlaybackResult.paused;
  @override
  bool canPlayAdaptiveRouteStory(
    AdaptiveRouteStorySelection selection,
    RoamSession session, {
    bool userRequested = false,
    bool interruptNavigation = true,
  }) =>
      maximumSeconds == null ||
      selection.variant.estimatedDurationSeconds <= maximumSeconds!;
  @override
  Future<AdaptiveStoryPlaybackResult> playAdaptiveRouteStoryWithResult(
    AdaptiveRouteStorySelection selection,
    RoamSession session, {
    bool userRequested = false,
  }) async {
    plays++;
    lastLength = selection.variant.length;
    return result;
  }
}

class _PollingInterruptionVoice extends _PlaybackVoice {
  final started = Completer<void>();
  final resumed = Completer<void>();
  final interrupted = Completer<AdaptiveStoryPlaybackResult>();
  int arrivals = 0;
  bool resumable = false;

  @override
  Future<void> syncWithSession(RoamSession session) async {
    if (session.arrivalCandidate && arrivals == 0 && started.isCompleted) {
      arrivals++;
      resumable = true;
      interrupted.complete(AdaptiveStoryPlaybackResult.interrupted);
    }
  }

  @override
  bool hasInterruptedAdaptiveStory(String storyId) => resumable;
  @override
  bool hasAutomaticallyResumableAdaptiveStory(String storyId) => resumable;
  @override
  Future<AdaptiveStoryPlaybackResult> playAdaptiveRouteStoryWithResult(
    AdaptiveRouteStorySelection selection,
    RoamSession session, {
    bool userRequested = false,
  }) async {
    plays++;
    if (plays == 1) {
      started.complete();
      return interrupted.future;
    }
    resumable = false;
    resumed.complete();
    return AdaptiveStoryPlaybackResult.completed;
  }
}
