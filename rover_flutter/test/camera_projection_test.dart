import 'package:flutter_test/flutter_test.dart';
import 'package:rover/src/camera_explorer/camera_projection.dart';
import 'package:rover/src/location/rover_location.dart';

void main() {
  const origin = RoverLatLng(latitude: 44.23, longitude: -76.48);

  test('bearing calculation points north and east', () {
    final north = bearingBetween(
      origin,
      const RoverLatLng(latitude: 44.231, longitude: -76.48),
    );
    final east = bearingBetween(
      origin,
      const RoverLatLng(latitude: 44.23, longitude: -76.479),
    );

    expect(north, closeTo(0, 1));
    expect(east, closeTo(90, 1));
  });

  test('relative bearing wraps around zero degrees', () {
    expect(relativeBearing(2, 358), closeTo(4, 0.1));
    expect(relativeBearing(358, 2), closeTo(-4, 0.1));
  });

  test('heading smoothing crosses 359 to 0 without jumping', () {
    final smoothed = smoothHeading(358, 2, smoothing: 0.5);

    expect(smoothed, closeTo(0, 0.1));
  });

  test('field of view filters and positions visible candidates', () {
    final visible = CameraPlaceCandidate(
      id: 'visible',
      name: 'Visible Place',
      coordinates: const RoverLatLng(latitude: 44.231, longitude: -76.48),
      category: 'Landmark',
      description: 'A nearby place.',
      sourceLabel: 'Test',
      confidence: 0.9,
      storyWorthiness: 50,
      storyAvailable: true,
    );
    final hidden = CameraPlaceCandidate(
      id: 'hidden',
      name: 'Hidden Place',
      coordinates: const RoverLatLng(latitude: 44.23, longitude: -76.479),
      category: 'Landmark',
      description: 'An east-side place.',
      sourceLabel: 'Test',
      confidence: 0.9,
      storyWorthiness: 50,
      storyAvailable: true,
    );

    final overlays = projectCameraCandidates(
      userLocation: origin,
      headingDegrees: 0,
      places: [visible, hidden],
      settings: const CameraProjectionSettings(
        horizontalFieldOfViewDegrees: 60,
      ),
    );

    expect(overlays, hasLength(1));
    expect(overlays.single.place.id, 'visible');
    expect(overlays.single.horizontalPosition, closeTo(0.5, 0.05));
  });

  test('ranking prefers current route stop over nearby generic place', () {
    final routeStop = CameraPlaceCandidate(
      id: 'route',
      name: 'Route Stop',
      coordinates: const RoverLatLng(latitude: 44.231, longitude: -76.48),
      category: 'Stop',
      description: 'Current stop.',
      sourceLabel: 'Walk',
      confidence: 0.8,
      storyWorthiness: 30,
      storyAvailable: true,
      isRouteStop: true,
      isCurrentOrNextStop: true,
    );
    final generic = CameraPlaceCandidate(
      id: 'generic',
      name: 'Generic Place',
      coordinates: const RoverLatLng(latitude: 44.2308, longitude: -76.48),
      category: 'Place',
      description: 'Closer place.',
      sourceLabel: 'Test',
      confidence: 0.9,
      storyWorthiness: 60,
      storyAvailable: true,
    );

    final overlays = projectCameraCandidates(
      userLocation: origin,
      headingDegrees: 0,
      places: [generic, routeStop],
    );

    expect(overlays.first.place.id, 'route');
  });

  test('label suppression limits visible overlays', () {
    final places = List.generate(
      8,
      (index) => CameraPlaceCandidate(
        id: 'place-$index',
        name: 'Place $index',
        coordinates: RoverLatLng(
          latitude: 44.231 + index * 0.00001,
          longitude: -76.48,
        ),
        category: 'Place',
        description: 'Nearby.',
        sourceLabel: 'Test',
        confidence: 0.7,
        storyWorthiness: 20,
        storyAvailable: true,
      ),
    );

    final overlays = projectCameraCandidates(
      userLocation: origin,
      headingDegrees: 0,
      places: places,
      settings: const CameraProjectionSettings(maximumVisibleLabels: 3),
    );

    expect(overlays, hasLength(3));
  });
}
