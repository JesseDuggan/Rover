import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../adventure/adventure_request.dart';
import '../adventure/roam.dart';
import '../api/adaptation_models.dart';
import '../api/location_update_models.dart';
import '../api/problem_details.dart';
import '../api/walk_models.dart';
import '../api/walk_repository.dart';
import '../diagnostics/field_diagnostics.dart';
import '../location/rover_location.dart';
import 'active_roam_repository.dart';
import 'active_roam_session.dart';
import 'screen_awake_controller.dart';

class ActiveRoamController extends ChangeNotifier {
  ActiveRoamController({
    ActiveRoamRepository? repository,
    WalkRepository? walkRepository,
    RoverLocationProvider? locationProvider,
    ScreenAwakeController? screenAwakeController,
  }) : _repository = repository ?? FileActiveRoamRepository(),
       _walkRepository = walkRepository ?? HttpWalkRepository(),
       _locationProvider =
           locationProvider ?? const GeolocatorLocationProvider(),
       _screenAwakeController =
           screenAwakeController ?? const WakelockScreenAwakeController();

  final ActiveRoamRepository _repository;
  final WalkRepository _walkRepository;
  final RoverLocationProvider _locationProvider;
  final ScreenAwakeController _screenAwakeController;

  static const int _httpConflictStatusCode = 409;

  RoamSession? _session;
  bool _isLoaded = false;
  bool _isBusy = false;
  StreamSubscription<RoverLocationReading>? _locationSubscription;
  RoverLocationReading? _lastSubmittedReading;
  RoverLocationReading? _pendingLocationReading;
  bool _processingLocationReading = false;
  bool _autoRejoinInFlight = false;
  DateTime? _lastAutoRejoinAttemptUtc;
  LocationFailure? _locationFailure;
  final Set<String> _deviceArrivalAttempts = <String>{};
  final Set<String> _insideGeofenceStopIds = <String>{};
  String? _lastAdaptationInterest;

  RoamSession get session => _session ?? RoamSession.empty();
  bool get isLoaded => _isLoaded;
  bool get isBusy => _isBusy;
  bool get isTrackingLocation => _locationSubscription != null;
  RoverLocationReading? get latestLocationReading => _lastSubmittedReading;
  LocationFailure? get locationFailure => _locationFailure;

  Future<bool> checkApiHealth() async {
    try {
      final health = await _walkRepository.getHealth();
      return health['status'] == 'Healthy';
    } on RoverApiException {
      return false;
    }
  }

  Future<void> createWalk({
    required AdventureRequest request,
    required RoverLatLng location,
  }) async {
    await _runApiAction(() async {
      _deviceArrivalAttempts.clear();
      _insideGeofenceStopIds.clear();
      final walk = await _walkRepository.createWalk(
        CreateWalkRequest(
          latitude: location.latitude,
          longitude: location.longitude,
          availableMinutes: request.availableMinutes,
          interests: request.interests,
          walkingPace: _apiPace(request.pace),
          accessibilityPreferences: _accessibilityPreferences(request),
        ),
      );
      await _save(_sessionFromWalk(walk));
    });
  }

  Future<void> startApiWalk() async {
    final walkSessionId = session.apiWalkSessionId;
    if (walkSessionId == null || _isBusy) {
      return;
    }

    await _runApiAction(() async {
      _deviceArrivalAttempts.clear();
      _insideGeofenceStopIds.clear();
      final walk = await _walkRepository.startWalk(walkSessionId);
      await _save(_sessionFromWalk(walk).copyWith(screenAwake: true));
      await _screenAwakeController.enable();
      await startLocationTracking();
    });
  }

  Future<void> startLocationTracking() async {
    final walkSessionId = session.apiWalkSessionId;
    if (walkSessionId == null || session.status != RoamSessionStatus.active) {
      return;
    }

    final permissionFailure = await _locationProvider.checkPermissionStatus();
    if (permissionFailure != null) {
      final requestedFailure =
          permissionFailure.kind == LocationFailureKind.denied
          ? await _locationProvider.requestForegroundPermission()
          : permissionFailure;
      if (requestedFailure != null) {
        _locationFailure = requestedFailure;
        await _save(session.copyWith(errorMessage: _permissionMessage));
        return;
      }
    }

    _locationFailure = null;
    await _locationSubscription?.cancel();
    _locationSubscription = _locationProvider.watchLocation().listen(
      (reading) => _queueLocationReading(walkSessionId, reading),
      onError: (_) {
        _locationFailure = const LocationFailure(
          kind: LocationFailureKind.unknown,
          message: 'ROVER could not continue reading live location.',
        );
        notifyListeners();
      },
    );
    notifyListeners();
  }

  Future<void> stopLocationTracking() async {
    await _locationSubscription?.cancel();
    _locationSubscription = null;
    _lastSubmittedReading = null;
    _pendingLocationReading = null;
    notifyListeners();
  }

  void _queueLocationReading(
    String walkSessionId,
    RoverLocationReading reading,
  ) {
    _pendingLocationReading = reading;
    if (_processingLocationReading) {
      return;
    }
    unawaited(_drainLocationReadings(walkSessionId));
  }

