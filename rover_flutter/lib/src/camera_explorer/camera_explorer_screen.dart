import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';

import '../active_roam/active_roam_controller.dart';
import '../active_roam/active_roam_session.dart';
import '../api/location_story_models.dart';
import '../api/location_observation_models.dart';
import '../api/hotel_rate_repository.dart';
import '../api/problem_details.dart';
import '../api/walk_repository.dart';
import '../diagnostics/field_diagnostics.dart';
import '../diagnostics/performance_diagnostics.dart';
import '../location/rover_location.dart';
import '../on_device_ai/rover_curator.dart';
import '../on_device_ai/rover_lens_service.dart';
import '../on_device_ai/rover_on_device_ai_scope.dart';
import '../preferences/preferences_controller.dart';
import '../voice/rover_premium_voice.dart';
import '../voice/rover_voice_controller.dart';
import 'ar_capability.dart';
import 'camera_projection.dart';
import 'camera_heading.dart';
import 'hotel_rate_sheet.dart';
import 'lodging_candidate.dart';

class CameraExplorerScreen extends StatefulWidget {
  const CameraExplorerScreen({this.hotelRateRepository, super.key});

  final HotelRateRepository? hotelRateRepository;

  @override
  State<CameraExplorerScreen> createState() => _CameraExplorerScreenState();
}

