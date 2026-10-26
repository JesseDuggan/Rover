import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rover/src/location/rover_location.dart';
import 'package:rover/src/memories/memory_store.dart';
import 'package:rover/src/memories/walk_trail_store.dart';

void main() {
  test(
    'GPS trail is local, filtered, timestamped and resumes with a gap',
    () async {
      final root = await Directory.systemTemp.createTemp('walk-trail-test');
      var now = DateTime.utc(2026, 10, 24, 12);
      final memories = MemoryStore(
        directory: Directory('${root.path}/memories'),
      );
      await memories.linkSession('session', 'saved-walk');
      final dir = Directory('${root.path}/trails');
      var store = WalkTrailStore(
        directory: dir,
        now: () => now,
        memoryStore: memories,
      );
      RoverLocationReading reading({
        double latitude = 43,
        double accuracy = 5,
        bool mocked = false,
        DateTime? at,
      }) => RoverLocationReading(
        location: RoverLatLng(latitude: latitude, longitude: 7),
        recordedAtUtc: at ?? now,
        accuracyMeters: accuracy,
        isMocked: mocked,
      );
      await store.record('session', reading(mocked: true));
      await store.record('session', reading(accuracy: 60));
      await store.record(
        'session',
        reading(at: now.subtract(const Duration(minutes: 2))),
      );
      expect(await store.read('session'), isEmpty);
      await store.record('session', reading());
      await store.record('session', reading());
      now = now.add(const Duration(seconds: 10));
      await store.record('session', reading(latitude: 43.0001));
      await store.record('session', reading(latitude: 43.5));
      var points = await store.read('session');
      expect(points, hasLength(2));
      expect(points.first['journeyId'], 'saved-walk');
      expect(points.last['segment'], 0);
      await store.pause('session');
      now = now.add(const Duration(seconds: 10));
      await store.record('session', reading(latitude: 43.0002));
      expect((await store.read('session')).last['segment'], 1);
      await store.close();
      store = WalkTrailStore(
        directory: dir,
        now: () => now,
        memoryStore: memories,
      );
      now = now.add(const Duration(seconds: 10));
      await store.record('session', reading(latitude: 43.0003));
      points = await store.read('session');
      expect(points, hasLength(4));
      expect(points.last['segment'], 2);
      expect(points.last['at'], now.toIso8601String());
      await store.close();
      await root.delete(recursive: true);
    },
  );
}