  Future<void> _drainLocationReadings(String walkSessionId) async {
    _processingLocationReading = true;
    try {
      while (_pendingLocationReading != null) {
        final reading = _pendingLocationReading!;
        _pendingLocationReading = null;
        await _submitLocationReading(walkSessionId, reading);
      }
    } finally {
      _processingLocationReading = false;
      if (_pendingLocationReading != null && _locationSubscription != null) {
        unawaited(_drainLocationReadings(walkSessionId));
      }
    }
  }

  Future<bool> openLocationSettings() {
    return _locationProvider.openSettings();
  }

  Future<void> simulateArrivalAtNextStop() async {
    final walkSessionId = session.apiWalkSessionId;
    if (walkSessionId == null ||
        _isBusy ||
        session.status != RoamSessionStatus.active) {
      return;
    }

    await _runApiAction(() async {
      final stop = session.currentStop;
      final walk = await _walkRepository.arriveAtStop(
        walkSessionId,
        stop.id,
        latitude: stop.coordinates.latitude,
        longitude: stop.coordinates.longitude,
      );

      final nextSession = _sessionFromWalk(walk);
      if (walk.status == WalkStatus.completed) {
        await _screenAwakeController.disable();
        await stopLocationTracking();
      }
      await _save(nextSession);
    });
  }

  Future<void> manualArriveAtCurrentStop() async {
    final walkSessionId = session.apiWalkSessionId;
    if (walkSessionId == null ||
        _isBusy ||
        session.status != RoamSessionStatus.active ||
        session.arrivedAtCurrentStop) {
      return;
    }

    await _runApiAction(() async {
      final stop = session.currentStop;
      final walk = await _walkRepository.arriveAtStop(
        walkSessionId,
        stop.id,
        latitude: session.simulatedLocation.latitude,
        longitude: session.simulatedLocation.longitude,
      );

      final nextSession = _sessionFromWalk(walk);
      if (walk.status == WalkStatus.completed) {
        await _screenAwakeController.disable();
        await stopLocationTracking();
      }
      await _save(nextSession);
    });
  }

  Future<void> completeApiWalk() async {
    final walkSessionId = session.apiWalkSessionId;
    if (walkSessionId == null || _isBusy) {
      return;
    }

    await _runApiAction(() async {
      final walk = await _walkRepository.completeWalk(walkSessionId);
      await _save(_sessionFromWalk(walk).copyWith(screenAwake: false));
      await _screenAwakeController.disable();
      await stopLocationTracking();
    });
  }

  Future<void> cancelApiWalk() async {
    final walkSessionId = session.apiWalkSessionId;
    if (walkSessionId == null || _isBusy) {
      return;
    }

    await _runApiAction(() async {
      final walk = await _walkRepository.cancelWalk(walkSessionId);
      await _save(_sessionFromWalk(walk).copyWith(screenAwake: false));
      await _screenAwakeController.disable();
      await stopLocationTracking();
    });
  }

  Future<void> evaluateAdaptation({
    required String requestedType,
    String? interest,
    String? userRequest,
    int? availableMinutes,
    String? proposedDiscoveryId,
  }) async {
    final walkSessionId = session.apiWalkSessionId;
    if (walkSessionId == null || _isBusy) {
      return;
    }

    _lastAdaptationInterest = interest;
    await _runApiAction(() async {
      final request = WalkAdaptationEvaluateRequest(
        routeRevision: session.routeRevision,
        location: session.simulatedLocation,
        requestedType: requestedType,
        availableMinutes: availableMinutes,
        userRequest: userRequest,
        interest: interest,
        proposedDiscoveryId: proposedDiscoveryId,
        dismissedDiscoveryIds: session.dismissedDiscoveryIds.toList(),
      );
      final proposal = await _evaluateAdaptationWithRevisionRefresh(
        walkSessionId,
        request,
      );
      await _save(session.copyWith(pendingAdaptation: proposal));
    });
  }

  Future<void> requestNextAdaptationOption() async {
    final walkSessionId = session.apiWalkSessionId;
    final proposal = session.pendingAdaptation;
    if (walkSessionId == null || proposal == null || _isBusy) {
      return;
    }

    final dismissed = {
      ...session.dismissedDiscoveryIds,
      ...proposal.affectedStops,
    };
    final requestedType = proposal.type;
    final userRequest = 'Show another ${proposal.type} option';

    await _runApiAction(() async {
      late WalkAdaptationProposal nextProposal;
      await Future.wait([
        _walkRepository.rejectAdaptation(walkSessionId, proposal.adaptationId),
        () async {
          nextProposal = await _evaluateAdaptationWithRevisionRefresh(
            walkSessionId,
            WalkAdaptationEvaluateRequest(
              routeRevision: session.routeRevision,
              location: session.simulatedLocation,
              requestedType: requestedType,
              userRequest: userRequest,
              interest: _lastAdaptationInterest,
              dismissedDiscoveryIds: dismissed.toList(),
            ),
          );
        }(),
      ]);
      await _save(
        session.copyWith(
          pendingAdaptation: nextProposal,
          dismissedDiscoveryIds: dismissed,
        ),
      );
    });
  }