class _CameraExplorerScreenState extends State<CameraExplorerScreen>
    with WidgetsBindingObserver {
  static const _settings = CameraProjectionSettings();
  static const _poiRefreshDistanceMeters = 500.0;
  static const _poiRefreshRadiusMeters = 1500;

  final WalkRepository _walkRepository = HttpWalkRepository();
  late final HotelRateRepository _hotelRateRepository;
  final RoverLocationProvider _locationProvider =
      const GeolocatorLocationProvider();
  final RoverArCapability _arCapability =
      RoverArCapability.cameraOverlayFallback;
  late final RoverVoiceController _voiceController;
  late RoverLensService _lensService;
  bool _lensServiceReady = false;
  CameraController? _cameraController;
  StreamSubscription<RoverLocationReading>? _locationSubscription;
  StreamSubscription<CompassEvent>? _compassSubscription;
  DateTime? _lastHeadingRefresh;
  DateTime? _lastOverlayLog;

  RoverLocationReading? _reading;
  double? _smoothedHeading;
  LocationStoryContext? _locationContext;
  List<CameraOverlayCandidate> _overlays = const [];
  CameraOverlayCandidate? _selected;
  DateTime? _lastPoiRefreshAt;
  RoverLatLng? _lastPoiRefreshLocation;
  String? _message =
      'Stop walking before exploring the screen. Rover will ask for camera and location access.';
  String? _error;
  bool _cameraPermissionDenied = false;
  bool _muted = false;
  bool _loadingCamera = false;
  bool _loadingPois = false;
  bool _addingToWalk = false;
  bool _analyzingCapture = false;
  int _staleJobs = 0;
  int _revision = 0;
  int _captureRevision = 0;
  String? _activeCapturePath;
  Duration? _cameraInitializationTime;

  bool get _recognitionEnabled => _lensServiceReady && _lensService.enabled;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _hotelRateRepository =
        widget.hotelRateRepository ?? HttpHotelRateRepository();
    _voiceController = RoverVoiceController(
      walkRepository: _walkRepository,
      premiumVoice: RoverPremiumVoiceCoordinator(
        walkRepository: _walkRepository,
      ),
    );
    unawaited(_initialize());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_lensServiceReady) {
      _lensService = RoverLensService(RoverOnDeviceAiScope.of(context));
      _lensServiceReady = true;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _locationSubscription?.cancel();
    _compassSubscription?.cancel();
    _cameraController?.dispose();
    if (_lensServiceReady) {
      unawaited(_lensService.cancel());
    }
    unawaited(_deleteCapture(_activeCapturePath));
    _voiceController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      FieldDiagnostics.instance.record(
        'camera',
        'app backgrounded; releasing camera',
      );
      unawaited(_cameraController?.dispose());
      _cameraController = null;
      _captureRevision++;
      if (_lensServiceReady) {
        unawaited(_lensService.cancel());
      }
      unawaited(_deleteCapture(_activeCapturePath));
      _activeCapturePath = null;
      unawaited(_voiceController.stopAll());
      unawaited(_compassSubscription?.cancel());
      _compassSubscription = null;
      if (mounted) {
        setState(() {
          _analyzingCapture = false;
          _message = 'Camera paused while Rover was in the background.';
        });
      }
    } else if (state == AppLifecycleState.resumed &&
        _cameraController == null) {
      unawaited(_initializeCamera());
      _initializeCompass();
    }
  }

  Future<void> _initialize() async {
    await _initializeCamera();
    if (!mounted) return;
    _initializeCompass();
    await _initializeLocation();
  }

  void _initializeCompass() {
    _compassSubscription ??= FlutterCompass.events?.listen(
      (event) {
        if (!mounted) return;
        final heading = cameraHeading(event, defaultTargetPlatform);
        _smoothedHeading = heading == null
            ? null
            : _smoothedHeading == null
            ? heading
            : smoothHeading(_smoothedHeading!, heading);
        final now = DateTime.now();
        if (_lastHeadingRefresh == null ||
            now.difference(_lastHeadingRefresh!) >=
                const Duration(milliseconds: 200)) {
          _lastHeadingRefresh = now;
          _refreshOverlays();
        }
      },
      onError: (_) {
        if (!mounted) return;
        _smoothedHeading = null;
        _refreshOverlays();
      },
    );
  }

  Future<void> _initializeCamera() async {
    if (_loadingCamera) {
      return;
    }

    setState(() {
      _loadingCamera = true;
      _cameraPermissionDenied = false;
      _error = null;
    });
    final started = DateTime.now();
    try {
      final cameras = await availableCameras();
      CameraDescription? rearCamera;
      for (final camera in cameras) {
        if (camera.lensDirection == CameraLensDirection.back) {
          rearCamera = camera;
          break;
        }
      }
      rearCamera ??= cameras.isEmpty ? null : cameras.first;
      if (rearCamera == null) {
        throw CameraException('no_camera', 'No camera is available.');
      }

      final controller = CameraController(
        rearCamera,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );
      await controller.initialize();
      _cameraInitializationTime = DateTime.now().difference(started);
      PerformanceDiagnostics.instance.record(
        'camera initialize',
        _cameraInitializationTime!,
      );
      FieldDiagnostics.instance.record(
        'camera',
        'initialized rear camera in ${_cameraInitializationTime!.inMilliseconds} ms',
      );
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _cameraController = controller;
        _message = 'Point your phone slowly toward nearby places.';
      });
    } on CameraException catch (exception) {
      FieldDiagnostics.instance.record(
        'camera',
        'camera unavailable ${exception.code}',
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _cameraPermissionDenied = exception.code.toLowerCase().contains(
          'permission',
        );
        _error = _cameraPermissionDenied
            ? 'Camera permission is needed for Camera Explorer.'
            : 'Camera Explorer could not start the camera.';
      });
    } finally {
      if (mounted) {
        setState(() => _loadingCamera = false);
      }
    }
  }

  Future<void> _initializeLocation() async {
    final failure = await _locationProvider.checkPermissionStatus();
    final requestedFailure = failure?.kind == LocationFailureKind.denied
        ? await _locationProvider.requestForegroundPermission()
        : failure;
    if (!mounted) return;
    if (requestedFailure != null) {
      FieldDiagnostics.instance.record(
        'camera',
        'location unavailable ${requestedFailure.kind.name}',
      );
      if (mounted) {
        setState(() {
          _error = requestedFailure.message;
        });
      }
      return;
    }

    _locationSubscription = _locationProvider.watchLocation().listen(
      _handleLocationReading,
      onError: (_) {
        if (mounted) {
          setState(() => _error = 'Rover could not keep location active.');
        }
      },
    );
    // A distance-filtered stream may not emit while the visitor is stationary.
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
      if (!mounted ||
          (_reading != null &&
              !_reading!.recordedAtUtc.isBefore(position.timestamp.toUtc()))) {
        return;
      }
      _handleLocationReading(
        RoverLocationReading(
          location: RoverLatLng(
            latitude: position.latitude,
            longitude: position.longitude,
          ),
          recordedAtUtc: position.timestamp.toUtc(),
          accuracyMeters: position.accuracy,
        ),
      );
    } catch (_) {
      if (mounted && _reading == null) {
        setState(
          () => _error = 'Waiting for a location fix. Check Location Services.',
        );
      }
    }
  }

  void _handleLocationReading(RoverLocationReading reading) {
    if (!mounted) {
      return;
    }

    _reading = reading;

    final shouldRefresh =
        _lastPoiRefreshLocation == null ||
        _lastPoiRefreshLocation!.distanceTo(reading.location) >=
            _poiRefreshDistanceMeters;
    if (shouldRefresh && !_loadingPois) {
      unawaited(_refreshPois(reading.location));
    }

    _refreshOverlays();
  }

  Future<void> _refreshPois(RoverLatLng location) async {
    final requestRevision = ++_revision;
    _loadingPois = true;
    final started = DateTime.now();
    try {
      final active = ActiveRoamScope.of(context).session;
      final contextResult = await _walkRepository.getLocationContext(
        latitude: location.latitude,
        longitude: location.longitude,
        radiusMeters: _poiRefreshRadiusMeters,
        routeId: active.apiWalkSessionId,
      );
      if (!mounted || requestRevision != _revision) {
        _staleJobs++;
        return;
      }
      _locationContext = contextResult;
      _lastPoiRefreshLocation = location;
      _lastPoiRefreshAt = DateTime.now();
      PerformanceDiagnostics.instance.record(
        'camera POI refresh',
        DateTime.now().difference(started),
      );
      FieldDiagnostics.instance.record(
        'camera',
        'POI refresh ${contextResult.rankedPlaces.length} candidates',
      );
      _curateVerifiedPlaces(active, contextResult);
      _refreshOverlays();
    } on RoverApiException catch (exception) {
      if (mounted) {
        setState(
          () => _error = 'Camera places could not load: ${exception.message}',
        );
      }
    } finally {
      _loadingPois = false;
    }
  }

  void _curateVerifiedPlaces(
    RoamSession active,
    LocationStoryContext contextResult,
  ) {
    final coordinator = RoverOnDeviceAiScope.of(context);
    final verifiedPlaces = contextResult.rankedPlaces
        .where(
          (place) => place.facts.any(
            (fact) =>
                fact.isSuitableForNarration && fact.factId.trim().isNotEmpty,
          ),
        )
        .toList(growable: false);
    final snapshot = coordinator.observeSituation(
      session: active,
      reading: _reading,
      nearbyVerifiedPoiIds: verifiedPlaces
          .map((place) => place.canonicalId)
          .toList(growable: false),
    );
    if (snapshot == null) {
      return;
    }

    final routeStopIds = active.roam.stops.map((stop) => stop.id).toSet();
    final candidates = verifiedPlaces
        .map(
          (place) => RoverCuratorStoryCandidate.fromPlace(
            place,
            routeStopIds: routeStopIds.contains(place.canonicalId)
                ? [place.canonicalId]
                : const [],
          ),
        )
        .toList(growable: false);
    final recentNarrationId = active.recentNarrationStopId;
    coordinator.curate(
      candidates: candidates,
      preferences: RoverCuratorPreferences.fromPreferences(
        PreferencesScope.of(context).preferences,
        availableMinutes: active.timeRemainingMinutes,
      ),
      situation: snapshot,
      previouslyNarratedContentIds: {?recentNarrationId},
    );
  }

  void _refreshOverlays() {
    if (!mounted) {
      return;
    }

    final reading = _reading;
    final heading = _smoothedHeading;
    if (reading == null || heading == null) {
      setState(() {
        _message = reading == null ? 'Waiting for a location fix.' : 'Waiting for compass direction. Sign scanning is still available.';
        _overlays = const [];
      });
      return;
    }

    if ((reading.accuracyMeters ?? 0) > 80) {
      setState(() {
        _message = 'Rover is waiting for a more accurate GPS fix.';
        _overlays = const [];
      });
      return;
    }

    final started = DateTime.now();
    final active = ActiveRoamScope.of(context).session;
    final places = _candidatePlaces(active);
    final overlays = projectCameraCandidates(
      userLocation: reading.location,
      headingDegrees: heading,
      places: places,
      settings: _settings,
    );
    PerformanceDiagnostics.instance.record(
      'camera overlay refresh',
      DateTime.now().difference(started),
    );
    if (_lastOverlayLog == null ||
        started.difference(_lastOverlayLog!) >= const Duration(seconds: 5)) {
      _lastOverlayLog = started;
      FieldDiagnostics.instance.record(
        'camera',
        'overlay ${overlays.length}/${places.length} compass=${heading.round()}',
      );
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _overlays = overlays;
      final offlineCached =
          _locationContext?.sourceWarnings.any(
            (warning) => warning.startsWith('Offline cached match.'),
          ) ??
          false;
      _message = offlineCached
          ? overlays.isEmpty
                ? 'Offline cache has no place confidently in this camera direction.'
                : 'Offline cached match. Live place details are unavailable.'
          : overlays.isEmpty
          ? 'No verified places are confidently in this camera direction.'
          : 'Likely nearby places in camera direction.';
      if (_selected != null &&
          !overlays.any((item) => item.place.id == _selected!.place.id)) {
        _selected = null;
      }
    });
  }

  List<CameraPlaceCandidate> _candidatePlaces(RoamSession active) {
    final candidates = <CameraPlaceCandidate>[];
    if (active.apiWalkSessionId != null) {
      for (final ordered in active.orderedStops) {
        final stop = ordered.stop;
        final sourceLabel = stop.contentSource ?? 'Walk';
        candidates.add(
          CameraPlaceCandidate(
            id: stop.id,
            name: stop.name,
            coordinates: stop.coordinates,
            category: stop.category,
            description: stop.shortDescription,
            sourceLabel: sourceLabel,
            confidence: 0.95,
            storyWorthiness: 75,
            storyAvailable: (stop.narration?.isNotEmpty ?? false),
            isRouteStop: true,
            isCurrentOrNextStop:
                ordered.sequence - 1 == active.currentStopIndex ||
                ordered.sequence - 1 == active.currentStopIndex + 1,
            addToWalkId: stop.id,
            address: stop.address,
            websiteUrl: stop.websiteUrl,
            phoneNumber: stop.phoneNumber,
            menuUrl: stop.menuUrl,
            sourceAttribution: [sourceLabel],
          ),
        );
      }
    }

    for (final place
        in _locationContext?.rankedPlaces ?? const <LocationPlaceSummary>[]) {
      if (candidates.any((candidate) => candidate.id == place.canonicalId)) {
        continue;
      }
      final factIds = place.facts
          .where((fact) => fact.factId.isNotEmpty)
          .map((fact) => fact.factId)
          .toList();
      candidates.add(
        CameraPlaceCandidate(
          id: place.canonicalId,
          name: place.name,
          coordinates: place.coordinates,
          category: place.categories.isEmpty ? 'Place' : place.categories.first,
          description:
              place.shortDescription ??
              place.facts
                  .where((fact) => fact.factText.isNotEmpty)
                  .map((fact) => fact.factText)
                  .take(1)
                  .join(),
          sourceLabel: place.sourceReferences.isEmpty
              ? 'Location Intelligence'
              : place.sourceReferences.first.providerName,
          confidence: place.confidenceScore,
          storyWorthiness: place.storyWorthinessScore,
          storyAvailable:
              factIds.isNotEmpty || place.sourceReferences.isNotEmpty,
          addToWalkId: place.canonicalId,
          address: place.address,
          openingStatus: place.openingStatus,
          accessibilityInformation: place.accessibilityInformation,
          facts: place.facts
              .where((fact) => fact.factText.isNotEmpty)
              .map((fact) => fact.factText)
              .toList(growable: false),
          sourceAttribution: place.sourceReferences
              .map((source) => source.attribution)
              .where((value) => value.isNotEmpty)
              .toSet()
              .toList(),
          factIds: factIds,
        ),
      );
    }
    return candidates;
  }

  @override
  Widget build(BuildContext context) {
    final session = ActiveRoamScope.of(context).session;
    final controller = _cameraController;
    final recognitionEnabled = _recognitionEnabled;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: controller != null && controller.value.isInitialized
                  ? CameraPreview(controller)
                  : _CameraFallback(
                      loading: _loadingCamera,
                      permissionDenied: _cameraPermissionDenied,
                      error: _error,
                    ),
            ),
            Positioned.fill(
              child: _OverlayLayer(
                overlays: _overlays,
                onSelected: _selectOverlay,
              ),
            ),
            Positioned(
              left: 12,
              right: 12,
              top: 8,
              child: _CameraTopBar(
                muted: _muted,
                recognitionEnabled: recognitionEnabled,
                recognizing: _analyzingCapture,
                onClose: () {
                  if (context.canPop()) {
                    context.pop();
                    return;
                  }
                  context.go('/home/active-roam');
                },
                onMuteToggle: () {
                  setState(() => _muted = !_muted);
                  if (!_muted) {
                    return;
                  }
                  unawaited(_voiceController.stopAll());
                },
                onRecognize: () => unawaited(_whatAmILookingAt()),
              ),
            ),
            Positioned(
              left: 16,
              right: 16,
              top: 82,
              child: _CameraStatusPill(message: _statusMessage()),
            ),
            if (_selected != null)
              Positioned(
                left: 12,
                right: 12,
                bottom: 12,
                child: _CameraPlaceCard(
                  overlay: _selected!,
                  activeWalk: session,
                  muted: _muted,
                  addingToWalk: _addingToWalk,
                  recognitionEnabled: recognitionEnabled,
                  recognizing: _analyzingCapture,
                  onDismiss: () => setState(() => _selected = null),
                  onHearStory: () => unawaited(_hearStory(_selected!)),
                  onTellMore: () => unawaited(_tellMore(_selected!)),
                  onAddToWalk: session.apiWalkSessionId == null
                      ? () => _startWalkFromCameraPlace(_selected!)
                      : () => unawaited(_addToWalk(_selected!)),
                  onOpenMap: () => context.go('/home/active-roam'),
                  onWhatAmILookingAt: () => unawaited(_whatAmILookingAt()),
                  onCheckRates:
                      isLodgingCandidate(
                        category: _selected!.place.category,
                        name: _selected!.place.name,
                      )
                      ? () => _showHotelRates(_selected!)
                      : null,
                ),
              ),
            if (_selected == null)
              Positioned(
                left: 20,
                right: 20,
                bottom: 24,
                child: Center(
                  child: _CameraScanControl(
                    enabled: recognitionEnabled,
                    recognizing: _analyzingCapture,
                    onPressed: () => unawaited(_whatAmILookingAt()),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _statusMessage() {
    final reading = _reading;
    final heading = _smoothedHeading;
    final parts = [
      _message ?? 'Camera Explorer is active.',
      if (!_recognitionEnabled)
        'Sign scanning was not enabled when this app was built',
      if (reading?.accuracyMeters != null)
        'GPS ${reading!.accuracyMeters!.round()} m',
      if (heading != null) 'heading ${heading.round()} deg',
      '${_overlays.length} labels',
      'AR: ${_arCapability.mode}',
      if (_lastPoiRefreshAt != null) 'POI refreshed',
      if (_staleJobs > 0) 'stale jobs $_staleJobs',
    ];
    return parts.join(' - ');
  }

  void _selectOverlay(CameraOverlayCandidate overlay) {
    setState(() => _selected = overlay);
  }

  Future<void> _hearStory(CameraOverlayCandidate overlay) async {
    if (_muted) {
      setState(() => _message = 'Narration is muted.');
      return;
    }

    final reading = _reading;
    if (reading == null) {
      return;
    }

    final session = ActiveRoamScope.of(context).session;
    await _voiceController.tellLocationStory(
      location: reading.location,
      routeId: session.apiWalkSessionId,
      routeGeometry: session.roam.routeGeometry,
      selectedPlaceId: overlay.place.id,
      selectedPlaceName: overlay.place.name,
      selectedPlaceFallbackNarration: _selectedPlaceFallback(overlay),
      label: 'Camera Explorer',
    );
  }

  String _selectedPlaceFallback(CameraOverlayCandidate overlay) {
    final place = overlay.place;
    final details = <String>[
      place.description.trim(),
      ...place.facts.map((fact) => fact.trim()),
    ].where((detail) => detail.isNotEmpty).toSet().take(2).toList();
    if (details.isNotEmpty) {
      return '${place.name}. ${details.join(' ')}';
    }
    return '${place.name} is ${distanceLabel(overlay.distanceMeters)} away, '
        '${overlay.relativeDirection.toLowerCase()}. Rover has basic map context '
        'for this place, but no verified story facts yet.';
  }

  Future<void> _tellMore(CameraOverlayCandidate overlay) async {
    await _hearStory(overlay);
  }

  Future<void> _addToWalk(CameraOverlayCandidate overlay) async {
    final controller = ActiveRoamScope.of(context);
    if (controller.session.apiWalkSessionId == null || _addingToWalk) {
      return;
    }

    setState(() => _addingToWalk = true);
    await controller.addDiscoveryToWalk(
      proposedDiscoveryId: overlay.place.addToWalkId ?? overlay.place.id,
      userRequest: 'Add ${overlay.place.name} from Camera Explorer',
    );
    if (!mounted) {
      return;
    }
    setState(() => _addingToWalk = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${overlay.place.name} has been added to the walk.'),
      ),
    );
    context.go('/home/active-roam');
  }

  void _startWalkFromCameraPlace(CameraOverlayCandidate overlay) {
    final place = Uri.encodeComponent(overlay.place.name);
    context.go('/home/adventure-request?nearby=true&cameraPlace=$place');
  }

  Future<void> _whatAmILookingAt() async {
    final controller = _cameraController;
    if (_analyzingCapture ||
        controller == null ||
        !controller.value.isInitialized ||
        !_lensServiceReady ||
        !_lensService.enabled) {
      return;
    }
    final requestRevision = ++_captureRevision;
    setState(() {
      _analyzingCapture = true;
      _message = 'Reading visible text on this device...';
    });

    String? capturePath;
    try {
      final capture = await controller.takePicture();
      capturePath = capture.path;
      _activeCapturePath = capturePath;
      final result = await _lensService.recognizeText(
        localImagePath: capturePath,
        nearbyCandidates: _overlays
            .map(
              (overlay) => RoverLensCandidate(
                id: overlay.place.id,
                name: overlay.place.name,
              ),
            )
            .toList(growable: false),
      );
      if (!mounted || requestRevision != _captureRevision) {
        _staleJobs++;
        return;
      }

      await _deleteCapture(capturePath);
      _activeCapturePath = null;
      capturePath = null;
      if (!mounted || requestRevision != _captureRevision) {
        _staleJobs++;
        return;
      }

      CameraOverlayCandidate? matchedOverlay;
      if (result.matchedCandidateId case final matchedId?) {
        for (final overlay in _overlays) {
          if (overlay.place.id == matchedId) {
            matchedOverlay = overlay;
            break;
          }
        }
      }
      LocationObservationResolution? resolution;
      final reading = _reading;
      // An exact OCR match against the already sourced camera labels is enough
      // to select the place. Avoid a second Places round trip in that case.
      if (result.recognizedText != null &&
          reading != null &&
          matchedOverlay == null) {
        if (mounted) {
          setState(() => _message = 'Checking nearby sourced places...');
        }
        try {
          final active = ActiveRoamScope.of(context).session;
          resolution = await _walkRepository.resolveLocationObservation(
            LocationObservationResolveRequest(
              recognizedText: result.recognizedText!,
              location: reading.location,
              accuracyMeters: reading.accuracyMeters,
              headingDegrees: _smoothedHeading,
              radiusMeters: _poiRefreshRadiusMeters,
              routeId: active.apiWalkSessionId,
              nearbyPlaceIds: _candidatePlaces(active)
                  .map((place) => place.id)
                  .toList(growable: false),
            ),
          );
          if (!mounted || requestRevision != _captureRevision) {
            _staleJobs++;
            return;
          }
          final verified = resolution.selectedCandidate;
          if (verified != null) {
            matchedOverlay = _overlayForResolvedPlace(
              verified.place,
              reading.location,
            );
          }
        } on RoverApiException catch (exception) {
          FieldDiagnostics.instance.record(
            'camera-resolver',
            'API unavailable; retained local result (${exception.statusCode ?? 'network'})',
          );
        }
      }
      setState(() {
        _message = switch (resolution?.status) {
          LocationObservationResolutionStatus.verified =>
            'Verified ${matchedOverlay!.place.name} from sourced nearby data.',
          LocationObservationResolutionStatus.ambiguous =>
            'Rover found a few possible nearby matches.',
          LocationObservationResolutionStatus.unresolved =>
            'Text found, but Rover could not verify the place.',
          null => result.message,
        };
        if (matchedOverlay != null) {
          _selected = matchedOverlay;
        }
      });
      FieldDiagnostics.instance.record(
        'on-device-ai',
        'lens OCR ${result.status.name}; code ${result.diagnosticCode}; '
            'local match ${result.matchedCandidateId != null}',
      );
      if (resolution != null) {
        FieldDiagnostics.instance.record(
          'camera-resolver',
          '${resolution.status.name}; code ${resolution.diagnosticCode}; '
              'candidates ${resolution.candidates.length}; '
              'auto-selected ${resolution.selectedPlaceId != null}',
        );
      }
      if (result.recognizedText != null) {
        final chosen = await _showLensResult(
          result,
          matchedOverlay,
          resolution,
        );
        if (chosen != null && mounted && requestRevision == _captureRevision) {
          final selectedOverlay = _overlayForResolvedPlace(
            chosen.place,
            reading!.location,
          );
          setState(() {
            _selected = selectedOverlay;
            _message = 'Using ${chosen.place.name} as the confirmed place.';
          });
          FieldDiagnostics.instance.record(
            'camera-resolver',
            'user selected ambiguous candidate ${chosen.place.canonicalId}',
          );
        }
      }
    } on CameraException catch (exception) {
      FieldDiagnostics.instance.record(
        'on-device-ai',
        'lens capture failed ${exception.code}',
      );
      if (mounted && requestRevision == _captureRevision) {
        setState(() => _message = 'Rover could not capture this image.');
      }
    } finally {
      await _deleteCapture(capturePath);
      if (_activeCapturePath == capturePath) {
        _activeCapturePath = null;
      }
      if (mounted && requestRevision == _captureRevision) {
        setState(() => _analyzingCapture = false);
      }
    }
  }

  Future<LocationObservationCandidate?> _showLensResult(
    RoverLensAnalysis result,
    CameraOverlayCandidate? matchedOverlay,
    LocationObservationResolution? resolution,
  ) async {
    return showModalBottomSheet<LocationObservationCandidate>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => FractionallySizedBox(
        heightFactor: 0.72,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
            child: ListView(
              children: [
                Text(
                  _lensResultTitle(resolution, matchedOverlay),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                if (resolution?.status ==
                    LocationObservationResolutionStatus.ambiguous) ...[
                  const Text('Choose the place you are looking at.'),
                  const SizedBox(height: 8),
                  for (final candidate in resolution!.candidates)
                    _ObservationCandidateTile(
                      candidate: candidate,
                      onTap: () => Navigator.of(context).pop(candidate),
                    ),
                ] else if (resolution?.selectedCandidate case final candidate?)
                  _ObservationCandidateTile(candidate: candidate)
                else if (resolution != null &&
                    resolution.candidates.isNotEmpty) ...[
                  const Text(
                    'These places were considered, but the evidence was not strong enough to identify one.',
                  ),
                  const SizedBox(height: 8),
                  for (final candidate in resolution.candidates)
                    _ObservationCandidateTile(candidate: candidate),
                ] else if (matchedOverlay != null)
                  _LocalMatchTile(overlay: matchedOverlay),
                const SizedBox(height: 12),
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: const Text('Recognized text'),
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: SelectableText(result.recognizedText!),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  resolution == null
                      ? 'The image stayed on this device. The place result is local only.'
                      : 'The image stayed on this device. Only recognized text and location context were checked against sourced place data.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _lensResultTitle(
    LocationObservationResolution? resolution,
    CameraOverlayCandidate? matchedOverlay,
  ) {
    return switch (resolution?.status) {
      LocationObservationResolutionStatus.verified => 'Verified place',
      LocationObservationResolutionStatus.ambiguous => 'Possible places',
      LocationObservationResolutionStatus.unresolved => 'Unverified text',
      null =>
        matchedOverlay == null ? 'Text candidate' : matchedOverlay.place.name,
    };
  }

  CameraOverlayCandidate _overlayForResolvedPlace(
    LocationPlaceSummary place,
    RoverLatLng userLocation,
  ) {
    final candidate = CameraPlaceCandidate(
      id: place.canonicalId,
      name: place.name,
      coordinates: place.coordinates,
      category: place.categories.isEmpty ? 'Place' : place.categories.first,
      description:
          place.shortDescription ??
          place.facts
              .where((fact) => fact.factText.isNotEmpty)
              .map((fact) => fact.factText)
              .take(1)
              .join(),
      sourceLabel: place.sourceReferences.isEmpty
          ? 'Location Intelligence'
          : place.sourceReferences.first.providerName,
      confidence: place.confidenceScore,
      storyWorthiness: place.storyWorthinessScore,
      storyAvailable:
          place.facts.isNotEmpty || place.sourceReferences.isNotEmpty,
      addToWalkId: place.canonicalId,
      address: place.address,
      openingStatus: place.openingStatus,
      accessibilityInformation: place.accessibilityInformation,
      facts: place.facts
          .where((fact) => fact.factText.isNotEmpty)
          .map((fact) => fact.factText)
          .toList(growable: false),
      sourceAttribution: place.sourceReferences
          .map((source) => source.attribution)
          .where((attribution) => attribution.isNotEmpty)
          .toSet()
          .toList(),
      factIds: place.facts
          .map((fact) => fact.factId)
          .where((factId) => factId.isNotEmpty)
          .toList(),
    );
    final bearing = bearingBetween(userLocation, place.coordinates);
    final relative = _smoothedHeading == null
        ? 0.0
        : relativeBearing(bearing, _smoothedHeading!);
    return CameraOverlayCandidate(
      place: candidate,
      distanceMeters: userLocation.distanceTo(place.coordinates),
      bearingDegrees: bearing,
      relativeBearingDegrees: relative,
      horizontalPosition: 0.5,
      relativeDirection: directionLabel(relative),
      rankScore: place.confidenceScore * 100,
    );
  }

  Future<void> _deleteCapture(String? path) async {
    if (path == null || path.isEmpty) {
      return;
    }
    try {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {
      FieldDiagnostics.instance.record(
        'on-device-ai',
        'lens temporary image cleanup failed',
      );
    }
  }

  void _showHotelRates(CameraOverlayCandidate overlay) {
    FieldDiagnostics.instance.record(
      'commerce',
      'hotel rate sheet opened for ${overlay.place.id}',
    );
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => HotelRateSearchSheet(
        hotelName: overlay.place.name,
        placeId: overlay.place.id,
        coordinates: overlay.place.coordinates,
        repository: _hotelRateRepository,
      ),
    );
  }
}

class _ObservationCandidateTile extends StatelessWidget {
  const _ObservationCandidateTile({required this.candidate, this.onTap});

  final LocationObservationCandidate candidate;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final place = candidate.place;
    final confidence = (candidate.matchConfidence * 100).round();
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.place_outlined),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      place.name,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  if (onTap != null) const Icon(Icons.chevron_right),
                ],
              ),
              const SizedBox(height: 8),
              if (place.categories.isNotEmpty)
                Text(place.categories.take(3).join(' - ')),
              if (place.address case final address? when address.isNotEmpty)
                Text(address),
              if (place.shortDescription case final description?
                  when description.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(description),
              ],
              if (place.openingStatus case final opening?
                  when opening.isNotEmpty)
                Text('Hours/status: $opening'),
              if (place.accessibilityInformation case final accessibility?
                  when accessibility.isNotEmpty)
                Text('Accessibility: $accessibility'),
              for (final fact
                  in place.facts
                      .where((fact) => fact.factText.isNotEmpty)
                      .take(3))
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(fact.factText),
                ),
              const SizedBox(height: 8),
              Text('$confidence% sourced match'),
              if (candidate.matchReasons.isNotEmpty)
                Text(candidate.matchReasons.join(' - ')),
              if (place.sourceReferences.isNotEmpty)
                Text(
                  'Sources: ${place.sourceReferences.map((source) => source.providerName).toSet().join(', ')}',
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LocalMatchTile extends StatelessWidget {
  const _LocalMatchTile({required this.overlay});

  final CameraOverlayCandidate overlay;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.location_searching),
      title: Text(overlay.place.name),
      subtitle: Text(
        overlay.place.address ?? 'Matched to nearby sourced location context.',
      ),
    );
  }
}

