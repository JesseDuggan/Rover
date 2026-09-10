import 'dart:convert';
import 'dart:math' as math;

import '../api/adaptation_models.dart';
import '../api/walk_models.dart'
    show RouteQualityDiagnostics, StopLifecycleConsistency;
import '../adventure/roam.dart';
import '../location/rover_location.dart';

enum RoamSessionStatus { notStarted, active, paused, completed, ended }

enum AudioPlaybackStatus { stopped, playing, paused }

class RoverNavigationGuidance {
  const RoverNavigationGuidance({
    required this.maneuver,
    required this.distanceMeters,
  });

  final RoverRouteManeuver maneuver;
  final int distanceMeters;
}

class RoamSession {
  const RoamSession({
    required this.roam,
    required this.status,
    required this.currentStopIndex,
    required this.completedStopIds,
    required this.skippedStopIds,
    required this.simulatedLocation,
    required this.audioStatus,
    required this.screenAwake,
    required this.arrivedAtCurrentStop,
    this.apiWalkSessionId,
    this.apiStatus,
    this.timeRemainingMinutes,
    this.progressPercentage,
    this.routeProgressPercentage,
    this.distanceToNextStopMeters,
    this.isOffRoute = false,
    this.distanceFromRouteMeters = 0,
    this.arrivalCandidate = false,
    this.arrivalCandidateReadingCount = 0,
    this.currentGpsAccuracyMeters,
    this.currentHeadingDegrees,
    this.arrivalCandidateStopId,
    this.recentNarrationStopId,
    this.recentNarrationStopOverride,
    this.geofenceEntryDebug,
    this.routeRevision = 1,
    this.routeQuality,
    this.lifecycleConsistency,
    this.pendingAdaptation,
    this.dismissedDiscoveryIds = const {},
    this.savedDiscoveryIds = const {},
    this.narratedArrivalStopIds = const {},
    this.errorMessage,
  });

  final RoverRoam roam;
  final RoamSessionStatus status;
  final int currentStopIndex;
  final Set<String> completedStopIds;
  final Set<String> skippedStopIds;
  final RoverLatLng simulatedLocation;
  final AudioPlaybackStatus audioStatus;
  final bool screenAwake;
  final bool arrivedAtCurrentStop;
  final String? apiWalkSessionId;
  final String? apiStatus;
  final int? timeRemainingMinutes;
  final double? progressPercentage;
  final double? routeProgressPercentage;
  final double? distanceToNextStopMeters;
  final bool isOffRoute;
  final double distanceFromRouteMeters;
  final bool arrivalCandidate;
  final int arrivalCandidateReadingCount;
  final double? currentGpsAccuracyMeters;
  final double? currentHeadingDegrees;
  final String? arrivalCandidateStopId;
  final String? recentNarrationStopId;
  final RoverStop? recentNarrationStopOverride;
  final String? geofenceEntryDebug;
  final int routeRevision;
  final RouteQualityDiagnostics? routeQuality;
  final StopLifecycleConsistency? lifecycleConsistency;
  final WalkAdaptationProposal? pendingAdaptation;
  final Set<String> dismissedDiscoveryIds;
  final Set<String> savedDiscoveryIds;
  final Set<String> narratedArrivalStopIds;
  final String? errorMessage;

  RoverStop get currentStop => roam.stops[currentStopIndex];

  double get storyArrivalBoundaryMeters =>
      currentStop.arrivalRadiusMeters +
      (currentGpsAccuracyMeters ?? 0).clamp(0, 25);

  int? get storySecondsUntilInterruption {
    final turn = storyNavigationGuidance?.distanceMeters.toDouble();
    final stop = distanceToNextStopMeters;
    final arrival = stop == null
        ? null
        : math.max(0.0, stop - storyArrivalBoundaryMeters);
    final distance = turn == null
        ? arrival
        : arrival == null
        ? turn
        : math.min(turn, arrival);
    return distance == null ? null : (distance / 1.3).floor();
  }

  bool get isNearRecentNarrationStop {
    final stop = recentNarrationStop;
    if (stop == null) return false;
    final accuracy = (currentGpsAccuracyMeters ?? 0).clamp(0, 25);
    final distanceMeters =
        _distanceBetween(simulatedLocation, stop.coordinates) * 1609.344;
    return distanceMeters <= stop.arrivalRadiusMeters + accuracy + 15;
  }

