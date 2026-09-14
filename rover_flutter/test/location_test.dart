import 'support/location_fixtures.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:rover/src/location/location_controller.dart';
import 'package:rover/src/location/rover_location.dart';
import 'package:rover/src/maps/google_maps_config.dart';
import 'package:rover/src/maps/mapbox_config.dart';
import 'package:rover/src/maps/rover_map_provider.dart';

void main() {
  test('simulated provider uses the same interface as real location', () async {
    final provider = SimulatedLocationProvider();

    expect(provider, isA<RoverLocationProvider>());
    expect(provider.requestsSystemPermission, isFalse);

    final first = await provider.getCurrentLocation();
    provider.moveNext();
    final second = await provider.getCurrentLocation();

    expect(first.isSuccess, isTrue);
    expect(second.isSuccess, isTrue);
    expect(second.location.toString(), isNot(first.location.toString()));
  });

  test('location controller defaults to device location', () async {
    final realLocation = const RoverLatLng(
      latitude: 44.678,
      longitude: -76.395,
    );
    final controller = LocationController(
      realProvider: _FakeLocationProvider(realLocation),
    );

    final result = await controller.ensureDeviceLocation();

    expect(result.location, realLocation);
    expect(controller.location, realLocation);
  });

  test('permission failures include recovery instructions', () async {
    const failures = [
      LocationFailure(
        kind: LocationFailureKind.servicesDisabled,
        message: 'off',
      ),
      LocationFailure(kind: LocationFailureKind.denied, message: 'denied'),
      LocationFailure(
        kind: LocationFailureKind.permanentlyDenied,
        message: 'blocked',
      ),
    ];

    for (final failure in failures) {
      expect(failure.recovery, isNotEmpty);
    }
  });

  test('map provider prefers Google and retains explicit Mapbox fallback', () {
    const mock = RoverMapProvider(
      google: GoogleMapsConfig(apiKey: ''),
      mapbox: MapboxConfig(publicToken: ''),
    );
    const googleBacked = RoverMapProvider(
      google: GoogleMapsConfig(apiKey: 'android-restricted-key'),
      mapbox: MapboxConfig(publicToken: 'pk.configured-at-runtime'),
    );
    const mapboxFallback = RoverMapProvider(
      google: GoogleMapsConfig(apiKey: ''),
      mapbox: MapboxConfig(publicToken: 'pk.configured-at-runtime'),
    );
    const forcedMapbox = RoverMapProvider(
      google: GoogleMapsConfig(apiKey: 'android-restricted-key'),
      mapbox: MapboxConfig(publicToken: 'pk.configured-at-runtime'),
      preferredProvider: 'mapbox',
    );

    expect(mock.mockMode, isTrue);
    expect(googleBacked.mode, RoverMapMode.google);
    expect(mapboxFallback.mode, RoverMapMode.mapbox);
    expect(forcedMapbox.mode, RoverMapMode.mapbox);
    expect(mock.developmentMessage, contains('GOOGLE_MAPS_ANDROID_API_KEY'));
  });
}

class _FakeLocationProvider implements RoverLocationProvider {
  const _FakeLocationProvider(this.location);

  final RoverLatLng location;

  @override
  String get label => 'Fake real provider';

  @override
  bool get requestsSystemPermission => true;

  @override
  Future<bool> isLocationServiceEnabled() async => true;

  @override
  Future<LocationFailure?> checkPermissionStatus() async => null;

  @override
  Future<LocationFailure?> requestForegroundPermission() async => null;

  @override
  Future<bool> openSettings() async => true;

  @override
  Future<RoverLocationResult> getCurrentLocation() async {
    return RoverLocationResult.success(location);
  }

  @override
  Stream<RoverLocationReading> watchLocation() async* {
    yield RoverLocationReading(
      location: location,
      recordedAtUtc: DateTime.utc(2026, 8, 27, 15),
    );
  }
}
