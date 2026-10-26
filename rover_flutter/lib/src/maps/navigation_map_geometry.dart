import 'dart:math' as math;
import '../location/rover_location.dart';

double smoothMapHeading(double previous, double next) =>
    (previous + ((next - previous + 540) % 360 - 180) * .3) % 360;

double? liveRouteProgress(List<RoverLatLng> route, RoverLatLng position) {
  final split = splitNavigationRoute(route, position);
  if (split.completed.isEmpty || position.distanceTo(split.completed.last) > 50) return null;
  double length(List<RoverLatLng> points) {
    var meters = 0.0;
    for (var i = 1; i < points.length; i++) {
      meters += points[i - 1].distanceTo(points[i]);
    }
    return meters;
  }
  final completed = length(split.completed);
  final total = completed + length(split.upcoming);
  return total == 0 ? null : completed / total * 100;
}

/// Project onto provider geometry, so the route never cuts across a corner.
({List<RoverLatLng> completed, List<RoverLatLng> upcoming}) splitNavigationRoute(
  List<RoverLatLng> route, RoverLatLng? position,
) {
  if (position == null || route.length < 2) {
    return (completed: const [], upcoming: route);
  }
  final scale = math.cos(position.latitude * math.pi / 180);
  var best = double.infinity;
  var index = 0;
  var point = route.first;
  for (var i = 0; i < route.length - 1; i++) {
    final a = route[i];
    final b = route[i + 1];
    final dx = (b.longitude - a.longitude) * scale;
    final dy = b.latitude - a.latitude;
    final length = dx * dx + dy * dy;
    final t = length == 0 ? 0.0 :
        (((position.longitude - a.longitude) * scale * dx +
          (position.latitude - a.latitude) * dy) / length).clamp(0.0, 1.0);
    final projected = RoverLatLng(
      latitude: a.latitude + (b.latitude - a.latitude) * t,
      longitude: a.longitude + (b.longitude - a.longitude) * t,
    );
    final distance = position.distanceTo(projected);
    if (distance < best) {
      best = distance;
      index = i;
      point = projected;
    }
  }
  return (
    completed: [...route.take(index + 1), point],
    upcoming: [point, ...route.skip(index + 1)],
  );
}
