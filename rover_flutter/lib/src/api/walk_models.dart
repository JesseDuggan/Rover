import '../adventure/roam.dart';
import '../location/rover_location.dart';

enum WalkStatus {
  created,
  ready,
  inProgress,
  completed,
  cancelled,
  unknown;

  static WalkStatus parse(String? value) {
    return switch (value?.toLowerCase()) {
      'created' => WalkStatus.created,
      'ready' => WalkStatus.ready,
      'inprogress' => WalkStatus.inProgress,
      'completed' => WalkStatus.completed,
      'cancelled' => WalkStatus.cancelled,
      _ => WalkStatus.unknown,
    };
  }
}

enum WalkContentType {
  history,
  architecture,
  foodAndDrink,
  shopping,
  publicArt,
  sponsoredRecommendation,
  unknown;

  static WalkContentType parse(String? value) {
    return switch (value?.toLowerCase()) {
      'history' => WalkContentType.history,
      'architecture' => WalkContentType.architecture,
      'foodanddrink' => WalkContentType.foodAndDrink,
      'shopping' => WalkContentType.shopping,
      'publicart' => WalkContentType.publicArt,
      'sponsoredrecommendation' => WalkContentType.sponsoredRecommendation,
      _ => WalkContentType.unknown,
    };
  }
}

enum WalkContentSource {
  roverEditorial,
  localRecommendation,
  sponsored,
  unknown;

  static WalkContentSource parse(String? value) {
    return switch (value?.toLowerCase()) {
      'rovereditorial' => WalkContentSource.roverEditorial,
      'localrecommendation' => WalkContentSource.localRecommendation,
      'sponsored' => WalkContentSource.sponsored,
      _ => WalkContentSource.unknown,
    };
  }
}

enum StopArrivalState {
  pending,
  arrived,
  unknown;

  static StopArrivalState parse(String? value) {
    return switch (value?.toLowerCase()) {
      'pending' => StopArrivalState.pending,
      'arrived' => StopArrivalState.arrived,
      _ => StopArrivalState.unknown,
    };
  }
}

class CreateWalkRequest {
  const CreateWalkRequest({
    required this.latitude,
    required this.longitude,
    required this.availableMinutes,
    required this.interests,
    required this.walkingPace,
    required this.accessibilityPreferences,
  });

  final double latitude;
  final double longitude;
  final int availableMinutes;
  final List<String> interests;
  final String walkingPace;
  final List<String> accessibilityPreferences;

  Map<String, Object?> toJson() {
    return {
      'latitude': latitude,
      'longitude': longitude,
      'availableMinutes': availableMinutes,
      'interests': interests,
      'walkingPace': walkingPace,
      'accessibilityPreferences': accessibilityPreferences,
    };
  }
}

class WalkSession {
  const WalkSession({
    required this.walkSessionId,
    required this.status,
    required this.startingLocation,
    required this.createdAtUtc,
    required this.availableMinutes,
    required this.estimatedDurationMinutes,
    required this.estimatedDistanceMeters,
    required this.routeSummary,
    required this.interests,
    required this.walkingPace,
    required this.accessibilityPreferences,
    required this.timeRemainingMinutes,
    required this.visitedStopCount,
    required this.walkProgressPercentage,
    required this.stops,
    this.routeRevision = 1,
    this.routeRevisions = const [],
    this.route,
    this.originalRoute,
    this.distanceToNextStopMeters,
    this.routeProgressPercentage = 0,
    this.isOffRoute = false,
    this.distanceFromRouteMeters = 0,
    this.lastKnownLocation,
    this.startedAtUtc,
    this.completedAtUtc,
    this.cancelledAtUtc,
    this.nextStop,
    this.recentNarrationStopId,
    this.recentNarration,
    this.routeQuality,
    this.lifecycleConsistency,
  });