  RoverStop? get recentNarrationStop {
    final override = recentNarrationStopOverride;
    if (override != null) {
      return override;
    }

    final stopId = recentNarrationStopId;
    if (stopId == null) {
      return null;
    }
    for (final stop in roam.stops) {
      if (stop.id == stopId) {
        return stop;
      }
    }
    return null;
  }

  RoverStop? get nextStop {
    final nextIndex = currentStopIndex + 1;
    return nextIndex >= roam.stops.length ? null : roam.stops[nextIndex];
  }

  double get progress {
    if (roam.stops.isEmpty) {
      return 0;
    }
    return progressPercentage != null
        ? progressPercentage! / 100
        : (completedStopIds.length + skippedStopIds.length) / roam.stops.length;
  }

  double get distanceMilesToNext {
    final target = arrivedAtCurrentStop
        ? nextStop?.coordinates
        : currentStop.coordinates;
    if (target == null) {
      return 0;
    }
    return _distanceBetween(simulatedLocation, target);
  }

  int get estimatedMinutesToNext {
    if (distanceMilesToNext == 0) {
      return 0;
    }
    final minutes = (distanceMilesToNext / 2.7 * 60).round();
    return math.max(1, minutes);
  }

  List<OrderedRoverStop> get orderedStops => roam.orderedStops;

  RoverNavigationGuidance? get navigationGuidance => _navigationGuidance();

  RoverNavigationGuidance? get storyNavigationGuidance =>
      _navigationGuidance(skipDeparture: true);

  RoverNavigationGuidance? _navigationGuidance({bool skipDeparture = false}) {
    if (status != RoamSessionStatus.active ||
        isOffRoute ||
        !roam.routeProvider.toLowerCase().startsWith('google') ||
        roam.routeManeuvers.isEmpty) {
      return null;
    }

    final totalDistance = roam.routeManeuvers.fold<int>(
      0,
      (total, maneuver) => total + maneuver.distanceMeters,
    );
    if (totalDistance <= 0) {
      return null;
    }

    final travelled =
        totalDistance *
        ((routeProgressPercentage ?? progressPercentage ?? 0) / 100);
    var maneuverStart = 0.0;
    for (final maneuver in roam.routeManeuvers) {
      final remaining = maneuverStart - travelled;
      final isArrival =
          maneuver.maneuverType.contains('DESTINATION') ||
          maneuver.instruction.toLowerCase().contains('destination');
      final isDeparture = maneuver.maneuverType.toUpperCase() == 'DEPART';
      if (!isArrival && !(skipDeparture && isDeparture) && remaining >= -12) {
        return RoverNavigationGuidance(
          maneuver: maneuver,
          distanceMeters: math.max(0, remaining.round()),
        );
      }
      maneuverStart += maneuver.distanceMeters;
    }
    return null;
  }

