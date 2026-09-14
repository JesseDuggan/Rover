import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:rover/src/active_roam/active_roam_controller.dart';
import 'package:rover/src/active_roam/active_roam_repository.dart';
import 'package:rover/src/active_roam/active_roam_session.dart';
import 'package:rover/src/adventure/roam.dart';
import 'package:rover/src/location/rover_location.dart';

void main() {
  test('new installation has no invented route', () async {
    final controller = ActiveRoamController(
      repository: MemoryActiveRoamRepository(),
    );
    await controller.load();
    expect(controller.session.roam.stops, isEmpty);
    expect(controller.session.roam.routeGeometry, isEmpty);
    expect(controller.session.roam.totalEstimatedMinutes, 0);
    expect(controller.session.distanceMilesToNext, 0);
    controller.dispose();
  });

  test('saved route retains its actual stops, geometry, and sources', () {
    const point = RoverLatLng(latitude: 44.678, longitude: -76.395);
    final session = RoamSession.empty().copyWith(
      apiWalkSessionId: 'real-walk',
      roam: const RoverRoam(
        title: 'Westport walk',
        summary: 'Live route',
        walkingMinutes: 12,
        distanceMiles: 0.5,
        startingPoint: 'Westport',
        routeProvider: 'Google',
        walkSessionId: 'real-walk',
        accessibilityNotes: [],
        warnings: [],
        routeGeometry: [point],
        routeManeuvers: [
          RoverRouteManeuver(
            sequenceNumber: 1,
            instruction: 'Head east',
            distanceMeters: 120,
            durationMinutes: 2,
            maneuverType: 'DEPART',
            location: point,
          ),
        ],
        stops: [
          RoverStop(
            id: 'verified-place',
            name: 'Verified place',
            image: '',
            shortDescription: 'Provider description',
            estimatedVisitMinutes: 4,
            coordinates: point,
            category: 'History',
            whySelected: 'Selected interest',
            providerPlaceId: 'provider-id',
            discoveryProviderName: 'GooglePlaces',
            sourceUrl: 'https://example.test/place',
            requiredAttribution: ['Provider'],
          ),
        ],
      ),
    );
    final restored = RoamSession.fromJson(session.toJson());
    expect(restored.apiWalkSessionId, 'real-walk');
    expect(restored.currentStop.id, 'verified-place');
    expect(restored.currentStop.coordinates.latitude, point.latitude);
    expect(restored.currentStop.sourceUrl, 'https://example.test/place');
    expect(restored.currentStop.requiredAttribution, ['Provider']);
    expect(restored.roam.routeGeometry.single.longitude, point.longitude);
    expect(restored.roam.routeManeuvers.single.instruction, 'Head east');
    expect(restored.roam.walkingMinutes, 12);
  });

  test('legacy metadata never reconstructs a demo itinerary', () {
    final data = jsonDecode(
      RoamSession.empty().copyWith(apiWalkSessionId: 'old-walk').toJson(),
    ) as Map<String, dynamic>;
    data.remove('route');
    data['currentStopIndex'] = 4;
    final restored = RoamSession.fromJson(jsonEncode(data));
    expect(restored.roam.stops, isEmpty);
    expect(restored.currentStopIndex, 0);
    expect(restored.apiWalkSessionId, 'old-walk');
  });
}
