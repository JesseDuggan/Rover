import 'dart:math' as math;

import '../location/rover_location.dart';

class CameraProjectionSettings {
  const CameraProjectionSettings({
    this.horizontalFieldOfViewDegrees = 60,
    this.maximumVisibleLabels = 5,
    this.maximumIdentificationDistanceMeters = 1200,
    this.minimumHeadingAccuracyDegrees = 35,
    this.headingSmoothing = 0.22,
  });

  final double horizontalFieldOfViewDegrees;
  final int maximumVisibleLabels;
  final double maximumIdentificationDistanceMeters;
  final double minimumHeadingAccuracyDegrees;
  final double headingSmoothing;
}

class CameraPlaceCandidate {
  const CameraPlaceCandidate({
    required this.id,
    required this.name,
    required this.coordinates,
    required this.category,
    required this.description,
    required this.sourceLabel,
    required this.confidence,
    required this.storyWorthiness,
    required this.storyAvailable,
    this.isRouteStop = false,
    this.isCurrentOrNextStop = false,
    this.addToWalkId,
    this.address,
    this.websiteUrl,
    this.phoneNumber,
    this.menuUrl,
    this.openingStatus,
    this.accessibilityInformation,
    this.facts = const [],
    this.sourceAttribution = const [],
    this.factIds = const [],
  });

  final String id;
  final String name;
  final RoverLatLng coordinates;
  final String category;
  final String description;
  final String sourceLabel;
  final double confidence;
  final double storyWorthiness;
  final bool storyAvailable;
  final bool isRouteStop;
  final bool isCurrentOrNextStop;
  final String? addToWalkId;
  final String? address;
  final String? websiteUrl;
  final String? phoneNumber;
  final String? menuUrl;
  final String? openingStatus;
  final String? accessibilityInformation;
  final List<String> facts;
  final List<String> sourceAttribution;
  final List<String> factIds;
}

class CameraOverlayCandidate {
  const CameraOverlayCandidate({
    required this.place,
    required this.distanceMeters,
    required this.bearingDegrees,
    required this.relativeBearingDegrees,
    required this.horizontalPosition,
    required this.relativeDirection,
    required this.rankScore,
  });

  final CameraPlaceCandidate place;
  final double distanceMeters;
  final double bearingDegrees;
  final double relativeBearingDegrees;
  final double horizontalPosition;
  final String relativeDirection;
  final double rankScore;
}

double bearingBetween(RoverLatLng from, RoverLatLng to) {
  final lat1 = _radians(from.latitude);
  final lat2 = _radians(to.latitude);
  final deltaLongitude = _radians(to.longitude - from.longitude);
  final y = math.sin(deltaLongitude) * math.cos(lat2);
  final x =
      math.cos(lat1) * math.sin(lat2) -
      math.sin(lat1) * math.cos(lat2) * math.cos(deltaLongitude);
  return normalizeDegrees(_degrees(math.atan2(y, x)));
}

double normalizeDegrees(double degrees) {
  final normalized = degrees % 360;
  return normalized < 0 ? normalized + 360 : normalized;
}

double relativeBearing(double bearingDegrees, double headingDegrees) {
  final value = normalizeDegrees(bearingDegrees - headingDegrees);
  return value > 180 ? value - 360 : value;
}

double smoothHeading(
  double previousHeading,
  double nextHeading, {
  double smoothing = 0.22,
}) {
  final delta = relativeBearing(nextHeading, previousHeading);
  return normalizeDegrees(previousHeading + delta * smoothing);
}

List<CameraOverlayCandidate> projectCameraCandidates({
  required RoverLatLng userLocation,
  required double headingDegrees,
  required List<CameraPlaceCandidate> places,
  CameraProjectionSettings settings = const CameraProjectionSettings(),
}) {
  final halfFov = settings.horizontalFieldOfViewDegrees / 2;
  final projected = <CameraOverlayCandidate>[];
  for (final place in places) {
    if (place.coordinates.latitude == 0 && place.coordinates.longitude == 0) {
      continue;
    }

    final distance = userLocation.distanceTo(place.coordinates);
    if (distance > settings.maximumIdentificationDistanceMeters) {
      continue;
    }

    final bearing = bearingBetween(userLocation, place.coordinates);
    final relative = relativeBearing(bearing, headingDegrees);
    if (relative.abs() > halfFov) {
      continue;
    }

    final horizontalPosition =
        ((relative + halfFov) / settings.horizontalFieldOfViewDegrees)
            .clamp(0.06, 0.94)
            .toDouble();
    final routeBoost = place.isCurrentOrNextStop
        ? 80
        : place.isRouteStop
        ? 40
        : 0;
    final score =
        routeBoost +
        place.storyWorthiness +
        place.confidence * 25 -
        distance / 40 -
        relative.abs();
    projected.add(
      CameraOverlayCandidate(
        place: place,
        distanceMeters: distance,
        bearingDegrees: bearing,
        relativeBearingDegrees: relative,
        horizontalPosition: horizontalPosition,
        relativeDirection: directionLabel(relative),
        rankScore: score,
      ),
    );
  }

  projected.sort((left, right) => right.rankScore.compareTo(left.rankScore));
  return projected.take(settings.maximumVisibleLabels).toList(growable: false);
}

String directionLabel(double relativeDegrees) {
  if (relativeDegrees.abs() <= 8) {
    return 'Ahead';
  }
  if (relativeDegrees > 0 && relativeDegrees <= 30) {
    return 'Ahead right';
  }
  if (relativeDegrees < 0 && relativeDegrees >= -30) {
    return 'Ahead left';
  }
  return relativeDegrees > 0 ? 'Right edge' : 'Left edge';
}

String distanceLabel(double meters) {
  if (meters < 1000) {
    return '${meters.round()} m';
  }
  return '${(meters / 1000).toStringAsFixed(1)} km';
}

double _radians(double degrees) => degrees * math.pi / 180;
double _degrees(double radians) => radians * 180 / math.pi;
