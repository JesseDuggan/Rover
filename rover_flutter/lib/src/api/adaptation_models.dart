import '../location/rover_location.dart';
import 'walk_models.dart';

class WalkAdaptationEvaluateRequest {
  const WalkAdaptationEvaluateRequest({
    required this.routeRevision,
    this.location,
    this.requestedType,
    this.availableMinutes,
    this.userRequest,
    this.interest,
    this.proposedDiscoveryId,
    this.dismissedDiscoveryIds = const [],
  });

  final int routeRevision;
  final RoverLatLng? location;
  final String? requestedType;
  final int? availableMinutes;
  final String? userRequest;
  final String? interest;
  final String? proposedDiscoveryId;
  final List<String> dismissedDiscoveryIds;

  WalkAdaptationEvaluateRequest copyWith({
    int? routeRevision,
    RoverLatLng? location,
    String? requestedType,
    int? availableMinutes,
    String? userRequest,
    String? interest,
    String? proposedDiscoveryId,
    List<String>? dismissedDiscoveryIds,
  }) {
    return WalkAdaptationEvaluateRequest(
      routeRevision: routeRevision ?? this.routeRevision,
      location: location ?? this.location,
      requestedType: requestedType ?? this.requestedType,
      availableMinutes: availableMinutes ?? this.availableMinutes,
      userRequest: userRequest ?? this.userRequest,
      interest: interest ?? this.interest,
      proposedDiscoveryId: proposedDiscoveryId ?? this.proposedDiscoveryId,
      dismissedDiscoveryIds:
          dismissedDiscoveryIds ?? this.dismissedDiscoveryIds,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'latitude': location?.latitude,
      'longitude': location?.longitude,
      'routeRevision': routeRevision,
      'requestedType': requestedType,
      'availableMinutes': availableMinutes,
      'userRequest': userRequest,
      'interest': interest,
      'proposedDiscoveryId': proposedDiscoveryId,
      'dismissedDiscoveryIds': dismissedDiscoveryIds,
    };
  }
}

class WalkAdaptationProposal {
  const WalkAdaptationProposal({
    required this.adaptationId,
    required this.walkSessionId,
    required this.type,
    required this.title,
    required this.explanation,
    required this.estimatedAddedMinutes,
    required this.estimatedAddedDistanceMeters,
    required this.estimatedNewTotalMinutes,
    required this.affectedStops,
    required this.addedStops,
    required this.removedStops,
    required this.reorderedStops,
    required this.proposedRoute,
    required this.proposedStops,
    required this.routeRevision,
    required this.proposedRouteRevision,
    required this.createdAtUtc,
    required this.expiresAtUtc,
    required this.status,
  });

  final String adaptationId;
  final String walkSessionId;
  final String type;
  final String title;
  final String explanation;
  final int estimatedAddedMinutes;
  final int estimatedAddedDistanceMeters;
  final int estimatedNewTotalMinutes;
  final List<String> affectedStops;
  final List<String> addedStops;
  final List<String> removedStops;
  final List<String> reorderedStops;
  final WalkRoute proposedRoute;
  final List<WalkStop> proposedStops;
  final int routeRevision;
  final int proposedRouteRevision;
  final DateTime createdAtUtc;
  final DateTime expiresAtUtc;
  final String status;

  bool get isSponsored {
    return proposedStops.any((stop) => stop.isSponsored);
  }

  String get distanceLabel {
    final miles = estimatedAddedDistanceMeters.abs() / 1609.344;
    final sign = estimatedAddedDistanceMeters >= 0 ? '+' : '-';
    return '$sign${miles.toStringAsFixed(1)} mi';
  }

  factory WalkAdaptationProposal.fromJson(Map<String, dynamic> json) {
    return WalkAdaptationProposal(
      adaptationId: json['adaptationId'] as String,
      walkSessionId: json['walkSessionId'] as String,
      type: json['type'] as String,
      title: json['title'] as String,
      explanation: json['explanation'] as String,
      estimatedAddedMinutes: json['estimatedAddedMinutes'] as int,
      estimatedAddedDistanceMeters: json['estimatedAddedDistanceMeters'] as int,
      estimatedNewTotalMinutes: json['estimatedNewTotalMinutes'] as int,
      affectedStops: WalkSession.stringList(json['affectedStops']),
      addedStops: WalkSession.stringList(json['addedStops']),
      removedStops: WalkSession.stringList(json['removedStops']),
      reorderedStops: WalkSession.stringList(json['reorderedStops']),
      proposedRoute: WalkRoute.fromJson(
        json['proposedRoute'] as Map<String, dynamic>,
      ),
      proposedStops: WalkSession.list(json['proposedStops'])
          .map((item) => WalkStop.fromJson(item as Map<String, dynamic>))
          .toList(),
      routeRevision: json['routeRevision'] as int,
      proposedRouteRevision: json['proposedRouteRevision'] as int,
      createdAtUtc: DateTime.parse(json['createdAtUtc'] as String),
      expiresAtUtc: DateTime.parse(json['expiresAtUtc'] as String),
      status: json['status'] as String,
    );
  }
}
