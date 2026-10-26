import 'package:flutter_test/flutter_test.dart';
import 'package:rover/src/active_roam/active_roam_session.dart';
import 'package:rover/src/adaptive_stories/story_walking_gap.dart';
import 'package:rover/src/location/rover_location.dart';

import 'support/route_fixtures.dart';

void main() {
  final start = DateTime.utc(2026, 10, 19);
  RoamSession position(double north, {double accuracy = 5}) =>
      demoSession().copyWith(
        status: RoamSessionStatus.active,
        currentGpsAccuracyMeters: accuracy,
        simulatedLocation: RoverLatLng(latitude: 52 + north, longitude: 4),
      );

  test('first story is immediate; completed stories require 50 metres', () {
    final gap = StoryWalkingGap();
    expect(gap.ready, isTrue);
    gap.completed(position(0), start);
    gap.observe(position(0.0002), start.add(const Duration(seconds: 15)));
    expect(gap.ready, isFalse);
    gap.observe(position(0.0005), start.add(const Duration(seconds: 35)));
    expect(gap.ready, isTrue);
    gap.completed(position(0.0005), start.add(const Duration(seconds: 40)));
    expect(gap.ready, isFalse);
    gap.reset();
    expect(gap.ready, isTrue);
  });

  test(
    'jitter, teleports, inaccurate GPS and tracking outages do not count',
    () {
      final gap = StoryWalkingGap()..completed(position(0), start);
      for (var i = 1; i <= 10; i++) {
        gap.observe(
          position(i.isEven ? 0.00002 : 0),
          start.add(Duration(seconds: i)),
        );
      }
      expect(gap.remainingMeters, 50);
      gap.observe(position(0.01), start.add(const Duration(seconds: 11)));
      expect(gap.remainingMeters, 50);
      gap.observe(
        position(0.02, accuracy: 100),
        start.add(const Duration(seconds: 20)),
      );
      gap.observe(position(0.03), start.add(const Duration(seconds: 30)));
      expect(gap.remainingMeters, 50);
      gap.observe(position(0.031), start.add(const Duration(seconds: 100)));
      expect(gap.remainingMeters, 50);
    },
  );

  test('movement while paused does not count', () {
    final gap = StoryWalkingGap()..completed(position(0), start);
    gap.observe(
      position(0.0005).copyWith(status: RoamSessionStatus.paused),
      start.add(const Duration(seconds: 30)),
    );
    gap.observe(position(0.001), start.add(const Duration(seconds: 60)));
    expect(gap.remainingMeters, 50);
  });
}
