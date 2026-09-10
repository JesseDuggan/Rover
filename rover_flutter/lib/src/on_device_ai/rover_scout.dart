import '../active_roam/active_roam_session.dart';
import '../location/rover_location.dart';

enum RoverTravelMode { stationary, walking, driving, unknown }

enum RoverRouteState { onRoute, offRoute, inactive }

enum RoverGeofenceState { outside, approaching, inside, leaving, unknown }

enum RoverAttentionOpportunity { open, brief, blocked }

enum RoverConnectivityState { online, offline, unknown }

enum RoverOfflineCacheState { available, unavailable, unknown }

class RoverSituationSnapshot {
  const RoverSituationSnapshot({
    required this.capturedAtUtc,
    required this.travelMode,
    required this.routeState,
    required this.geofenceState,
    required this.attentionOpportunity,
    required this.connectivityState,
    required this.offlineCacheState,
    required this.routeRevision,
    required this.nearbyVerifiedPoiIds,
    this.navigationUrgent = false,
    this.currentStopId,
    this.distanceToStopMeters,
  });

  final DateTime capturedAtUtc;
  final RoverTravelMode travelMode;
  final RoverRouteState routeState;
  final RoverGeofenceState geofenceState;
  final RoverAttentionOpportunity attentionOpportunity;
  final RoverConnectivityState connectivityState;
  final RoverOfflineCacheState offlineCacheState;
  final int routeRevision;
  final bool navigationUrgent;
  final String? currentStopId;
  final double? distanceToStopMeters;
  final List<String> nearbyVerifiedPoiIds;

  bool get hasNavigationUrgency =>
      navigationUrgent ||
      routeState == RoverRouteState.offRoute ||
      geofenceState == RoverGeofenceState.approaching ||
      geofenceState == RoverGeofenceState.leaving;

  String get diagnosticSummary =>
      'travel=${travelMode.name}; route=${routeState.name}; '
      'geofence=${geofenceState.name}; '
      'attention=${attentionOpportunity.name}; '
      'nearby=${nearbyVerifiedPoiIds.length}; '
      'connectivity=${connectivityState.name}; '
      'cache=${offlineCacheState.name}';
}

class RoverScoutService {
  const RoverScoutService();

  RoverSituationSnapshot derive({
    required RoamSession session,
    RoverLocationReading? reading,
    RoverSituationSnapshot? previous,
    List<String> nearbyVerifiedPoiIds = const [],
    RoverConnectivityState connectivityState = RoverConnectivityState.unknown,
    RoverOfflineCacheState offlineCacheState = RoverOfflineCacheState.unknown,
    DateTime? capturedAtUtc,
  }) {
    final travelMode = _travelMode(reading?.speedMetersPerSecond);
    final routeState = session.status != RoamSessionStatus.active
        ? RoverRouteState.inactive
        : session.isOffRoute
        ? RoverRouteState.offRoute
        : RoverRouteState.onRoute;
    final stop = session.roam.stops.isEmpty ? null : session.currentStop;
    final distance = stop == null
        ? null
        : session.distanceToNextStopMeters ??
              reading?.location.distanceTo(stop.coordinates);
    final threshold = stop == null
        ? null
        : stop.arrivalRadiusMeters +
              10 +
              (reading?.accuracyMeters ??
                  session.currentGpsAccuracyMeters ??
                  0);
    final inside =
        stop != null &&
        (session.arrivedAtCurrentStop ||
            session.arrivalCandidateStopId == stop.id ||
            (distance != null && threshold != null && distance <= threshold));
    final sameStop = stop != null && previous?.currentStopId == stop.id;

    final geofenceState = switch ((stop, distance, threshold)) {
      (null, _, _) => RoverGeofenceState.unknown,
      (_, _, _) when inside => RoverGeofenceState.inside,
      (_, _, _)
          when sameStop &&
              previous?.geofenceState == RoverGeofenceState.inside =>
        RoverGeofenceState.leaving,
      (_, final value?, final limit?) when value <= limit + 100 =>
        RoverGeofenceState.approaching,
      _ => RoverGeofenceState.outside,
    };
    final navigationUrgent =
        routeState == RoverRouteState.offRoute ||
        geofenceState == RoverGeofenceState.approaching ||
        geofenceState == RoverGeofenceState.leaving ||
        (geofenceState == RoverGeofenceState.inside &&
            (session.arrivalCandidate ||
                session.audioStatus == AudioPlaybackStatus.playing));

    return RoverSituationSnapshot(
      capturedAtUtc: capturedAtUtc ?? DateTime.now().toUtc(),
      travelMode: travelMode,
      routeState: routeState,
      geofenceState: geofenceState,
      attentionOpportunity: _attentionOpportunity(
        routeState,
        navigationUrgent,
        travelMode,
      ),
      connectivityState: connectivityState,
      offlineCacheState: offlineCacheState,
      routeRevision: session.routeRevision,
      navigationUrgent: navigationUrgent,
      currentStopId: stop?.id,
      distanceToStopMeters: distance,
      nearbyVerifiedPoiIds: List.unmodifiable(
        nearbyVerifiedPoiIds.where((id) => id.isNotEmpty).toSet(),
      ),
    );
  }

  RoverTravelMode _travelMode(double? speedMetersPerSecond) {
    if (speedMetersPerSecond == null ||
        !speedMetersPerSecond.isFinite ||
        speedMetersPerSecond < 0) {
      return RoverTravelMode.unknown;
    }
    if (speedMetersPerSecond < 0.5) {
      return RoverTravelMode.stationary;
    }
    if (speedMetersPerSecond <= 2.8) {
      return RoverTravelMode.walking;
    }
    if (speedMetersPerSecond >= 5) {
      return RoverTravelMode.driving;
    }
    return RoverTravelMode.unknown;
  }

  RoverAttentionOpportunity _attentionOpportunity(
    RoverRouteState routeState,
    bool navigationUrgent,
    RoverTravelMode travelMode,
  ) {
    if (routeState == RoverRouteState.inactive ||
        routeState == RoverRouteState.offRoute ||
        navigationUrgent) {
      return RoverAttentionOpportunity.blocked;
    }
    if (travelMode == RoverTravelMode.driving ||
        travelMode == RoverTravelMode.unknown) {
      return RoverAttentionOpportunity.brief;
    }
    return RoverAttentionOpportunity.open;
  }
}
