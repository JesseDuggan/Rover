import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:rover/src/api/location_story_models.dart';
import 'package:rover/src/just_walking/just_walking_controller.dart';
import 'package:rover/src/location/rover_location.dart';

import 'api_walk_test.dart' show FakeWalkRepository;

class NearbyRepository extends FakeWalkRepository {
  int searches = 0;
  Completer<LocationStoryContext>? pending;
  final context = LocationStoryContext.fromJson({
    'rankedPlaces': [
      {
        'canonicalId': 'cafe',
        'name': 'Coffee Club',
        'coordinates': {'latitude': 50.0, 'longitude': 8.0},
        'facts': [
          {'factId': 'history', 'text': 'Documented history.'},
        ],
        'sourceReferences': [
          {'providerName': 'Archive', 'attribution': 'Archive'},
        ],
      },
      {
        'canonicalId': 'unsourced',
        'name': 'No sources',
        'coordinates': {'latitude': 50.0, 'longitude': 8.0},
      },
    ],
  });

  @override
  Future<LocationStoryContext> getLocationContext({
    required double latitude,
    required double longitude,
    required int radiusMeters,
    String? routeId,
  }) async {
    searches++;
    expect(routeId, isNull);
    expect(radiusMeters, 500);
    return pending == null ? context : pending!.future;
  }
}

void main() {
  test('failed research has a cooldown without marking place heard', () async {
    var time = DateTime.utc(2026, 10, 3);
    var attempts = 0;
    final controller = JustWalkingController(
      repository: NearbyRepository(),
      clock: () => time,
      narrate: (_, _) async {
        attempts++;
        return false;
      },
    );
    Future<void> tick() => controller.update(
      RoverLocationReading(
        location: const RoverLatLng(latitude: 50, longitude: 8),
        accuracyMeters: 5,
        recordedAtUtc: time,
      ),
    );
    await tick();
    time = time.add(const Duration(minutes: 2));
    await tick();
    expect(attempts, 1);
    expect(controller.heard, isEmpty);
    time = time.add(const Duration(minutes: 9));
    await tick();
    expect(attempts, 2);
    controller.dispose();
  });
  test('research status survives response serialization', () {
    final result = LocationStoryResponse.fromJson({'researchStatus': 'empty'});
    expect(result.researchStatus, 'empty');
    expect(
      LocationStoryResponse.fromJson(result.toJson()).researchStatus,
      'empty',
    );
  });
  var now = DateTime.utc(2026, 10, 3, 12);
  RoverLocationReading reading({double accuracy = 5, double latitude = 50}) =>
      RoverLocationReading(
        location: RoverLatLng(latitude: latitude, longitude: 8),
        recordedAtUtc: now,
        accuracyMeters: accuracy,
      );

  test(
    'route-free nearby stories play once and searches are bounded',
    () async {
      final repository = NearbyRepository();
      var plays = 0;
      final controller = JustWalkingController(
        repository: repository,
        clock: () => now,
        narrate: (_, _) async {
          plays++;
          return true;
        },
      );
      await controller.update(reading(accuracy: 80));
      expect(repository.searches, 0);
      await controller.update(reading());
      expect(controller.places, hasLength(1));
      expect(plays, 1);
      expect(controller.heard, contains('cafe'));
      expect(controller.status, 'All current nearby stories heard');
      await controller.update(reading(), refresh: true);
      expect(repository.searches, 1);
      now = now.add(const Duration(minutes: 4));
      await controller.update(reading());
      expect(repository.searches, 2);
      expect(plays, 1);
      expect(repository.calls, isNot(contains('createWalk')));
      controller.dispose();
    },
  );

  test('paused searches cannot trigger late audio', () async {
    final repository = NearbyRepository()..pending = Completer();
    var plays = 0;
    final controller = JustWalkingController(
      repository: repository,
      clock: () => now,
      narrate: (_, _) async {
        plays++;
        return true;
      },
    );
    final work = controller.update(reading());
    controller.setPaused(true);
    repository.pending!.complete(repository.context);
    await work;
    expect(plays, 0);
    expect(controller.status, 'Paused');
    controller.dispose();
  });

  test('moving away while research runs prevents automatic playback', () async {
    final repository = NearbyRepository()..pending = Completer();
    var plays = 0;
    final controller = JustWalkingController(
      repository: repository,
      clock: () => now,
      narrate: (_, _) async {
        plays++;
        return true;
      },
    );
    final work = controller.update(reading());
    await controller.update(reading(latitude: 50.01));
    repository.pending!.complete(repository.context);
    await work;
    expect(plays, 0);
    controller.dispose();
  });

  test('failed or paused playback never marks a story heard', () async {
    final repository = NearbyRepository();
    final completion = Completer<bool>();
    final controller = JustWalkingController(
      repository: repository,
      clock: () => now,
      narrate: (_, _) => completion.future,
    );
    final work = controller.update(reading());
    await Future<void>.delayed(Duration.zero);
    controller.setPaused(true);
    completion.complete(true);
    await work;
    expect(controller.heard, isEmpty);
    controller.dispose();
  });
}