  Future<void> acceptPendingAdaptation() async {
    final walkSessionId = session.apiWalkSessionId;
    final proposal = session.pendingAdaptation;
    if (walkSessionId == null || proposal == null || _isBusy) {
      return;
    }

    await _runApiAction(() async {
      final dismissed = session.dismissedDiscoveryIds;
      final walk = await _acceptAdaptationWithRevisionRefresh(
        walkSessionId,
        proposal.adaptationId,
        session.routeRevision,
      );
      await _save(
        _sessionFromWalk(walk).copyWith(
          clearPendingAdaptation: true,
          dismissedDiscoveryIds: dismissed,
          savedDiscoveryIds: session.savedDiscoveryIds,
        ),
      );
    });
  }

  Future<void> addDiscoveryToWalk({
    required String proposedDiscoveryId,
    String? userRequest,
  }) async {
    final walkSessionId = session.apiWalkSessionId;
    if (walkSessionId == null || _isBusy) {
      return;
    }

    await _runApiAction(() async {
      final dismissed = session.dismissedDiscoveryIds;
      final request = WalkAdaptationEvaluateRequest(
        routeRevision: session.routeRevision,
        location: session.simulatedLocation,
        requestedType: 'AddDiscovery',
        proposedDiscoveryId: proposedDiscoveryId,
        userRequest: userRequest,
        dismissedDiscoveryIds: dismissed.toList(),
      );
      final proposal = await _evaluateAdaptationWithRevisionRefresh(
        walkSessionId,
        request,
      );
      final walk = await _acceptAdaptationWithRevisionRefresh(
        walkSessionId,
        proposal.adaptationId,
        proposal.routeRevision,
      );
      await _save(
        _sessionFromWalk(walk).copyWith(
          clearPendingAdaptation: true,
          dismissedDiscoveryIds: dismissed,
          savedDiscoveryIds: session.savedDiscoveryIds,
        ),
      );
    });
  }

  Future<WalkAdaptationProposal> _evaluateAdaptationWithRevisionRefresh(
    String walkSessionId,
    WalkAdaptationEvaluateRequest request,
  ) async {
    try {
      return await _walkRepository.evaluateAdaptation(walkSessionId, request);
    } on RoverApiException catch (exception) {
      if (exception.statusCode != _httpConflictStatusCode) {
        rethrow;
      }
      final refreshed = await _walkRepository.getWalk(walkSessionId);
      await _save(
        _sessionFromWalk(refreshed).copyWith(
          pendingAdaptation: session.pendingAdaptation,
          dismissedDiscoveryIds: session.dismissedDiscoveryIds,
          savedDiscoveryIds: session.savedDiscoveryIds,
        ),
      );
      try {
        return await _walkRepository.evaluateAdaptation(
          walkSessionId,
          request.copyWith(routeRevision: refreshed.routeRevision),
        );
      } on RoverApiException catch (retryException) {
        if (retryException.statusCode == _httpConflictStatusCode) {
          throw const RoverApiException(
            'Rover refreshed your walk. Try that route option again.',
            statusCode: _httpConflictStatusCode,
          );
        }
        rethrow;
      }
    }
  }

  Future<WalkSession> _acceptAdaptationWithRevisionRefresh(
    String walkSessionId,
    String adaptationId,
    int routeRevision,
  ) async {
    try {
      return await _walkRepository.acceptAdaptation(
        walkSessionId,
        adaptationId,
        routeRevision,
      );
    } on RoverApiException catch (exception) {
      if (exception.statusCode != _httpConflictStatusCode) {
        rethrow;
      }
      final refreshed = await _walkRepository.getWalk(walkSessionId);
      await _save(
        _sessionFromWalk(refreshed).copyWith(
          pendingAdaptation: session.pendingAdaptation,
          dismissedDiscoveryIds: session.dismissedDiscoveryIds,
          savedDiscoveryIds: session.savedDiscoveryIds,
        ),
      );
      try {
        return await _walkRepository.acceptAdaptation(
          walkSessionId,
          adaptationId,
          refreshed.routeRevision,
        );
      } on RoverApiException catch (retryException) {
        if (retryException.statusCode == _httpConflictStatusCode) {
          throw const RoverApiException(
            'Rover refreshed your walk. Choose that route option again.',
            statusCode: _httpConflictStatusCode,
          );
        }
        rethrow;
      }
    }
  }

  Future<void> rejectPendingAdaptation({bool dismissDiscovery = false}) async {
    final walkSessionId = session.apiWalkSessionId;
    final proposal = session.pendingAdaptation;
    if (proposal == null) {
      return;
    }

    final dismissed = dismissDiscovery
        ? {...session.dismissedDiscoveryIds, ...proposal.affectedStops}
        : session.dismissedDiscoveryIds;

    if (walkSessionId == null || _isBusy) {
      await _save(
        session.copyWith(
          clearPendingAdaptation: true,
          dismissedDiscoveryIds: dismissed,
        ),
      );
      return;
    }

    await _runApiAction(() async {
      await _walkRepository.rejectAdaptation(
        walkSessionId,
        proposal.adaptationId,
      );
      await _save(
        session.copyWith(
          clearPendingAdaptation: true,
          dismissedDiscoveryIds: dismissed,
        ),
      );
    });
  }

