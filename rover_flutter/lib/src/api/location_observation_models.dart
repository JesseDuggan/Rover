import '../location/rover_location.dart';
import 'location_story_models.dart';

class LocationObservationResolveRequest {
  const LocationObservationResolveRequest({
    required this.recognizedText,
    required this.location,
    required this.radiusMeters,
    required this.nearbyPlaceIds,
    this.accuracyMeters,
    this.headingDegrees,
    this.routeId,
  });

  final String recognizedText;
  final RoverLatLng location;
  final double? accuracyMeters;
  final double? headingDegrees;
  final int radiusMeters;
  final String? routeId;
  final List<String> nearbyPlaceIds;

  Map<String, Object?> toJson() => {
    'recognizedText': recognizedText,
    'latitude': location.latitude,
    'longitude': location.longitude,
    'accuracyMeters': accuracyMeters,
    'headingDegrees': headingDegrees,
    'radiusMeters': radiusMeters,
    'routeId': routeId,
    'nearbyPlaceIds': nearbyPlaceIds,
  };
}

enum LocationObservationResolutionStatus {
  verified,
  ambiguous,
  unresolved;

  static LocationObservationResolutionStatus parse(String? value) {
    return switch (value?.toLowerCase()) {
      'verified' => verified,
      'ambiguous' => ambiguous,
      _ => unresolved,
    };
  }
}

class LocationObservationCandidate {
  const LocationObservationCandidate({
    required this.place,
    required this.matchConfidence,
    required this.nameSimilarity,
    required this.distanceScore,
    required this.headingScore,
    required this.matchReasons,
  });

  final LocationPlaceSummary place;
  final double matchConfidence;
  final double nameSimilarity;
  final double distanceScore;
  final double headingScore;
  final List<String> matchReasons;

  factory LocationObservationCandidate.fromJson(Map<String, dynamic> json) {
    return LocationObservationCandidate(
      place: LocationPlaceSummary.fromJson(
        json['place'] as Map<String, dynamic>? ?? const {},
      ),
      matchConfidence: (json['matchConfidence'] as num?)?.toDouble() ?? 0,
      nameSimilarity: (json['nameSimilarity'] as num?)?.toDouble() ?? 0,
      distanceScore: (json['distanceScore'] as num?)?.toDouble() ?? 0,
      headingScore: (json['headingScore'] as num?)?.toDouble() ?? 0,
      matchReasons: (json['matchReasons'] as List? ?? const [])
          .whereType<String>()
          .toList(),
    );
  }
}

class LocationObservationResolution {
  const LocationObservationResolution({
    required this.status,
    required this.candidates,
    required this.diagnosticCode,
    required this.warnings,
    this.selectedPlaceId,
  });

  final LocationObservationResolutionStatus status;
  final String? selectedPlaceId;
  final List<LocationObservationCandidate> candidates;
  final String diagnosticCode;
  final List<String> warnings;

  LocationObservationCandidate? get selectedCandidate {
    final id = selectedPlaceId;
    if (id == null) {
      return null;
    }
    for (final candidate in candidates) {
      if (candidate.place.canonicalId == id) {
        return candidate;
      }
    }
    return null;
  }

  factory LocationObservationResolution.fromJson(Map<String, dynamic> json) {
    return LocationObservationResolution(
      status: LocationObservationResolutionStatus.parse(
        json['status'] as String?,
      ),
      selectedPlaceId: json['selectedPlaceId'] as String?,
      candidates: (json['candidates'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(LocationObservationCandidate.fromJson)
          .toList(),
      diagnosticCode:
          json['diagnosticCode'] as String? ?? 'observation_unresolved',
      warnings: (json['warnings'] as List? ?? const [])
          .whereType<String>()
          .toList(),
    );
  }
}
