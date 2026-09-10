import 'package:geolocator/geolocator.dart';

class RoverLatLng {
  const RoverLatLng({required this.latitude, required this.longitude});

  final double latitude;
  final double longitude;

  @override
  String toString() {
    return '${latitude.toStringAsFixed(5)}, ${longitude.toStringAsFixed(5)}';
  }

  double distanceTo(RoverLatLng other) {
    return Geolocator.distanceBetween(
      latitude,
      longitude,
      other.latitude,
      other.longitude,
    );
  }
}

class RoverLocationReading {
  const RoverLocationReading({
    required this.location,
    required this.recordedAtUtc,
    this.accuracyMeters,
    this.headingDegrees,
    this.speedMetersPerSecond,
  });

  final RoverLatLng location;
  final DateTime recordedAtUtc;
  final double? accuracyMeters;
  final double? headingDegrees;
  final double? speedMetersPerSecond;
}

enum LocationFailureKind {
  servicesDisabled,
  denied,
  permanentlyDenied,
  unknown,
}

class LocationFailure {
  const LocationFailure({required this.kind, required this.message});

  final LocationFailureKind kind;
  final String message;

  String get recovery {
    return switch (kind) {
      LocationFailureKind.servicesDisabled =>
        'Turn on Location Services in system settings, then try again.',
      LocationFailureKind.denied =>
        'Allow foreground location when Android prompts, then try again.',
      LocationFailureKind.permanentlyDenied =>
        'Open app settings and allow location for ROVER.',
      LocationFailureKind.unknown => 'Check Location Services, then try again.',
    };
  }
}

class RoverLocationResult {
  const RoverLocationResult._({this.location, this.failure});

  final RoverLatLng? location;
  final LocationFailure? failure;

  bool get isSuccess => location != null;

  static RoverLocationResult success(RoverLatLng location) {
    return RoverLocationResult._(location: location);
  }

  static RoverLocationResult failed(LocationFailure failure) {
    return RoverLocationResult._(failure: failure);
  }
}

abstract class RoverLocationProvider {
  String get label;
  bool get requestsSystemPermission;
  Future<bool> isLocationServiceEnabled() async => true;
  Future<LocationFailure?> checkPermissionStatus() async => null;
  Future<LocationFailure?> requestForegroundPermission() async => null;
  Future<bool> openSettings() async => Geolocator.openAppSettings();
  Future<RoverLocationResult> getCurrentLocation();
  Stream<RoverLocationReading> watchLocation() async* {
    final result = await getCurrentLocation();
    if (result.location != null) {
      yield RoverLocationReading(
        location: result.location!,
        recordedAtUtc: DateTime.now().toUtc(),
      );
    }
  }
}

class GeolocatorLocationProvider implements RoverLocationProvider {
  const GeolocatorLocationProvider();

  @override
  String get label => 'Device location';

  @override
  bool get requestsSystemPermission => true;

  @override
  Future<bool> openSettings() {
    return Geolocator.openAppSettings();
  }

  @override
  Future<bool> isLocationServiceEnabled() {
    return Geolocator.isLocationServiceEnabled();
  }

  @override
  Future<LocationFailure?> checkPermissionStatus() async {
    final servicesEnabled = await Geolocator.isLocationServiceEnabled();
    if (!servicesEnabled) {
      return const LocationFailure(
        kind: LocationFailureKind.servicesDisabled,
        message: 'Location Services are turned off.',
      );
    }

    final permission = await Geolocator.checkPermission();
    return _failureForPermission(permission);
  }

  @override
  Future<LocationFailure?> requestForegroundPermission() async {
    final servicesEnabled = await Geolocator.isLocationServiceEnabled();
    if (!servicesEnabled) {
      return const LocationFailure(
        kind: LocationFailureKind.servicesDisabled,
        message: 'Location Services are turned off.',
      );
    }

    final permission = await Geolocator.requestPermission();
    return _failureForPermission(permission);
  }

  @override
  Future<RoverLocationResult> getCurrentLocation() async {
    try {
      final existingFailure = await checkPermissionStatus();
      if (existingFailure != null &&
          existingFailure.kind != LocationFailureKind.denied) {
        return RoverLocationResult.failed(existingFailure);
      }

      if (existingFailure?.kind == LocationFailureKind.denied) {
        final requestedFailure = await requestForegroundPermission();
        if (requestedFailure != null) {
          return RoverLocationResult.failed(requestedFailure);
        }
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      return RoverLocationResult.success(
        RoverLatLng(latitude: position.latitude, longitude: position.longitude),
      );
    } on Exception {
      return RoverLocationResult.failed(
        const LocationFailure(
          kind: LocationFailureKind.unknown,
          message: 'ROVER could not read the current location.',
        ),
      );
    }
  }

  @override
  Stream<RoverLocationReading> watchLocation() {
    return Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 2,
      ),
    ).map(_readingFromPosition);
  }

  static RoverLocationReading _readingFromPosition(Position position) {
    return RoverLocationReading(
      location: RoverLatLng(
        latitude: position.latitude,
        longitude: position.longitude,
      ),
      recordedAtUtc: position.timestamp.toUtc(),
      accuracyMeters: position.accuracy,
      headingDegrees: position.heading.isNaN || position.heading < 0
          ? null
          : position.heading,
      speedMetersPerSecond: position.speed.isNaN ? null : position.speed,
    );
  }

  static LocationFailure? _failureForPermission(LocationPermission permission) {
    return switch (permission) {
      LocationPermission.denied => const LocationFailure(
        kind: LocationFailureKind.denied,
        message: 'ROVER does not have foreground location permission yet.',
      ),
      LocationPermission.deniedForever => const LocationFailure(
        kind: LocationFailureKind.permanentlyDenied,
        message: 'Location permission is blocked for ROVER.',
      ),
      LocationPermission.whileInUse || LocationPermission.always => null,
      LocationPermission.unableToDetermine => const LocationFailure(
        kind: LocationFailureKind.unknown,
        message: 'ROVER could not determine location permission.',
      ),
    };
  }
}

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
