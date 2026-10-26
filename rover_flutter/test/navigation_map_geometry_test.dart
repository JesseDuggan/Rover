import 'package:flutter_test/flutter_test.dart';
import 'package:rover/src/location/rover_location.dart';
import 'package:rover/src/maps/navigation_map_geometry.dart';

void main() {
  const start = RoverLatLng(latitude: 43, longitude: 7);
  const corner = RoverLatLng(latitude: 43.001, longitude: 7);
  const end = RoverLatLng(latitude: 43.001, longitude: 7.001);
  test('compass smoothing takes the short path across north', () {
    expect(smoothMapHeading(359, 1), closeTo(359.6, .001));
    expect(smoothMapHeading(1, 359), closeTo(.4, .001));
  });
  test('route split preserves corners and joins at the projected location', () {
    final split = splitNavigationRoute([start, corner, end],
        const RoverLatLng(latitude: 43.0005, longitude: 7.00001));
    expect(split.completed.last.latitude, closeTo(43.0005, .000001));
    expect(split.completed.last.longitude, 7);
    expect(split.upcoming[1], corner);
    expect(split.upcoming.last, end);
    expect(split.completed.last, split.upcoming.first);
  });
  test('overview and empty routes do not acquire a completed section', () {
    expect(splitNavigationRoute([start, end], null).completed, isEmpty);
    expect(splitNavigationRoute([], start).upcoming, isEmpty);
    expect(liveRouteProgress([start, start], start), isNull);
  });
  test('live progress updates along geometry but rejects distant GPS', () {
    expect(liveRouteProgress([start, corner],
        const RoverLatLng(latitude: 43.0005, longitude: 7)), closeTo(50, .1));
    expect(liveRouteProgress([start, corner],
        const RoverLatLng(latitude: 43.0005, longitude: 7.01)), isNull);
  });
}
