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
        final safe = RoamSession.demo().copyWith(
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
  int selections = 0;
  NextRouteStoryRequest? lastRequest;
  @override
  Future<AdaptiveRouteStoryPackState> getRouteStoryPackStatus(String id) async {
    final now = DateTime.now().toUtc();
    return AdaptiveRouteStoryPackState(
      walkSessionId: id,
      routeRevision: 1,
      status: 'Ready',
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
        stories: const [],
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
    return null;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