  Future<void> savePendingAdaptationForLater() async {
    final proposal = session.pendingAdaptation;
    if (proposal == null) {
      return;
    }

    final saved = {...session.savedDiscoveryIds, ...proposal.affectedStops};
    await rejectPendingAdaptation();
    await _save(session.copyWith(savedDiscoveryIds: saved));
  }

  Future<void> load() async {
    _session = await _repository.load();
    // Older saves contain only session metadata, not the route itself.
    final walkId = _session?.apiWalkSessionId;
    if (_session != null && _session!.roam.stops.isEmpty && walkId != null) {
      try {
        _session = _sessionFromWalk(await _walkRepository.getWalk(walkId));
        await _repository.save(_session!);
      } catch (_) {
        _session = _session!.copyWith(
          status: RoamSessionStatus.notStarted,
          screenAwake: false,
          errorMessage:
              'Your saved walk could not be loaded. Try again when connected.',
        );
      }
    }
    _isLoaded = true;
    notifyListeners();
    if (session.apiWalkSessionId != null &&
        session.status == RoamSessionStatus.active) {
      await startLocationTracking();
    }
  }

  Future<void> pause() async {
    await _save(
      session.copyWith(
        status: RoamSessionStatus.paused,
        audioStatus: AudioPlaybackStatus.paused,
        screenAwake: false,
      ),
    );
    await _screenAwakeController.disable();
    await stopLocationTracking();
  }

  Future<void> resume() async {
    if (session.roam.stops.isEmpty) {
      return;
    }
    await _save(
      session.copyWith(status: RoamSessionStatus.active, screenAwake: true),
    );
    await _screenAwakeController.enable();
    if (session.apiWalkSessionId != null) {
      await startLocationTracking();
    }
  }

  Future<void> end() async {
    await _save(
      session.copyWith(
        status: RoamSessionStatus.ended,
        audioStatus: AudioPlaybackStatus.stopped,
        screenAwake: false,
      ),
    );
    await _screenAwakeController.disable();
    await stopLocationTracking();
  }

  Future<void> completeCurrentStop() async {
    final current = session.currentStop;
    final completed = {...session.completedStopIds, current.id};
    final isLast = session.currentStopIndex >= session.roam.stops.length - 1;
    final progressPercentage =
        ((completed.length + session.skippedStopIds.length) /
            session.roam.stops.length) *
        100;
    await _save(
      session.copyWith(
        completedStopIds: completed,
        currentStopIndex: isLast
            ? session.currentStopIndex
            : session.currentStopIndex + 1,
        arrivedAtCurrentStop: isLast,
        status: isLast ? RoamSessionStatus.completed : session.status,
        audioStatus: AudioPlaybackStatus.stopped,
        screenAwake: isLast ? false : session.screenAwake,
        progressPercentage: progressPercentage,
      ),
    );
    if (isLast) {
      await _screenAwakeController.disable();
      await stopLocationTracking();
    }
  }

  Future<void> skipCurrentStop() async {
    final current = session.currentStop;
    final skipped = {...session.skippedStopIds, current.id};
    final isLast = session.currentStopIndex >= session.roam.stops.length - 1;
    final progressPercentage =
        ((session.completedStopIds.length + skipped.length) /
            session.roam.stops.length) *
        100;
    await _save(
      session.copyWith(
        skippedStopIds: skipped,
        currentStopIndex: isLast
            ? session.currentStopIndex
            : session.currentStopIndex + 1,
        arrivedAtCurrentStop: isLast,
        status: isLast ? RoamSessionStatus.completed : session.status,
        audioStatus: AudioPlaybackStatus.stopped,
        screenAwake: isLast ? false : session.screenAwake,
        progressPercentage: progressPercentage,
      ),
    );
    if (isLast) {
      await _screenAwakeController.disable();
      await stopLocationTracking();
    }
  }

  Future<void> updateLocation(RoverLatLng location) async {
    final distance = _distanceMiles(location, session.currentStop.coordinates);
    await _save(
      session.copyWith(
        simulatedLocation: location,
        arrivedAtCurrentStop: distance <= 0.05,
      ),
    );
  }

  Future<void> playAudio() async {
    await _save(session.copyWith(audioStatus: AudioPlaybackStatus.playing));
  }

  Future<void> pauseAudio() async {
    await _save(session.copyWith(audioStatus: AudioPlaybackStatus.paused));
  }

  Future<void> replayAudio() async {
    await _save(session.copyWith(audioStatus: AudioPlaybackStatus.playing));
  }

  Future<void> markArrivalNarrated(String stopId) async {
    if (session.narratedArrivalStopIds.contains(stopId)) {
      return;
    }
    await _save(
      session.copyWith(
        narratedArrivalStopIds: {...session.narratedArrivalStopIds, stopId},
      ),
    );
  }

