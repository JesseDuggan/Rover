import 'package:rover/src/location/rover_location.dart';

class SimulatedLocationProvider implements RoverLocationProvider {
  SimulatedLocationProvider({
    this.route = const [
      RoverLatLng(latitude: 37.7879, longitude: -122.4075),
      RoverLatLng(latitude: 37.7880, longitude: -122.4075),
      RoverLatLng(latitude: 37.7879, longitude: -122.4074),
      RoverLatLng(latitude: 37.7885, longitude: -122.4058),
    ],
  });

  final List<RoverLatLng> route;
  int _index = 0;

  @override
  String get label => 'Developer simulator';

  @override
  bool get requestsSystemPermission => false;

  @override
  Future<bool> isLocationServiceEnabled() async => true;

  @override
  Future<LocationFailure?> checkPermissionStatus() async => null;

  @override
  Future<LocationFailure?> requestForegroundPermission() async => null;

  @override
  Future<bool> openSettings() async => true;

  RoverLatLng get current => route[_index];

  void moveNext() {
    _index = (_index + 1) % route.length;
  }

  void reset() {
    _index = 0;
  }

  @override
  Future<RoverLocationResult> getCurrentLocation() async {
    return RoverLocationResult.success(current);
  }

  @override
  Stream<RoverLocationReading> watchLocation() async* {
    for (final point in route) {
      yield RoverLocationReading(
        location: point,
        recordedAtUtc: DateTime.now().toUtc(),
        accuracyMeters: 8,
        speedMetersPerSecond: 1.2,
      );
    }
  }
}
