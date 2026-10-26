import 'package:latlong2/latlong.dart';

import '../location/rover_location.dart';

/// Small directional chevrons sampled only from the provider's route geometry.
List<List<RoverLatLng>> routeArrowStrokes(List<RoverLatLng> route) {
  const distance = Distance(roundResult: false);
  final strokes = <List<RoverLatLng>>[];
  var remaining = 40.0;
  for (var i = 1; i < route.length && strokes.length < 120; i++) {
    final a = LatLng(route[i - 1].latitude, route[i - 1].longitude);
    final b = LatLng(route[i].latitude, route[i].longitude);
    final length = distance(a, b);
    if (!length.isFinite || length < .1) continue;
    final bearing = distance.bearing(a, b);
    while (remaining <= length && strokes.length < 120) {
      final tip = distance.offset(a, remaining, bearing);
      final left = distance.offset(tip, 7, bearing + 150);
      final right = distance.offset(tip, 7, bearing - 150);
      strokes.add([
        for (final p in [left, tip, right])
          RoverLatLng(latitude: p.latitude, longitude: p.longitude),
      ]);
      remaining += 80;
    }
    remaining -= length;
  }
  return strokes;
}