  Future<void> reroutePlaceholder() async {
    await _save(
      session.copyWith(
        status: RoamSessionStatus.active,
        arrivedAtCurrentStop: false,
      ),
    );
  }

  @override
  void dispose() {
    _locationSubscription?.cancel();
    super.dispose();
  }

  Future<void> _save(RoamSession nextSession) async {
    final mergedArrivalStopIds = {
      ...session.narratedArrivalStopIds,
      ...nextSession.narratedArrivalStopIds,
    };
    final mergedSession = nextSession.copyWith(
      narratedArrivalStopIds: mergedArrivalStopIds,
    );
    _session = mergedSession;
    await _repository.save(mergedSession);
    notifyListeners();
  }

  Future<void> _submitLocationReading(
    String walkSessionId,
    RoverLocationReading reading,
  ) async {
    if (!_shouldSubmitLocation(reading)) {
      return;
    }

    _lastSubmittedReading = reading;
    _session = session.copyWith(
      simulatedLocation: reading.location,
      currentGpsAccuracyMeters: reading.accuracyMeters,
      currentHeadingDegrees: reading.headingDegrees,
    );
    notifyListeners();
    try {
      final result = await _walkRepository.updateLocation(
        walkSessionId,
        LocationUpdateRequest(
          location: reading.location,
          recordedAtUtc: reading.recordedAtUtc,
          accuracyMeters: reading.accuracyMeters,
          headingDegrees: reading.headingDegrees,
          speedMetersPerSecond: reading.speedMetersPerSecond,
        ),
      );
      final nextSession = result.confirmedArrival == null
          ? _sessionFromLocationUpdate(result, reading)
          : await _sessionFromConfirmedArrival(walkSessionId, result, reading);
      if (result.confirmedArrival == null) {
        final deviceArrival = await _tryConfirmDeviceGeofenceArrival(
          walkSessionId,
          result,
          reading,
        );
        if (deviceArrival != null) {
          await _save(_withLatestLocation(deviceArrival));
          if (deviceArrival.status == RoamSessionStatus.completed ||
              deviceArrival.status == RoamSessionStatus.ended) {
            await stopLocationTracking();
          }
          return;
        }
      }
      final resolvedSession = result.confirmedArrival == null
          ? _sessionWithEnteredGeofenceNarration(nextSession, reading)
          : nextSession;
      await _save(_withLatestLocation(resolvedSession));
      if (result.isOffRoute) {
        await _tryAutoRejoinRoute(walkSessionId, reading);
      }
      if (result.status == WalkStatus.completed ||
          result.status == WalkStatus.cancelled) {
        await stopLocationTracking();
      }
    } on RoverApiException catch (exception) {
      _session = session.copyWith(errorMessage: exception.message);
      notifyListeners();
    }
  }

  Future<void> _tryAutoRejoinRoute(
    String walkSessionId,
    RoverLocationReading reading,
  ) async {
    final now = DateTime.now().toUtc();
    final lastAttempt = _lastAutoRejoinAttemptUtc;
    if (_autoRejoinInFlight ||
        _isBusy ||
        session.status != RoamSessionStatus.active ||
        session.arrivedAtCurrentStop ||
        (lastAttempt != null &&
            now.difference(lastAttempt) < const Duration(seconds: 30))) {
      return;
    }

    _autoRejoinInFlight = true;
    _lastAutoRejoinAttemptUtc = now;
    FieldDiagnostics.instance.record(
      'navigation',
      'off route confirmed; rebuilding Google route from current location',
    );
    try {
      final proposal = await _evaluateAdaptationWithRevisionRefresh(
        walkSessionId,
        WalkAdaptationEvaluateRequest(
          routeRevision: session.routeRevision,
          location: reading.location,
          requestedType: 'RejoinRoute',
          userRequest: 'Automatically rejoin from the current GPS location',
          dismissedDiscoveryIds: session.dismissedDiscoveryIds.toList(),
        ),
      );
      final walk = await _acceptAdaptationWithRevisionRefresh(
        walkSessionId,
        proposal.adaptationId,
        proposal.routeRevision,
      );
      final rerouted = _sessionFromWalk(walk).copyWith(
        simulatedLocation: reading.location,
        currentGpsAccuracyMeters: reading.accuracyMeters,
        currentHeadingDegrees: reading.headingDegrees,
        dismissedDiscoveryIds: session.dismissedDiscoveryIds,
        savedDiscoveryIds: session.savedDiscoveryIds,
        clearPendingAdaptation: true,
      );
      await _save(rerouted);
      FieldDiagnostics.instance.record(
        'navigation',
        'Google route rebuilt at revision ${walk.routeRevision}',
      );
    } on RoverApiException catch (exception) {
      FieldDiagnostics.instance.record(
        'navigation',
        'automatic rejoin deferred: ${exception.message}',
      );
    } finally {
      _autoRejoinInFlight = false;
    }
  }

  RoamSession _withLatestLocation(RoamSession nextSession) {
    final latest = _lastSubmittedReading;
    if (latest == null) {
      return nextSession;
    }
    return nextSession.copyWith(
      simulatedLocation: latest.location,
      currentGpsAccuracyMeters: latest.accuracyMeters,
      currentHeadingDegrees: latest.headingDegrees,
    );
  }

