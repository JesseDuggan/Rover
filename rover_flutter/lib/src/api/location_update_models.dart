import '../location/rover_location.dart';
import 'walk_models.dart';

class LocationUpdateRequest {
  const LocationUpdateRequest({
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

  Map<String, Object?> toJson() {
    return {
      'latitude': location.latitude,
      'longitude': location.longitude,
      'accuracyMeters': accuracyMeters,
      'headingDegrees': headingDegrees,
      'speedMetersPerSecond': speedMetersPerSecond,
      'recordedAtUtc': recordedAtUtc.toUtc().toIso8601String(),
    };
  }
}

class LocationUpdateResult {
  const LocationUpdateResult({
    required this.walkSessionId,
    required this.status,
    required this.accepted,
    required this.routeProgressPercentage,
    required this.estimatedMinutesRemaining,
    required this.isOffRoute,
    required this.distanceFromRouteMeters,
    required this.arrivalCandidate,
    required this.arrivalCandidateReadingCount,
    required this.serverTimestampUtc,
    this.nextStop,
    this.distanceToNextStopMeters,
    this.arrivalCandidateStopId,
    this.confirmedArrival,
  });

  final String walkSessionId;
  final WalkStatus status;
  final bool accepted;
  final WalkStop? nextStop;
  final double? distanceToNextStopMeters;
  final double routeProgressPercentage;
  final int estimatedMinutesRemaining;
  final bool isOffRoute;
  final double distanceFromRouteMeters;
  final bool arrivalCandidate;
  final int arrivalCandidateReadingCount;
  final String? arrivalCandidateStopId;
  final WalkStop? confirmedArrival;
  final DateTime serverTimestampUtc;

  factory LocationUpdateResult.fromJson(Map<String, dynamic> json) {
    return LocationUpdateResult(
      walkSessionId: json['walkSessionId'] as String,
      status: WalkStatus.parse(json['status'] as String?),
      accepted: json['accepted'] as bool,
      nextStop: json['nextStop'] == null
          ? null
          : WalkStop.fromJson(json['nextStop'] as Map<String, dynamic>),
      distanceToNextStopMeters: (json['distanceToNextStopMeters'] as num?)
          ?.toDouble(),
      routeProgressPercentage: (json['routeProgressPercentage'] as num)
          .toDouble(),
      estimatedMinutesRemaining: json['estimatedMinutesRemaining'] as int,
      isOffRoute: json['isOffRoute'] as bool,
      distanceFromRouteMeters: (json['distanceFromRouteMeters'] as num)
          .toDouble(),
      arrivalCandidate: json['arrivalCandidate'] as bool,
      arrivalCandidateReadingCount:
          json['arrivalCandidateReadingCount'] as int? ?? 0,
      arrivalCandidateStopId: json['arrivalCandidateStopId'] as String?,
      confirmedArrival: json['confirmedArrival'] == null
          ? null
          : WalkStop.fromJson(json['confirmedArrival'] as Map<String, dynamic>),
      serverTimestampUtc: DateTime.parse(json['serverTimestampUtc'] as String),
    );
  }
}
