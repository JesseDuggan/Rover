import 'support/route_fixtures.dart';

import 'dart:io';

import 'package:flutter/services.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:rover/src/active_roam/active_roam_session.dart';
import 'package:rover/src/adaptive_stories/adaptive_route_story_controller.dart';
import 'package:rover/src/adaptive_stories/adaptive_route_story_device_cache.dart';
import 'package:rover/src/api/adaptive_route_story_models.dart';
import 'package:rover/src/api/walk_repository.dart';
import 'package:rover/src/location/rover_location.dart';
import 'package:rover/src/voice/rover_voice_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('ai.myrover.rover/voice'),
        (_) async => null,
      );
  test(
    'ready stories can be read outside their automatic window without playback',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'story-manual-test',
      );
      final story = AdaptiveRouteStory.fromJson({
        'storyId': 'sourced-story',
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

  test('manual story selection preserves arrival audio priority', () async {
    final directory = await Directory.systemTemp.createTemp(
      'story-arrival-test',
    );
    final story = AdaptiveRouteStory.fromJson({
      'storyId': 'sourced-story',
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
    final voice = RoverVoiceController(walkRepository: _WalkRepository());
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
        'Waiting for turn or arrival to clear',
      );
      expect(controller.selectStory(story.storyId, session), isTrue);
      await controller.playCurrent(session, voice);
      expect(controller.errorMessage, contains('waiting for enough time'));
      expect(controller.currentSelection!.variant.narration, 'Sourced text.');
      expect(repository.events, isEmpty);
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
      expect(repository.statusChecks, 2);
      expect(controller.readinessLabel, 'failed');
      expect(controller.errorMessage, 'Generation timed out.');
      expect(controller.researchStatus, 'Generation timed out.');
      controller.dispose();
      disposed = true;
      await Future<void>.delayed(const Duration(milliseconds: 5200));
      expect(repository.statusChecks, 2);
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

  test('completed audio cannot replay when server status is stale', () async {
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
    );
    final voice = _PlaybackVoice();
    try {
      final session = demoSession().copyWith(
        apiWalkSessionId: 'walk-test',
        status: RoamSessionStatus.active,
        distanceToNextStopMeters: 500,
        routeProgressPercentage: 25,
      );
      await controller.syncWithSession(session, voice);
      await controller.syncWithSession(
        session.copyWith(routeProgressPercentage: 50),
        voice,
      );
      expect(voice.plays, 1);
      expect(repository.lastRequest!.excludedStoryIds, contains('story-1'));
      expect(controller.currentSelection, isNull);
    } finally {
      controller.dispose();
      voice.dispose();
      cache.dispose();
      await directory.delete(recursive: true);
    }
  });
  test(
    'selection retries after arrival clears without progress changing',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'route-retry-test',
      );
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
        expect(repository.selections, 1);
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
        expect(repository.selections, 2);
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
        expect(repository.lastRequest?.secondsUntilNextManeuver, 36);
      } finally {
        controller.dispose();
        voice.dispose();
        cache.dispose();
        await directory.delete(recursive: true);
      }
    },
  );
}

class _WalkRepository implements WalkRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _StoryRepository implements AdaptiveRouteStoryRepository {
  List<AdaptiveRouteStory> stories = const [];
  final List<String> events = [];
  String? statusOverride;
  bool refreshing = false;
  int statusChecks = 0;
  AdaptiveRouteStorySelection? selection;
  int selections = 0;
  NextRouteStoryRequest? lastRequest;
  @override
  Future<AdaptiveRouteStoryPackState> getRouteStoryPackStatus(String id) async {
    statusChecks++;
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
      heardStoryIds: const [],
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
        warnings: const [],
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
    events.add(request.kind);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _PlaybackVoice extends RoverVoiceController {
  _PlaybackVoice() : super(walkRepository: _WalkRepository());
  int plays = 0;
  @override
  bool canPlayAdaptiveRouteStory(
    AdaptiveRouteStorySelection selection,
    RoamSession session, {
    bool userRequested = false,
  }) => true;
  @override
  Future<bool> playAdaptiveRouteStory(
    AdaptiveRouteStorySelection selection,
    RoamSession session, {
    bool userRequested = false,
  }) async {
    plays++;
    return true;
  }
}