  RoamSession _sessionWithEnteredGeofenceNarration(
    RoamSession baseSession,
    RoverLocationReading reading,
  ) {
    if (baseSession.status != RoamSessionStatus.active) {
      return baseSession;
    }

    final scan = _scanEnteredNarratableStop(baseSession, reading);
    FieldDiagnostics.instance.record('geofence', scan.summary);
    final stop = scan.stop;
    if (stop == null) {
      return baseSession.copyWith(geofenceEntryDebug: scan.summary);
    }

    FieldDiagnostics.instance.record(
      'geofence',
      'queued narration stop=${stop.name} id=${stop.id}',
    );
    return baseSession.copyWith(
      arrivalCandidate: true,
      arrivalCandidateReadingCount: math.max(
        1,
        baseSession.arrivalCandidateReadingCount,
      ),
      arrivalCandidateStopId: stop.id,
      recentNarrationStopId: stop.id,
      recentNarrationStopOverride: stop,
      geofenceEntryDebug: scan.summary,
    );
  }

  _GeofenceEntryScan _scanEnteredNarratableStop(
    RoamSession baseSession,
    RoverLocationReading reading,
  ) {
    final accuracy = reading.accuracyMeters;
    if (accuracy != null && accuracy > 25) {
      return _GeofenceEntryScan(
        summary:
            'Geofence: blocked by GPS accuracy ${accuracy.round()} m; need 25 m or better',
      );
    }

    RoverStop? closest;
    var closestDistance = double.infinity;
    RoverStop? closestNarratable;
    var closestNarratableDistance = double.infinity;
    final previouslyInside = _insideGeofenceStopIds.toSet();
    final currentlyInside = <String>{};
    for (final stop in baseSession.roam.stops) {
      final distance = reading.location.distanceTo(stop.coordinates);
      if (distance < closestDistance) {
        closest = stop;
        closestDistance = distance;
      }

      final threshold = stop.arrivalRadiusMeters + math.min(accuracy ?? 0, 10);
      if (distance <= threshold) {
        currentlyInside.add(stop.id);
        final missedEntryNeedsRecovery =
            previouslyInside.contains(stop.id) &&
            !baseSession.narratedArrivalStopIds.contains(stop.id) &&
            baseSession.arrivalCandidateStopId == null;
        if ((!previouslyInside.contains(stop.id) || missedEntryNeedsRecovery) &&
            distance < closestNarratableDistance) {
          closestNarratable = stop;
          closestNarratableDistance = distance;
        }
      }
    }
    _insideGeofenceStopIds
      ..clear()
      ..addAll(currentlyInside);

    if (closestNarratable != null) {
      final completed = baseSession.completedStopIds.contains(
        closestNarratable.id,
      );
      final completedText = completed ? 'yes' : 'no';
      final recovered = previouslyInside.contains(closestNarratable.id);
      final entryKind = recovered ? 'recovered entry' : 'entry fired';
      return _GeofenceEntryScan(
        stop: closestNarratable,
        summary:
            'Geofence: $entryKind for ${closestNarratable.name}; completed $completedText; distance ${closestNarratableDistance.round()} m; radius ${closestNarratable.arrivalRadiusMeters} m; GPS ${accuracy?.round() ?? '-'} m',
      );
    }

    if (closest == null) {
      return const _GeofenceEntryScan(summary: 'Geofence: no stops on walk');
    }

    final threshold = closest.arrivalRadiusMeters + math.min(accuracy ?? 0, 10);
    final wasInside = previouslyInside.contains(closest.id);
    final completed = baseSession.completedStopIds.contains(closest.id);
    final state = closestDistance <= threshold
        ? wasInside
              ? 'still inside geofence'
              : completed
              ? 'already completed'
              : 'inside but not selected'
        : 'outside';
    return _GeofenceEntryScan(
      summary:
          'Geofence: closest ${closest.name}; $state; distance ${closestDistance.round()} m; threshold ${threshold.round()} m; radius ${closest.arrivalRadiusMeters} m; GPS ${accuracy?.round() ?? '-'} m',
    );
  }