class _CameraFallback extends StatelessWidget {
  const _CameraFallback({
    required this.loading,
    required this.permissionDenied,
    required this.error,
  });

  final bool loading;
  final bool permissionDenied;
  final String? error;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                permissionDenied
                    ? Icons.no_photography_outlined
                    : Icons.photo_camera_outlined,
                color: Colors.white,
                size: 48,
              ),
              const SizedBox(height: 16),
              if (loading) const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(
                error ?? 'Camera Explorer uses the rear camera without storing or uploading video.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(color: Colors.white),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OverlayLayer extends StatelessWidget {
  const _OverlayLayer({required this.overlays, required this.onSelected});

  final List<CameraOverlayCandidate> overlays;
  final ValueChanged<CameraOverlayCandidate> onSelected;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Stack(
          children: [
            Center(
              child: Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white70, width: 2),
                  shape: BoxShape.circle,
                ),
              ),
            ),
            for (var i = 0; i < overlays.length; i++)
              Positioned(
                left:
                    overlays[i].horizontalPosition * constraints.maxWidth - 92,
                top: 150 + i * 58,
                child: _PoiBubble(
                  overlay: overlays[i],
                  onTap: () => onSelected(overlays[i]),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _PoiBubble extends StatelessWidget {
  const _PoiBubble({required this.overlay, required this.onTap});

  final CameraOverlayCandidate overlay;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final place = overlay.place;
    return Semantics(
      button: true,
      label:
          '${place.name}, ${distanceLabel(overlay.distanceMeters)}, ${overlay.relativeDirection}',
      child: Material(
        color: Colors.black.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 184, minWidth: 132),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    place.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${distanceLabel(overlay.distanceMeters)} - ${overlay.relativeDirection}',
                    style: const TextStyle(color: Colors.white),
                  ),
                  if (place.isCurrentOrNextStop)
                    const Text(
                      'Walk stop',
                      style: TextStyle(color: Colors.white),
                    ),
                  if (place.storyAvailable)
                    const Text(
                      'Story available',
                      style: TextStyle(color: Colors.white),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CameraTopBar extends StatelessWidget {
  const _CameraTopBar({
    required this.muted,
    required this.recognitionEnabled,
    required this.recognizing,
    required this.onClose,
    required this.onMuteToggle,
    required this.onRecognize,
  });

  final bool muted;
  final bool recognitionEnabled;
  final bool recognizing;
  final VoidCallback onClose;
  final VoidCallback onMuteToggle;
  final VoidCallback onRecognize;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton.filledTonal(
          onPressed: onClose,
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Close Camera',
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Camera Explorer',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: Colors.white,
              shadows: const [Shadow(blurRadius: 6)],
            ),
          ),
        ),
        IconButton.filled(
          onPressed: recognizing || !recognitionEnabled ? null : onRecognize,
          icon: recognizing
              ? const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.center_focus_strong),
          tooltip: recognitionEnabled
              ? 'Scan sign'
              : 'Sign scanning was not enabled for this build',
        ),
        const SizedBox(width: 8),
        IconButton.filledTonal(
          onPressed: onMuteToggle,
          icon: Icon(muted ? Icons.volume_off : Icons.volume_up),
          tooltip: muted ? 'Unmute narration' : 'Mute narration',
        ),
      ],
    );
  }
}