  final String walkSessionId;
  final WalkStatus status;
  final RoverLatLng startingLocation;
  final RoverLatLng? lastKnownLocation;
  final DateTime createdAtUtc;
  final DateTime? startedAtUtc;
  final DateTime? completedAtUtc;
  final DateTime? cancelledAtUtc;
  final int availableMinutes;
  final int estimatedDurationMinutes;
  final int estimatedDistanceMeters;
  final String routeSummary;
  final List<String> interests;
  final String walkingPace;
  final List<String> accessibilityPreferences;
  final int timeRemainingMinutes;
  final int visitedStopCount;
  final double walkProgressPercentage;
  final int routeRevision;
  final List<WalkRouteRevision> routeRevisions;
  final WalkRoute? route;
  final WalkRoute? originalRoute;
  final double? distanceToNextStopMeters;
  final double routeProgressPercentage;
  final bool isOffRoute;
  final double distanceFromRouteMeters;
  final WalkStop? nextStop;
  final String? recentNarrationStopId;
  final WalkStop? recentNarration;
  final RouteQualityDiagnostics? routeQuality;
  final StopLifecycleConsistency? lifecycleConsistency;
  final List<WalkStop> stops;

  bool get isTerminal =>
      status == WalkStatus.completed || status == WalkStatus.cancelled;

  RoverRoam toRoam() {
    return RoverRoam(
      title: 'Rover walk',
      summary: routeSummary,
      walkingMinutes: estimatedDurationMinutes,
      distanceMiles: estimatedDistanceMeters / 1609.344,
      startingPoint: 'Current location',
      stops: stops.map((stop) => stop.toRoverStop()).toList(),
      routeGeometry:
          route?.coordinates ?? stops.map((stop) => stop.coordinates).toList(),
      accessibilityNotes: accessibilityPreferences.isEmpty
          ? const ['No accessibility preferences selected.']
          : accessibilityPreferences,
      warnings: const [
        'Stay aware of traffic, crossings, surfaces, and people around you.',
      ],
      routeProvider: route?.provider ?? 'Unknown',
      routeManeuvers:
          route?.maneuvers
              .map(
                (maneuver) => RoverRouteManeuver(
                  sequenceNumber: maneuver.sequenceNumber,
                  instruction: maneuver.instruction,
                  distanceMeters: maneuver.distanceMeters,
                  durationMinutes: maneuver.durationMinutes,
                  maneuverType: maneuver.maneuverType,
                  location: maneuver.location,
                ),
              )
              .toList() ??
          const [],
      walkSessionId: walkSessionId,
    );
  }

  factory WalkSession.fromJson(Map<String, dynamic> json) {
    final stops = _list(json['stops'])
        .map((item) => WalkStop.fromJson(item as Map<String, dynamic>))
        .toList();
    return WalkSession(
      walkSessionId: json['walkSessionId'] as String,
      status: WalkStatus.parse(json['status'] as String?),
      startingLocation: _location(json['startingLocation']),
      lastKnownLocation: json['lastKnownLocation'] == null
          ? null
          : _location(json['lastKnownLocation']),
      createdAtUtc: DateTime.parse(json['createdAtUtc'] as String),
      startedAtUtc: _date(json['startedAtUtc']),
      completedAtUtc: _date(json['completedAtUtc']),
      cancelledAtUtc: _date(json['cancelledAtUtc']),
      availableMinutes: json['availableMinutes'] as int,
      estimatedDurationMinutes: json['estimatedDurationMinutes'] as int,
      estimatedDistanceMeters: json['estimatedDistanceMeters'] as int,
      routeSummary: json['routeSummary'] as String,
      interests: _stringList(json['interests']),
      walkingPace: json['walkingPace'] as String,
      accessibilityPreferences: _stringList(json['accessibilityPreferences']),
      timeRemainingMinutes: json['timeRemainingMinutes'] as int,
      visitedStopCount: json['visitedStopCount'] as int,
      walkProgressPercentage: (json['walkProgressPercentage'] as num)
          .toDouble(),
      route: json['route'] == null
          ? null
          : WalkRoute.fromJson(json['route'] as Map<String, dynamic>),
      originalRoute: json['originalRoute'] == null
          ? null
          : WalkRoute.fromJson(json['originalRoute'] as Map<String, dynamic>),
      routeRevision: json['routeRevision'] as int? ?? 1,
      routeRevisions: list(json['routeRevisions'])
          .map(
            (item) => WalkRouteRevision.fromJson(item as Map<String, dynamic>),
          )
          .toList(),
      distanceToNextStopMeters: (json['distanceToNextStopMeters'] as num?)
          ?.toDouble(),
      routeProgressPercentage:
          (json['routeProgressPercentage'] as num?)?.toDouble() ?? 0,
      isOffRoute: json['isOffRoute'] as bool? ?? false,
      distanceFromRouteMeters:
          (json['distanceFromRouteMeters'] as num?)?.toDouble() ?? 0,
      nextStop: json['nextStop'] == null
          ? null
          : WalkStop.fromJson(json['nextStop'] as Map<String, dynamic>),
      recentNarrationStopId: json['recentNarrationStopId'] as String?,
      recentNarration: json['recentNarration'] == null
          ? null
          : WalkStop.fromJson(json['recentNarration'] as Map<String, dynamic>),
      routeQuality: json['routeQuality'] == null
          ? null
          : RouteQualityDiagnostics.fromJson(
              json['routeQuality'] as Map<String, dynamic>,
            ),
      lifecycleConsistency: json['lifecycleConsistency'] == null
          ? null
          : StopLifecycleConsistency.fromJson(
              json['lifecycleConsistency'] as Map<String, dynamic>,
            ),
      stops: stops,
    );
  }