  Future<RoamSession?> _tryConfirmDeviceGeofenceArrival(
    String walkSessionId,
    LocationUpdateResult result,
    RoverLocationReading reading,
  ) async {
    if (session.status != RoamSessionStatus.active ||
        session.arrivedAtCurrentStop) {
      return null;
    }

    final target = result.nextStop?.toRoverStop() ?? session.currentStop;
    if (session.completedStopIds.contains(target.id) ||
        _deviceArrivalAttempts.contains(target.id)) {
      return null;
    }

    final accuracy = reading.accuracyMeters;
    if (accuracy != null && accuracy > 55) {
      return null;
    }

    const fallbackPaddingMeters = 12.0;
    final distance = reading.location.distanceTo(target.coordinates);
    final threshold =
        target.arrivalRadiusMeters + fallbackPaddingMeters + (accuracy ?? 0);
    if (distance > threshold) {
      return null;
    }

    _deviceArrivalAttempts.add(target.id);
    try {
      final walk = await _walkRepository.arriveAtStop(
        walkSessionId,
        target.id,
        latitude: reading.location.latitude,
        longitude: reading.location.longitude,
      );
      if (walk.status == WalkStatus.completed ||
          walk.status == WalkStatus.cancelled) {
        await _screenAwakeController.disable();
      }
      return _sessionFromWalk(walk).copyWith(
        simulatedLocation: reading.location,
        currentGpsAccuracyMeters: reading.accuracyMeters,
        currentHeadingDegrees: reading.headingDegrees,
        pendingAdaptation: session.pendingAdaptation,
        dismissedDiscoveryIds: session.dismissedDiscoveryIds,
        savedDiscoveryIds: session.savedDiscoveryIds,
      );
    } on RoverApiException catch (exception) {
      if (exception.statusCode != _httpConflictStatusCode) {
        _deviceArrivalAttempts.remove(target.id);
      }
      return null;
    }
  }

  bool _shouldSubmitLocation(RoverLocationReading reading) {
    final last = _lastSubmittedReading;
    if (last == null) {
      return true;
    }

    if (_crossedNextStopEntryEdge(last, reading)) {
      return true;
    }

    final seconds = reading.recordedAtUtc
        .difference(last.recordedAtUtc)
        .inSeconds
        .abs();
    final meters = reading.location.distanceTo(last.location);
    return seconds >= 1 || meters >= 2;
  }

  bool _crossedNextStopEntryEdge(
    RoverLocationReading last,
    RoverLocationReading current,
  ) {
    final stop = session.currentStop;
    if (session.status != RoamSessionStatus.active ||
        session.arrivedAtCurrentStop ||
        session.completedStopIds.contains(stop.id)) {
      return false;
    }

    const entryBufferMeters = 10;
    const exitBufferMeters = 20;
    final entryThreshold = stop.arrivalRadiusMeters + entryBufferMeters;
    final resetThreshold = stop.arrivalRadiusMeters + exitBufferMeters;
    final previousDistance = last.location.distanceTo(stop.coordinates);
    final currentDistance = current.location.distanceTo(stop.coordinates);
    final accuracy = current.accuracyMeters ?? 0;

    return previousDistance > resetThreshold &&
        currentDistance <= entryThreshold &&
        accuracy <= resetThreshold;
  }

  RoamSession _sessionFromLocationUpdate(
    LocationUpdateResult result,
    RoverLocationReading reading,
  ) {
    final nextStop = result.nextStop;
    final currentStopIndex = nextStop == null
        ? math.max(0, session.roam.stops.length - 1)
        : session.roam.stops.indexWhere((stop) => stop.id == nextStop.stopId);
    final completed = result.confirmedArrival == null
        ? session.completedStopIds
        : {...session.completedStopIds, result.confirmedArrival!.stopId};

    return session.copyWith(
      status: _sessionStatus(result.status),
      currentStopIndex: currentStopIndex < 0
          ? session.currentStopIndex
          : currentStopIndex,
      completedStopIds: completed,
      simulatedLocation: reading.location,
      arrivedAtCurrentStop: nextStop == null,
      apiStatus: result.status.name,
      timeRemainingMinutes: result.estimatedMinutesRemaining,
      progressPercentage: result.routeProgressPercentage,
      routeProgressPercentage: result.routeProgressPercentage,
      distanceToNextStopMeters: result.distanceToNextStopMeters,
      isOffRoute: result.isOffRoute,
      distanceFromRouteMeters: result.distanceFromRouteMeters,
      arrivalCandidate: result.arrivalCandidate,
      arrivalCandidateReadingCount: result.arrivalCandidateReadingCount,
      currentGpsAccuracyMeters: reading.accuracyMeters,
      currentHeadingDegrees: reading.headingDegrees,
      routeRevision: session.routeRevision,
      arrivalCandidateStopId: result.arrivalCandidate
          ? result.arrivalCandidateStopId ??
                result.confirmedArrival?.stopId ??
                result.nextStop?.stopId
          : null,
      clearArrivalCandidateStopId: !result.arrivalCandidate,
      recentNarrationStopId: result.confirmedArrival?.stopId,
      recentNarrationStopOverride: result.confirmedArrival?.toRoverStop(),
      clearRecentNarrationStopId: result.confirmedArrival == null,
      errorMessage: result.isOffRoute
          ? 'You appear to be off the planned route.'
          : null,
    );
  }

