import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../location/rover_location.dart';
import 'journey_coverage.dart';

String previewPace(String value) => switch (value.toLowerCase()) {
  '' || 'easy' || 'leisurely' || 'relaxed' => 'Leisurely',
  'brisk' => 'Brisk',
  _ => 'Standard',
};

Future<LatLng> currentWalkStart() async {
  final result = await const GeolocatorLocationProvider().getCurrentLocation();
  final point = result.location;
  if (point == null)
    throw StateError(result.failure?.recovery ?? 'Choose a start on the map.');
  return LatLng(point.latitude, point.longitude);
}

class WalkingPreview extends StatelessWidget {
  const WalkingPreview({
    super.key,
    required this.plan,
    required this.geometry,
    required this.budget,
    required this.first,
    required this.firstName,
    required this.names,
  });
  final Map<String, dynamic> plan;
  final List<LatLng> geometry;
  final int budget;
  final LatLng first;
  final String firstName;
  final List<String> names;

  @override
  Widget build(BuildContext context) {
    final path = JourneyCoverage(geometry);
    final distance = plan['distanceMeters'] as int;
    final walking = plan['walkingMinutes'] as int;
    final visiting = plan['visitMinutes'] as int;
    final total = walking + visiting;
    final fraction = path.total > 0
        ? path.project(first).along / path.total
        : 0.0;
    final approach = (distance * fraction).round();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Walking route preview',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        Text('${(distance / 1000).toStringAsFixed(2)} km · About $total min'),
        Text('$walking min walking + $visiting min at stops'),
        Text(
          total > budget
              ? '${total - budget} min over your $budget min budget'
              : '${budget - total} min to spare in your $budget min budget',
        ),
        Text(
          approach < 20
              ? 'Start at $firstName'
              : 'First destination: $firstName · $approach m (about ${(walking * fraction).ceil()} min from your start)',
        ),
        if (names.isNotEmpty)
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Text('Stops in order (${names.length})'),
            children: [
              for (final (i, name) in names.indexed)
                ListTile(leading: Text('${i + 1}'), title: Text(name)),
            ],
          ),
      ],
    );
  }
}