  static DateTime? _date(Object? value) {
    return value == null ? null : DateTime.parse(value as String);
  }

  static RoverLatLng _location(Object? value) {
    final json = value as Map<String, dynamic>;
    return RoverLatLng(
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
    );
  }

  static List<dynamic> list(Object? value) => value as List<dynamic>? ?? [];
  static List<String> stringList(Object? value) =>
      list(value).map((item) => item.toString()).toList();

  static List<dynamic> _list(Object? value) => list(value);
  static List<String> _stringList(Object? value) => stringList(value);
}

class RouteQualityDiagnostics {
  const RouteQualityDiagnostics({
    required this.totalRouteDistanceMeters,
    required this.estimatedWalkingTimeMinutes,
    required this.estimatedStopTimeMinutes,
    required this.estimatedExperienceTimeMinutes,
    required this.availableTimeUtilization,
    required this.backtrackingEstimateMeters,
    required this.repeatedSegmentCount,
    required this.returnToStartEstimateMeters,
    required this.warnings,
  });

  final int totalRouteDistanceMeters;
  final int estimatedWalkingTimeMinutes;
  final int estimatedStopTimeMinutes;
  final int estimatedExperienceTimeMinutes;
  final double availableTimeUtilization;
  final int backtrackingEstimateMeters;
  final int repeatedSegmentCount;
  final int returnToStartEstimateMeters;
  final List<String> warnings;

  factory RouteQualityDiagnostics.fromJson(Map<String, dynamic> json) {
    return RouteQualityDiagnostics(
      totalRouteDistanceMeters: json['totalRouteDistanceMeters'] as int? ?? 0,
      estimatedWalkingTimeMinutes:
          json['estimatedWalkingTimeMinutes'] as int? ?? 0,
      estimatedStopTimeMinutes: json['estimatedStopTimeMinutes'] as int? ?? 0,
      estimatedExperienceTimeMinutes:
          json['estimatedExperienceTimeMinutes'] as int? ?? 0,
      availableTimeUtilization:
          (json['availableTimeUtilization'] as num?)?.toDouble() ?? 0,
      backtrackingEstimateMeters:
          json['backtrackingEstimateMeters'] as int? ?? 0,
      repeatedSegmentCount: json['repeatedSegmentCount'] as int? ?? 0,
      returnToStartEstimateMeters:
          json['returnToStartEstimateMeters'] as int? ?? 0,
      warnings: WalkSession.stringList(json['warnings']),
    );
  }
}

class StopLifecycleConsistency {
  const StopLifecycleConsistency({
    required this.isConsistent,
    required this.stopCount,
    required this.routeRevision,
    required this.warnings,
    this.nextStopId,
  });

  final bool isConsistent;
  final int stopCount;
  final int routeRevision;
  final String? nextStopId;
  final List<String> warnings;

  factory StopLifecycleConsistency.fromJson(Map<String, dynamic> json) {
    return StopLifecycleConsistency(
      isConsistent: json['isConsistent'] as bool? ?? false,
      stopCount: json['stopCount'] as int? ?? 0,
      routeRevision: json['routeRevision'] as int? ?? 0,
      nextStopId: json['nextStopId'] as String?,
      warnings: WalkSession.stringList(json['warnings']),
    );
  }
}