  Future<RoamSession> _sessionFromConfirmedArrival(
    String walkSessionId,
    LocationUpdateResult result,
    RoverLocationReading reading,
  ) async {
    try {
      final walk = await _walkRepository.getWalk(walkSessionId);
      return _sessionFromWalk(walk).copyWith(
        simulatedLocation: reading.location,
        currentGpsAccuracyMeters: reading.accuracyMeters,
        currentHeadingDegrees: reading.headingDegrees,
        recentNarrationStopId:
            result.confirmedArrival?.stopId ?? walk.recentNarrationStopId,
        recentNarrationStopOverride:
            result.confirmedArrival?.toRoverStop() ??
            walk.recentNarration?.toRoverStop(),
        routeRevision: walk.routeRevision,
        pendingAdaptation: session.pendingAdaptation,
        dismissedDiscoveryIds: session.dismissedDiscoveryIds,
        savedDiscoveryIds: session.savedDiscoveryIds,
        errorMessage: result.isOffRoute
            ? 'You appear to be off the planned route.'
            : null,
      );
    } on RoverApiException {
      return _sessionFromLocationUpdate(result, reading);
    }
  }

  Future<void> _runApiAction(Future<void> Function() action) async {
    if (_isBusy) {
      return;
    }

    _isBusy = true;
    _session = _session?.copyWith(errorMessage: null);
    notifyListeners();

    try {
      await action();
    } on RoverApiException catch (exception) {
      _session = session.copyWith(errorMessage: exception.message);
      notifyListeners();
    } finally {
      _isBusy = false;
      notifyListeners();
    }
  }

  static RoamSession _sessionFromWalk(WalkSession walk) {
    final roam = walk.toRoam();
    final currentStopIndex = walk.nextStop == null
        ? math.max(0, roam.stops.length - 1)
        : roam.stops.indexWhere((stop) => stop.id == walk.nextStop!.stopId);
    final completed = walk.stops
        .where((stop) => stop.visited)
        .map((stop) => stop.stopId)
        .toSet();

    return RoamSession(
      roam: roam,
      status: _sessionStatus(walk.status),
      currentStopIndex: currentStopIndex < 0 ? 0 : currentStopIndex,
      completedStopIds: completed,
      skippedStopIds: const {},
      simulatedLocation: walk.lastKnownLocation ?? walk.startingLocation,
      audioStatus: AudioPlaybackStatus.stopped,
      screenAwake: walk.status == WalkStatus.inProgress,
      arrivedAtCurrentStop: walk.nextStop == null,
      apiWalkSessionId: walk.walkSessionId,
      apiStatus: walk.status.name,
      timeRemainingMinutes: walk.timeRemainingMinutes,
      progressPercentage: math.max(
        walk.walkProgressPercentage,
        walk.routeProgressPercentage,
      ),
      routeProgressPercentage: walk.routeProgressPercentage,
      distanceToNextStopMeters: walk.distanceToNextStopMeters,
      isOffRoute: walk.isOffRoute,
      distanceFromRouteMeters: walk.distanceFromRouteMeters,
      arrivalCandidateReadingCount: 0,
      arrivalCandidateStopId: null,
      recentNarrationStopId: walk.recentNarrationStopId,
      recentNarrationStopOverride: walk.recentNarration?.toRoverStop(),
      routeRevision: walk.routeRevision,
      routeQuality: walk.routeQuality,
      lifecycleConsistency: walk.lifecycleConsistency,
      currentGpsAccuracyMeters: null,
      savedDiscoveryIds: const {},
    );
  }

  static const String _permissionMessage =
      'Rover uses your location during an active walk to show your route, guide you to the next stop and detect when you arrive.';

  static RoamSessionStatus _sessionStatus(WalkStatus status) {
    return switch (status) {
      WalkStatus.created || WalkStatus.ready => RoamSessionStatus.notStarted,
      WalkStatus.inProgress => RoamSessionStatus.active,
      WalkStatus.completed => RoamSessionStatus.completed,
      WalkStatus.cancelled => RoamSessionStatus.ended,
      WalkStatus.unknown => RoamSessionStatus.notStarted,
    };
  }

  static String _apiPace(String pace) {
    return switch (pace.toLowerCase()) {
      'easy' || 'relaxed' || 'leisurely' => 'Leisurely',
      'brisk' => 'Brisk',
      _ => 'Standard',
    };
  }

  static List<String> _accessibilityPreferences(AdventureRequest request) {
    final values = <String>[];
    if (request.routeMode.toLowerCase().contains('accessible')) {
      values.add('WheelchairAccessible');
    }
    final text = request.naturalRequest.toLowerCase();
    if (text.contains('stairs') ||
        request.routeMode.toLowerCase().contains('stairs')) {
      values.add('AvoidStairs');
    }
    return values;
  }

  static double _distanceMiles(RoverLatLng a, RoverLatLng b) {
    final latMiles = (a.latitude - b.latitude).abs() * 69;
    final lngMiles = (a.longitude - b.longitude).abs() * 54;
    return math.sqrt((latMiles * latMiles) + (lngMiles * lngMiles));
  }
}

class _GeofenceEntryScan {
  const _GeofenceEntryScan({required this.summary, this.stop});

  final String summary;
  final RoverStop? stop;
}

class ActiveRoamScope extends InheritedNotifier<ActiveRoamController> {
  const ActiveRoamScope({
    required ActiveRoamController controller,
    required super.child,
    super.key,
  }) : super(notifier: controller);

  static ActiveRoamController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<ActiveRoamScope>();
    assert(scope != null, 'No ActiveRoamScope found in context.');
    return scope!.notifier!;
  }
}