class _CameraScanControl extends StatelessWidget {
  const _CameraScanControl({
    required this.enabled,
    required this.recognizing,
    required this.onPressed,
  });

  final bool enabled;
  final bool recognizing;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: enabled && !recognizing ? onPressed : null,
      icon: recognizing
          ? const SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.center_focus_strong),
      label: Text(
        recognizing
            ? 'Reading sign...'
            : enabled
            ? 'Scan sign'
            : 'Sign scan unavailable',
      ),
    );
  }
}

class _CameraStatusPill extends StatelessWidget {
  const _CameraStatusPill({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Text(message, style: const TextStyle(color: Colors.white)),
      ),
    );
  }
}

class _CameraPlaceCard extends StatelessWidget {
  const _CameraPlaceCard({
    required this.overlay,
    required this.activeWalk,
    required this.muted,
    required this.addingToWalk,
    required this.recognitionEnabled,
    required this.recognizing,
    required this.onDismiss,
    required this.onHearStory,
    required this.onTellMore,
    required this.onAddToWalk,
    required this.onOpenMap,
    required this.onWhatAmILookingAt,
    required this.onCheckRates,
  });

  final CameraOverlayCandidate overlay;
  final RoamSession activeWalk;
  final bool muted;
  final bool addingToWalk;
  final bool recognitionEnabled;
  final bool recognizing;
  final VoidCallback onDismiss;
  final VoidCallback onHearStory;
  final VoidCallback onTellMore;
  final VoidCallback? onAddToWalk;
  final VoidCallback onOpenMap;
  final VoidCallback onWhatAmILookingAt;
  final VoidCallback? onCheckRates;

