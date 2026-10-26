import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
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
    this.isMocked = false,
  });

  final RoverLatLng location;
  final DateTime recordedAtUtc;
  final double? accuracyMeters;
  final double? headingDegrees;
  final double? speedMetersPerSecond;
  final bool isMocked;
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
  const GeolocatorLocationProvider({this.backgroundWalking = false});

  final bool backgroundWalking;

  LocationSettings navigationSettings({required bool mapVisible}) {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return AndroidSettings(
        accuracy: mapVisible ? LocationAccuracy.bestForNavigation : LocationAccuracy.high,
        distanceFilter: mapVisible ? 1 : 10,
        intervalDuration: Duration(seconds: mapVisible ? 1 : 10),
        foregroundNotificationConfig: backgroundWalking
            ? const ForegroundNotificationConfig(
                notificationTitle: 'Walk About is walking with you',
                notificationText: 'Open Walk About for live navigation.',
                notificationChannelName: 'Active walks',
                enableWakeLock: false,
                setOngoing: true,
              )
            : null,
      );
    }
    return LocationSettings(
      accuracy: mapVisible ? LocationAccuracy.bestForNavigation : LocationAccuracy.high,
      distanceFilter: mapVisible ? 1 : 10,
    );
  }

  Stream<RoverLocationReading> watchNavigationLocation({required bool mapVisible}) async* {
    if (backgroundWalking && !kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      await const MethodChannel('ai.myrover.rover/voice')
          .invokeMethod<void>('walkingNotificationPermission');
    }
    yield* Geolocator.getPositionStream(
      locationSettings: navigationSettings(mapVisible: mapVisible),
    ).map(_readingFromPosition);
  }

  LocationSettings get streamSettings {
    if (!kIsWeb &&
        defaultTargetPlatform == TargetPlatform.android &&
        backgroundWalking) {
      return AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 2,
        intervalDuration: const Duration(seconds: 5),
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: 'Walk About is walking with you',
          notificationText: 'Location and stories stay active with the screen locked. Open Walk About to pause or end.',
          notificationChannelName: 'Active walks',
          enableWakeLock: true,
          setOngoing: true,
        ),
      );
    }
    return const LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 2,
    );
  }

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
  Stream<RoverLocationReading> watchLocation() async* {
    if (backgroundWalking &&
        !kIsWeb &&
        defaultTargetPlatform == TargetPlatform.android) {
      await const MethodChannel('ai.myrover.rover/voice')
          .invokeMethod<void>('walkingNotificationPermission');
    }
    yield* Geolocator.getPositionStream(locationSettings: streamSettings)
        .map(_readingFromPosition);
  }

  static RoverLocationReading _readingFromPosition(Position position) {
    return RoverLocationReading(
      location: RoverLatLng(
        latitude: position.latitude,
        longitude: position.longitude,
      ),
      recordedAtUtc: position.timestamp.toUtc(),
      isMocked: position.isMocked,
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