class WalkRouteRevision {
  const WalkRouteRevision({
    required this.revision,
    required this.reason,
    required this.appliedAtUtc,
    required this.addedStopIds,
    required this.removedStopIds,
    required this.reorderedStopIds,
  });

  final int revision;
  final String reason;
  final DateTime appliedAtUtc;
  final List<String> addedStopIds;
  final List<String> removedStopIds;
  final List<String> reorderedStopIds;

  factory WalkRouteRevision.fromJson(Map<String, dynamic> json) {
    return WalkRouteRevision(
      revision: json['revision'] as int,
      reason: json['reason'] as String,
      appliedAtUtc: DateTime.parse(json['appliedAtUtc'] as String),
      addedStopIds: WalkSession.stringList(json['addedStopIds']),
      removedStopIds: WalkSession.stringList(json['removedStopIds']),
      reorderedStopIds: WalkSession.stringList(json['reorderedStopIds']),
    );
  }
}

class WalkRoute {
  const WalkRoute({
    required this.routeId,
    required this.provider,
    required this.version,
    required this.generatedAtUtc,
    required this.coordinates,
    required this.bounds,
    required this.distanceMeters,
    required this.durationMinutes,
    this.maneuvers = const [],
  });

  final String routeId;
  final String provider;
  final String version;
  final DateTime generatedAtUtc;
  final List<RoverLatLng> coordinates;
  final WalkRouteBounds bounds;
  final int distanceMeters;
  final int durationMinutes;
  final List<WalkRouteManeuver> maneuvers;

  factory WalkRoute.fromJson(Map<String, dynamic> json) {
    return WalkRoute(
      routeId: json['routeId'] as String,
      provider: json['provider'] as String,
      version: json['version'] as String,
      generatedAtUtc: DateTime.parse(json['generatedAtUtc'] as String),
      coordinates: WalkSession._list(json['coordinates'])
          .map((item) => _coordinate(item as Map<String, dynamic>))
          .toList(),
      bounds: WalkRouteBounds.fromJson(json['bounds'] as Map<String, dynamic>),
      distanceMeters: json['distanceMeters'] as int,
      durationMinutes: json['durationMinutes'] as int,
      maneuvers: WalkSession.list(json['maneuvers'])
          .map(
            (item) => WalkRouteManeuver.fromJson(item as Map<String, dynamic>),
          )
          .toList(),
    );
  }

  static RoverLatLng _coordinate(Map<String, dynamic> json) {
    return RoverLatLng(
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
    );
  }
}

class WalkRouteManeuver {
  const WalkRouteManeuver({
    required this.sequenceNumber,
    required this.instruction,
    required this.distanceMeters,
    required this.durationMinutes,
    this.maneuverType = 'MANEUVER_UNSPECIFIED',
    this.location,
  });

  final int sequenceNumber;
  final String instruction;
  final int distanceMeters;
  final int durationMinutes;
  final String maneuverType;
  final RoverLatLng? location;

  factory WalkRouteManeuver.fromJson(Map<String, dynamic> json) {
    return WalkRouteManeuver(
      sequenceNumber: json['sequenceNumber'] as int,
      instruction: json['instruction'] as String,
      distanceMeters: json['distanceMeters'] as int,
      durationMinutes: json['durationMinutes'] as int,
      maneuverType: json['maneuverType'] as String? ?? 'MANEUVER_UNSPECIFIED',
      location: json['location'] == null
          ? null
          : WalkRoute._coordinate(json['location'] as Map<String, dynamic>),
    );
  }
}

class WalkRouteBounds {
  const WalkRouteBounds({required this.southwest, required this.northeast});

  final RoverLatLng southwest;
  final RoverLatLng northeast;

  factory WalkRouteBounds.fromJson(Map<String, dynamic> json) {
    return WalkRouteBounds(
      southwest: WalkRoute._coordinate(
        json['southwest'] as Map<String, dynamic>,
      ),
      northeast: WalkRoute._coordinate(
        json['northeast'] as Map<String, dynamic>,
      ),
    );
  }
}

