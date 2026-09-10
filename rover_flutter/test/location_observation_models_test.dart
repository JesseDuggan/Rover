import 'package:flutter_test/flutter_test.dart';
import 'package:rover/src/api/location_observation_models.dart';
import 'package:rover/src/location/rover_location.dart';

void main() {
  test('observation request contains text context but no image data', () {
    const request = LocationObservationResolveRequest(
      recognizedText: 'HOME HARDWARE',
      location: RoverLatLng(latitude: 44.678, longitude: -76.395),
      accuracyMeters: 4,
      headingDegrees: 90,
      radiusMeters: 1500,
      routeId: 'walk-1',
      nearbyPlaceIds: ['mapbox-home-hardware'],
    );

    final json = request.toJson();

    expect(json['recognizedText'], 'HOME HARDWARE');
    expect(json['latitude'], 44.678);
    expect(json['nearbyPlaceIds'], ['mapbox-home-hardware']);
    expect(
      json.keys.where(
        (key) =>
            key.toLowerCase().contains('image') ||
            key.toLowerCase().contains('photo') ||
            key.toLowerCase().contains('bytes'),
      ),
      isEmpty,
    );
  });

  test('verified response preserves address confidence and attribution', () {
    final resolution = LocationObservationResolution.fromJson({
      'status': 'Verified',
      'selectedPlaceId': 'mapbox-home-hardware',
      'diagnosticCode': 'observation_verified',
      'warnings': <String>[],
      'candidates': [
        {
          'place': {
            'canonicalId': 'mapbox-home-hardware',
            'name': 'Home Hardware',
            'coordinates': {'latitude': 44.6781, 'longitude': -76.3951},
            'address': '1 Hardware Street, Westport, ON',
            'categories': ['hardware'],
            'shortDescription': 'A sourced nearby hardware business.',
            'openingStatus': 'open',
            'accessibilityInformation': 'wheelchair access: yes',
            'facts': [
              {
                'factId': 'mapbox:home-hardware:summary',
                'factType': 'poi_summary',
                'factText': 'Home Hardware is listed near Hardware Street.',
                'confidenceScore': 0.78,
                'isSuitableForNarration': true,
              },
            ],
            'storyWorthinessReasons': <String>[],
            'sourceReferences': [
              {'providerName': 'Mapbox', 'attribution': 'Mapbox service terms'},
            ],
            'confidenceScore': 0.84,
            'storyWorthinessScore': 42,
          },
          'matchConfidence': 0.94,
          'nameSimilarity': 1.0,
          'distanceScore': 0.96,
          'headingScore': 0.88,
          'matchReasons': ['recognized text closely matches the place name'],
        },
      ],
    });

    expect(resolution.status, LocationObservationResolutionStatus.verified);
    expect(resolution.selectedCandidate?.place.name, 'Home Hardware');
    expect(
      resolution.selectedCandidate?.place.address,
      '1 Hardware Street, Westport, ON',
    );
    expect(
      resolution.selectedCandidate?.place.sourceReferences.single.providerName,
      'Mapbox',
    );
    expect(resolution.selectedCandidate?.place.openingStatus, 'open');
    expect(
      resolution.selectedCandidate?.place.accessibilityInformation,
      'wheelchair access: yes',
    );
    expect(
      resolution.selectedCandidate?.place.facts.single.factText,
      contains('Hardware Street'),
    );
  });

  test('ambiguous response never auto-selects a candidate', () {
    final resolution = LocationObservationResolution.fromJson({
      'status': 'Ambiguous',
      'selectedPlaceId': null,
      'diagnosticCode': 'observation_ambiguous',
      'warnings': <String>[],
      'candidates': <Object>[],
    });

    expect(resolution.status, LocationObservationResolutionStatus.ambiguous);
    expect(resolution.selectedCandidate, isNull);
  });
}