  RoamSession copyWith({
    RoverRoam? roam,
    RoamSessionStatus? status,
    int? currentStopIndex,
    Set<String>? completedStopIds,
    Set<String>? skippedStopIds,
    RoverLatLng? simulatedLocation,
    AudioPlaybackStatus? audioStatus,
    bool? screenAwake,
    bool? arrivedAtCurrentStop,
    String? apiWalkSessionId,
    String? apiStatus,
    int? timeRemainingMinutes,
    double? progressPercentage,
    double? routeProgressPercentage,
    double? distanceToNextStopMeters,
    bool? isOffRoute,
    double? distanceFromRouteMeters,
    bool? arrivalCandidate,
    int? arrivalCandidateReadingCount,
    double? currentGpsAccuracyMeters,
    double? currentHeadingDegrees,
    String? arrivalCandidateStopId,
    bool clearArrivalCandidateStopId = false,
    String? recentNarrationStopId,
    RoverStop? recentNarrationStopOverride,
    bool clearRecentNarrationStopId = false,
    String? geofenceEntryDebug,
    int? routeRevision,
    RouteQualityDiagnostics? routeQuality,
    StopLifecycleConsistency? lifecycleConsistency,
    WalkAdaptationProposal? pendingAdaptation,
    bool clearPendingAdaptation = false,
    Set<String>? dismissedDiscoveryIds,
    Set<String>? savedDiscoveryIds,
    Set<String>? narratedArrivalStopIds,
    String? errorMessage,
  }) {
    return RoamSession(
      roam: roam ?? this.roam,
      status: status ?? this.status,
      currentStopIndex: currentStopIndex ?? this.currentStopIndex,
      completedStopIds: completedStopIds ?? this.completedStopIds,
      skippedStopIds: skippedStopIds ?? this.skippedStopIds,
      simulatedLocation: simulatedLocation ?? this.simulatedLocation,
      audioStatus: audioStatus ?? this.audioStatus,
      screenAwake: screenAwake ?? this.screenAwake,
      arrivedAtCurrentStop: arrivedAtCurrentStop ?? this.arrivedAtCurrentStop,
      apiWalkSessionId: apiWalkSessionId ?? this.apiWalkSessionId,
      apiStatus: apiStatus ?? this.apiStatus,
      timeRemainingMinutes: timeRemainingMinutes ?? this.timeRemainingMinutes,
      progressPercentage: progressPercentage ?? this.progressPercentage,
      routeProgressPercentage:
          routeProgressPercentage ?? this.routeProgressPercentage,
      distanceToNextStopMeters:
          distanceToNextStopMeters ?? this.distanceToNextStopMeters,
      isOffRoute: isOffRoute ?? this.isOffRoute,
      distanceFromRouteMeters:
          distanceFromRouteMeters ?? this.distanceFromRouteMeters,
      arrivalCandidate: arrivalCandidate ?? this.arrivalCandidate,
      arrivalCandidateReadingCount:
          arrivalCandidateReadingCount ?? this.arrivalCandidateReadingCount,
      currentGpsAccuracyMeters:
          currentGpsAccuracyMeters ?? this.currentGpsAccuracyMeters,
      currentHeadingDegrees:
          currentHeadingDegrees ?? this.currentHeadingDegrees,
      arrivalCandidateStopId: clearArrivalCandidateStopId
          ? null
          : arrivalCandidateStopId ?? this.arrivalCandidateStopId,
      recentNarrationStopId: clearRecentNarrationStopId
          ? null
          : recentNarrationStopId ?? this.recentNarrationStopId,
      recentNarrationStopOverride: clearRecentNarrationStopId
          ? null
          : recentNarrationStopOverride ?? this.recentNarrationStopOverride,
      geofenceEntryDebug: geofenceEntryDebug ?? this.geofenceEntryDebug,
      routeRevision: routeRevision ?? this.routeRevision,
      routeQuality: routeQuality ?? this.routeQuality,
      lifecycleConsistency: lifecycleConsistency ?? this.lifecycleConsistency,
      pendingAdaptation: clearPendingAdaptation
          ? null
          : pendingAdaptation ?? this.pendingAdaptation,
      dismissedDiscoveryIds:
          dismissedDiscoveryIds ?? this.dismissedDiscoveryIds,
      savedDiscoveryIds: savedDiscoveryIds ?? this.savedDiscoveryIds,
      narratedArrivalStopIds:
          narratedArrivalStopIds ?? this.narratedArrivalStopIds,
      errorMessage: errorMessage,
    );
  }

  String toJson() {
    return jsonEncode({
      'status': status.name,
      'currentStopIndex': currentStopIndex,
      'completedStopIds': completedStopIds.toList(),
      'skippedStopIds': skippedStopIds.toList(),
      'latitude': simulatedLocation.latitude,
      'longitude': simulatedLocation.longitude,
      'audioStatus': audioStatus.name,
      'screenAwake': screenAwake,
      'arrivedAtCurrentStop': arrivedAtCurrentStop,
      'apiWalkSessionId': apiWalkSessionId,
      'apiStatus': apiStatus,
      'timeRemainingMinutes': timeRemainingMinutes,
      'progressPercentage': progressPercentage,
      'routeProgressPercentage': routeProgressPercentage,
      'distanceToNextStopMeters': distanceToNextStopMeters,
      'isOffRoute': isOffRoute,
      'distanceFromRouteMeters': distanceFromRouteMeters,
      'arrivalCandidate': arrivalCandidate,
      'arrivalCandidateReadingCount': arrivalCandidateReadingCount,
      'currentGpsAccuracyMeters': currentGpsAccuracyMeters,
      'currentHeadingDegrees': currentHeadingDegrees,
      'arrivalCandidateStopId': arrivalCandidateStopId,
      'recentNarrationStopId': recentNarrationStopId,
      'geofenceEntryDebug': geofenceEntryDebug,
      'routeRevision': routeRevision,
      'dismissedDiscoveryIds': dismissedDiscoveryIds.toList(),
      'savedDiscoveryIds': savedDiscoveryIds.toList(),
      'narratedArrivalStopIds': narratedArrivalStopIds.toList(),
      'errorMessage': errorMessage,
    });
  }