class WalkStop {
  const WalkStop({
    required this.stopId,
    required this.sequenceNumber,
    required this.name,
    required this.coordinates,
    required this.shortDescription,
    required this.narration,
    required this.category,
    required this.contentType,
    required this.contentSource,
    required this.estimatedVisitMinutes,
    required this.distanceFromPreviousStopMeters,
    required this.arrivalRadiusMeters,
    required this.visited,
    required this.arrivalState,
    this.address,
    this.websiteUrl,
    this.phoneNumber,
    this.menuUrl,
    this.sponsoredDisclosure,
    this.arrivedAtUtc,
    this.discoveryProviderName,
    this.providerPlaceId,
    this.sourceUrl,
    this.requiredAttribution = const [],
  });

  final String stopId;
  final int sequenceNumber;
  final String name;
  final RoverLatLng coordinates;
  final String shortDescription;
  final String narration;
  final String category;
  final WalkContentType contentType;
  final WalkContentSource contentSource;
  final String? sponsoredDisclosure;
  final int estimatedVisitMinutes;
  final int distanceFromPreviousStopMeters;
  final int arrivalRadiusMeters;
  final bool visited;
  final StopArrivalState arrivalState;
  final String? address;
  final String? websiteUrl;
  final String? phoneNumber;
  final String? menuUrl;
  final DateTime? arrivedAtUtc;
  final String? discoveryProviderName;
  final String? providerPlaceId;
  final String? sourceUrl;
  final List<String> requiredAttribution;

  bool get isSponsored => contentSource == WalkContentSource.sponsored;

  String get contentSourceLabel {
    return switch (contentSource) {
      WalkContentSource.roverEditorial => 'Rover editorial',
      WalkContentSource.localRecommendation => 'Local recommendation',
      WalkContentSource.sponsored => 'Sponsored',
      WalkContentSource.unknown => 'Unknown source',
    };
  }

  RoverStop toRoverStop() {
    return RoverStop(
      id: stopId,
      name: name,
      image: 'api://walk-stop/$stopId',
      shortDescription: shortDescription,
      estimatedVisitMinutes: estimatedVisitMinutes,
      coordinates: coordinates,
      category: category,
      whySelected: narration,
      distanceFromPreviousStopMeters: distanceFromPreviousStopMeters,
      arrivalRadiusMeters: arrivalRadiusMeters,
      audio: narration.isEmpty ? null : 'api://narration/$stopId',
      narration: narration,
      contentType: contentType.name,
      contentSource: contentSourceLabel,
      sponsoredDisclosure: sponsoredDisclosure,
      address: address,
      websiteUrl: websiteUrl,
      phoneNumber: phoneNumber,
      menuUrl: menuUrl,
      discoveryProviderName: discoveryProviderName,
      providerPlaceId: providerPlaceId,
      sourceUrl: sourceUrl,
      requiredAttribution: requiredAttribution,
    );
  }

  factory WalkStop.fromJson(Map<String, dynamic> json) {
    return WalkStop(
      stopId: json['stopId'] as String,
      sequenceNumber: json['sequenceNumber'] as int,
      name: json['name'] as String,
      coordinates: RoverLatLng(
        latitude: (json['latitude'] as num).toDouble(),
        longitude: (json['longitude'] as num).toDouble(),
      ),
      shortDescription: json['shortDescription'] as String,
      narration: json['narration'] as String,
      category: json['category'] as String,
      contentType: WalkContentType.parse(json['contentType'] as String?),
      contentSource: WalkContentSource.parse(json['contentSource'] as String?),
      sponsoredDisclosure: json['sponsoredDisclosure'] as String?,
      estimatedVisitMinutes: json['estimatedVisitMinutes'] as int,
      distanceFromPreviousStopMeters:
          json['distanceFromPreviousStopMeters'] as int,
      arrivalRadiusMeters: json['arrivalRadiusMeters'] as int,
      visited: json['visited'] as bool,
      arrivalState: StopArrivalState.parse(json['arrivalState'] as String?),
      address: json['address'] as String?,
      websiteUrl: json['websiteUrl'] as String?,
      phoneNumber: json['phoneNumber'] as String?,
      menuUrl: json['menuUrl'] as String?,
      arrivedAtUtc: WalkSession._date(json['arrivedAtUtc']),
      discoveryProviderName: json['discoveryProviderName'] as String?,
      providerPlaceId: json['providerPlaceId'] as String?,
      sourceUrl: json['sourceUrl'] as String?,
      requiredAttribution: (json['requiredAttribution'] as List? ?? const [])
          .whereType<String>()
          .toList(growable: false),
    );
  }
}