  @override
  Widget build(BuildContext context) {
    final place = overlay.place;
    return Material(
      color: Theme.of(context).colorScheme.surface,
      elevation: 10,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    place.name,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  key: const Key('camera-place-card-dismiss'),
                  onPressed: onDismiss,
                  tooltip: 'Hide place information',
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${place.category} - ${distanceLabel(overlay.distanceMeters)} - ${overlay.relativeDirection}',
            ),
            if (place.address case final address? when address.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(address),
            ],
            const SizedBox(height: 6),
            if (place.description.isNotEmpty) Text(place.description),
            if (place.openingStatus case final opening? when opening.isNotEmpty)
              Text('Hours/status: $opening'),
            if (place.accessibilityInformation case final accessibility?
                when accessibility.isNotEmpty)
              Text('Accessibility: $accessibility'),
            for (final fact in place.facts.take(3)) Text(fact),
            const SizedBox(height: 6),
            Text(
              place.storyAvailable
                  ? 'Why this matters: Rover has sourced local context for this place.'
                  : 'This is a possible nearby match. Rover needs better sourced facts for a full story.',
            ),
            if (place.sourceAttribution.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text('Sources: ${place.sourceAttribution.join(', ')}'),
            ],
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: muted ? null : onHearStory,
                  icon: const Icon(Icons.volume_up),
                  label: const Text('Hear Story'),
                ),
                OutlinedButton.icon(
                  onPressed: muted ? null : onTellMore,
                  icon: const Icon(Icons.info_outline),
                  label: const Text('Tell Me More'),
                ),
                OutlinedButton.icon(
                  onPressed: addingToWalk ? null : onAddToWalk,
                  icon: const Icon(Icons.add_location_alt_outlined),
                  label: Text(
                    addingToWalk
                        ? 'Adding...'
                        : activeWalk.apiWalkSessionId == null
                        ? 'Start Walk'
                        : 'Add to Walk',
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: onOpenMap,
                  icon: const Icon(Icons.map_outlined),
                  label: const Text('Open in Map'),
                ),
                if (onCheckRates != null)
                  OutlinedButton.icon(
                    onPressed: onCheckRates,
                    icon: const Icon(Icons.hotel_outlined),
                    label: const Text('Check rates'),
                  ),
                OutlinedButton.icon(
                  onPressed: recognizing || !recognitionEnabled
                      ? null
                      : onWhatAmILookingAt,
                  icon: const Icon(Icons.center_focus_strong),
                  label: Text(
                    recognizing ? 'Reading...' : 'What am I looking at?',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