  static RoamSession fromJson(String source) {
    final data = jsonDecode(source) as Map<String, dynamic>;
    final roam = MockRouteGenerationService.activeSanFranciscoDemo();
    return RoamSession(
      roam: roam,
      status: RoamSessionStatus.values.byName(data['status'] as String),
      currentStopIndex: data['currentStopIndex'] as int,
      completedStopIds: Set<String>.from(data['completedStopIds'] as List),
      skippedStopIds: Set<String>.from(data['skippedStopIds'] as List),
      simulatedLocation: RoverLatLng(
        latitude: (data['latitude'] as num).toDouble(),
        longitude: (data['longitude'] as num).toDouble(),
      ),
      audioStatus: AudioPlaybackStatus.values.byName(
        data['audioStatus'] as String,
      ),
      screenAwake: data['screenAwake'] as bool,
      arrivedAtCurrentStop: data['arrivedAtCurrentStop'] as bool,
      apiWalkSessionId: data['apiWalkSessionId'] as String?,
      apiStatus: data['apiStatus'] as String?,
      timeRemainingMinutes: data['timeRemainingMinutes'] as int?,
      progressPercentage: (data['progressPercentage'] as num?)?.toDouble(),
      routeProgressPercentage: (data['routeProgressPercentage'] as num?)
          ?.toDouble(),
      distanceToNextStopMeters: (data['distanceToNextStopMeters'] as num?)
          ?.toDouble(),
      isOffRoute: data['isOffRoute'] as bool? ?? false,
      distanceFromRouteMeters:
          (data['distanceFromRouteMeters'] as num?)?.toDouble() ?? 0,
      arrivalCandidate: data['arrivalCandidate'] as bool? ?? false,
      arrivalCandidateReadingCount:
          data['arrivalCandidateReadingCount'] as int? ?? 0,
      currentGpsAccuracyMeters: (data['currentGpsAccuracyMeters'] as num?)
          ?.toDouble(),
      currentHeadingDegrees: (data['currentHeadingDegrees'] as num?)
          ?.toDouble(),
      arrivalCandidateStopId: data['arrivalCandidateStopId'] as String?,
      recentNarrationStopId: data['recentNarrationStopId'] as String?,
      geofenceEntryDebug: data['geofenceEntryDebug'] as String?,
      routeRevision: data['routeRevision'] as int? ?? 1,
      routeQuality: null,
      lifecycleConsistency: null,
      dismissedDiscoveryIds: Set<String>.from(
        data['dismissedDiscoveryIds'] as List? ?? const [],
      ),
      savedDiscoveryIds: Set<String>.from(
        data['savedDiscoveryIds'] as List? ?? const [],
      ),
      narratedArrivalStopIds: Set<String>.from(
        data['narratedArrivalStopIds'] as List? ?? const [],
      ),
      errorMessage: data['errorMessage'] as String?,
    );
  }

  static RoamSession demo() {
    final roam = MockRouteGenerationService.activeSanFranciscoDemo();
    return RoamSession(
      roam: roam,
      status: RoamSessionStatus.notStarted,
      currentStopIndex: 0,
      completedStopIds: const {},
      skippedStopIds: const {},
      simulatedLocation: roam.stops.first.coordinates,
      audioStatus: AudioPlaybackStatus.stopped,
      screenAwake: false,
      arrivedAtCurrentStop: true,
      timeRemainingMinutes: roam.totalEstimatedMinutes,
      progressPercentage: 0,
      routeProgressPercentage: 0,
      distanceToNextStopMeters: 0,
      routeRevision: 1,
      savedDiscoveryIds: const {},
    );
  }

  static double _distanceBetween(RoverLatLng a, RoverLatLng b) {
    final latMiles = (a.latitude - b.latitude).abs() * 69;
    final lngMiles =
        (a.longitude - b.longitude).abs() *
        69 *
        math.cos(a.latitude * math.pi / 180);
    return double.parse(
      math
          .sqrt((latMiles * latMiles) + (lngMiles * lngMiles))
          .toStringAsFixed(2),
    );
  }
}
