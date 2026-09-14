import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;

import '../adventure/roam.dart';
import '../diagnostics/performance_diagnostics.dart';
import '../location/rover_location.dart';
import 'google_rover_map.dart';
import 'mapbox_config.dart';
import 'rover_map_provider.dart';

class RoverMapView extends StatefulWidget {
  const RoverMapView({
    required this.currentLocation,
    required this.orderedStops,
    required this.routeGeometry,
    this.currentStopIndex = 0,
    this.completedStopIds = const {},
    this.arrivalDebug,
    this.currentHeadingDegrees,
    this.mapProvider = const RoverMapProvider(),
    this.height = 360,
    this.showDebugOverlay = false,
    this.enableExpand = true,
    super.key,
  });

  final RoverLatLng? currentLocation;
  final List<OrderedRoverStop> orderedStops;
  final List<RoverLatLng> routeGeometry;
  final int currentStopIndex;
  final Set<String> completedStopIds;
  final RoverArrivalDebugInfo? arrivalDebug;
  final double? currentHeadingDegrees;
  final RoverMapProvider mapProvider;
  final double height;
  final bool showDebugOverlay;
  final bool enableExpand;

  @override
  State<RoverMapView> createState() => _RoverMapViewState();
}

class _RoverMapViewState extends State<RoverMapView> {
  static const _styleUri = mapbox.MapboxStyles.STANDARD;
  static const _initialZoom = 16.0;
  static const _minimumZoom = 12.0;
  static const _maximumZoom = 20.0;

  bool _mapInitialized = false;
  bool _styleLoaded = false;
  bool _mapLoaded = false;
  bool _annotationsDrawnByMapbox = false;
  bool _gesturesConfigured = false;
  bool _cameraFollowEnabled = true;
  bool _programmaticCameraMove = false;
  double _currentZoom = _initialZoom;
  double? _lastMovementBearing;
  String? _styleError;
  mapbox.MapboxMap? _mapboxMap;
  mapbox.PointAnnotationManager? _pointManager;
  mapbox.PointAnnotationManager? _currentLocationManager;
  mapbox.CircleAnnotationManager? _circleManager;
  mapbox.PolylineAnnotationManager? _polylineManager;
  mapbox.PolygonAnnotationManager? _polygonManager;
  String? _annotationSignature;
  List<_StopBubbleLayout> _stopBubbles = const [];

  @override
  void didUpdateWidget(covariant RoverMapView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final movedToNextStop =
        oldWidget.currentStopIndex != widget.currentStopIndex;
    if (movedToNextStop) {
      _cameraFollowEnabled = true;
    }
    if (_styleLoaded && widget.mapProvider.mode == RoverMapMode.mapbox) {
      if (_annotationSignature != _buildAnnotationSignature()) {
        unawaited(_drawMapboxAnnotations());
      } else if (oldWidget.currentLocation != widget.currentLocation) {
        unawaited(_updateCurrentLocationAnnotation());
      }
      unawaited(_updateStopBubblePositions());
    }
    if (_cameraFollowEnabled &&
        widget.mapProvider.mode == RoverMapMode.mapbox &&
        widget.currentLocation != null &&
        oldWidget.currentLocation != widget.currentLocation) {
      _lastMovementBearing = _bearingFromMovement(
        oldWidget.currentLocation,
        widget.currentLocation,
      );
      unawaited(_followCurrentLocation());
    }
  }

  @override
  void dispose() {
    _pointManager?.deleteAll();
    _currentLocationManager?.deleteAll();
    _circleManager?.deleteAll();
    _polylineManager?.deleteAll();
    _polygonManager?.deleteAll();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.mapProvider.mockMode ||
        (widget.currentLocation == null &&
            widget.routeGeometry.isEmpty &&
            widget.orderedStops.isEmpty)) {
      return SizedBox(
        height: widget.height,
        child: const Center(child: Text('Map unavailable')),
      );
    }
    final center = _toLatLng(
      widget.currentLocation ??
          (widget.routeGeometry.isNotEmpty
              ? widget.routeGeometry.first
              : null) ??
          widget.orderedStops.first.stop.coordinates,
    );
    final stopPoints = widget.orderedStops
        .map((orderedStop) => _toLatLng(orderedStop.stop.coordinates))
        .toList();
    final geometry = widget.routeGeometry.map(_toLatLng).toList();
    final markers = <Marker>[
      if (widget.currentLocation != null)
        Marker(
          point: center,
          width: 44,
          height: 44,
          child: const _MapPin(
            icon: Icons.my_location,
            label: 'Current location',
            color: Colors.indigo,
          ),
        ),
      for (final orderedStop in widget.orderedStops)
        Marker(
          point: _toLatLng(orderedStop.stop.coordinates),
          width: 48,
          height: 48,
          child: _MapPin(
            sequence: orderedStop.sequence,
            icon: _iconForStop(orderedStop.stop),
            label: '${orderedStop.sequence}. ${orderedStop.stop.name}',
            color: _colorForStop(orderedStop.stop, _statusFor(orderedStop)),
          ),
        ),
    ];

    return Semantics(
      label: 'Rover map with current location, route and ordered stops',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          height: widget.height,
          width: double.infinity,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (widget.mapProvider.mode == RoverMapMode.google)
                GoogleRoverMap(
                  currentLocation: widget.currentLocation,
                  orderedStops: widget.orderedStops,
                  routeGeometry: widget.routeGeometry,
                  currentStopIndex: widget.currentStopIndex,
                  completedStopIds: widget.completedStopIds,
                  currentHeadingDegrees: widget.currentHeadingDegrees,
                  routingProvider: widget.mapProvider.routingProvider,
                  showDebugOverlay: widget.showDebugOverlay,
                  hasExpandButton: widget.enableExpand,
                  onStopTap: (orderedStop) => _showStopDetails(
                    context,
                    orderedStop,
                    _statusFor(orderedStop),
                  ),
                )
              else if (widget.mapProvider.mode == RoverMapMode.mapbox)
                mapbox.MapWidget(
                  styleUri: _styleUri,
                  gestureRecognizers: {
                    Factory<OneSequenceGestureRecognizer>(
                      EagerGestureRecognizer.new,
                    ),
                  },
                  // ignore: deprecated_member_use
                  cameraOptions: mapbox.CameraOptions(
                    center: mapbox.Point(
                      coordinates: mapbox.Position(
                        center.longitude,
                        center.latitude,
                      ),
                    ),
                    zoom: _initialZoom,
                    pitch: 35,
                    bearing: _cameraBearing(
                      centerLocation: widget.currentLocation,
                    ),
                  ),
                  onMapCreated: _onMapCreated,
                  onCameraChangeListener: (data) {
                    final zoom = data.cameraState.zoom;
                    setState(() => _currentZoom = zoom);
                    unawaited(_updateStopBubblePositions());
                  },
                  onScrollListener: (_) => _pauseCameraFollow(),
                  onZoomListener: (_) => _pauseCameraFollow(),
                  onStyleLoadedListener: (_) {
                    setState(() {
                      _styleLoaded = true;
                      _styleError = null;
                    });
                    unawaited(_drawMapboxAnnotations());
                  },
                  onMapLoadedListener: (_) {
                    setState(() => _mapLoaded = true);
                  },
                  onMapLoadErrorListener: (data) {
                    setState(() {
                      _styleError = _sanitizeMapboxError(
                        '${data.type.name}: ${data.message}',
                      );
                    });
                  },
                  onResourceRequestListener: (data) {
                    final error = data.response?.error;
                    if (error == null) {
                      return;
                    }
                    setState(() {
                      _styleError = _sanitizeMapboxError(
                        '${error.reason.name}: ${error.message} ${data.request.url}',
                      );
                    });
                  },
                )
              else
                FlutterMap(
                  options: MapOptions(initialCenter: center, initialZoom: 15),
                  children: [
                    PolylineLayer(
                      polylines: [
                        Polyline(
                          points: geometry.isEmpty
                              ? [center, ...stopPoints]
                              : geometry,
                          strokeWidth: 4,
                          color: Theme.of(context).colorScheme.primary
                              .withValues(alpha: 0.72),
                        ),
                      ],
                    ),
                    MarkerLayer(markers: markers),
                  ],
                ),
              if (widget.mapProvider.mockMode)
                Positioned(
                  left: 12,
                  top: 12,
                  right: 12,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      child: Text(
                        widget.mapProvider.developmentMessage ??
                            'Development map',
                        style: Theme.of(context).textTheme.labelMedium,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ),
              if (kDebugMode && widget.showDebugOverlay)
                Positioned(
                  left: 12,
                  right: 12,
                  bottom: 12,
                  child: _MapboxDiagnosticsPanel(
                    tokenConfigured: widget.mapProvider.mapbox.hasPublicToken,
                    tokenLooksPublic:
                        widget.mapProvider.mapbox.tokenLooksPublic,
                    tokenVariableName: MapboxConfig.variableName,
                    mapInitialized: _mapInitialized,
                    styleLoaded: _styleLoaded,
                    mapLoaded: _mapLoaded,
                    styleUri: _styleUri,
                    styleError: _styleError,
                    routingProvider: widget.mapProvider.routingProvider,
                    annotationsDrawnByMapbox: _annotationsDrawnByMapbox,
                    gesturesConfigured: _gesturesConfigured,
                    cameraFollowEnabled: _cameraFollowEnabled,
                    currentZoom: _currentZoom,
                    arrivalDebug: widget.arrivalDebug,
                    mapSize: '${widget.height.round()} x full-width',
                  ),
                ),
              if (widget.enableExpand)
                Positioned(
                  right: 12,
                  top: 12,
                  child: FloatingActionButton.small(
                    heroTag: 'rover-map-expand-${widget.hashCode}',
                    tooltip: 'Expand map',
                    onPressed: () => _showExpandedMap(context),
                    child: const Icon(Icons.open_in_full),
                  ),
                ),
              if (widget.mapProvider.mode == RoverMapMode.mapbox)
                ..._stopBubbles.map(
                  (bubble) => Positioned(
                    left: bubble.left,
                    top: bubble.top,
                    width: bubble.width,
                    child: _StopBubble(
                      bubble: bubble,
                      onTap: () => _showStopDetails(
                        context,
                        bubble.orderedStop,
                        bubble.status,
                      ),
                    ),
                  ),
                ),
              if (widget.mapProvider.mode == RoverMapMode.mapbox &&
                  !_cameraFollowEnabled)
                Positioned(
                  right: 12,
                  top: widget.enableExpand ? 64 : 12,
                  child: FloatingActionButton.small(
                    heroTag: 'rover-map-recenter',
                    tooltip: 'Recenter on current location',
                    onPressed: _recenterAndResumeFollow,
                    child: const Icon(Icons.my_location),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  LatLng _toLatLng(RoverLatLng location) {
    return LatLng(location.latitude, location.longitude);
  }

  void _onMapCreated(mapbox.MapboxMap mapboxMap) {
    unawaited(_handleMapCreated(mapboxMap));
  }

  Future<void> _handleMapCreated(mapbox.MapboxMap mapboxMap) async {
    _mapboxMap = mapboxMap;
    setState(() => _mapInitialized = true);
    await _configureMapboxGestures(mapboxMap);
    await _configureMapboxLocationPuck(mapboxMap);
    await mapboxMap.setBounds(
      mapbox.CameraBoundsOptions(minZoom: _minimumZoom, maxZoom: _maximumZoom),
    );
    await _followCurrentLocation();
  }

  Future<void> _configureMapboxGestures(mapbox.MapboxMap mapboxMap) async {
    await mapboxMap.gestures.updateSettings(
      mapbox.GesturesSettings(
        rotateEnabled: true,
        pinchToZoomEnabled: true,
        scrollEnabled: true,
        simultaneousRotateAndPinchToZoomEnabled: true,
        pitchEnabled: true,
        scrollMode: mapbox.ScrollMode.HORIZONTAL_AND_VERTICAL,
        doubleTapToZoomInEnabled: true,
        doubleTouchToZoomOutEnabled: true,
        quickZoomEnabled: true,
        pinchToZoomDecelerationEnabled: true,
        rotateDecelerationEnabled: true,
        scrollDecelerationEnabled: true,
        pinchPanEnabled: true,
      ),
    );
    if (mounted) {
      setState(() => _gesturesConfigured = true);
    }
  }

  Future<void> _configureMapboxLocationPuck(mapbox.MapboxMap mapboxMap) async {
    await mapboxMap.location.updateSettings(
      mapbox.LocationComponentSettings(
        enabled: true,
        pulsingEnabled: true,
        pulsingColor: Colors.blueAccent.toARGB32(),
        pulsingMaxRadius: 32,
        showAccuracyRing: true,
        accuracyRingColor: Colors.blueAccent.withValues(alpha: 0.18).toARGB32(),
        accuracyRingBorderColor: Colors.blueAccent.toARGB32(),
        puckBearingEnabled: true,
        puckBearing: mapbox.PuckBearing.COURSE,
      ),
    );
  }

  void _pauseCameraFollow() {
    if (_programmaticCameraMove || !_cameraFollowEnabled) {
      return;
    }
    setState(() => _cameraFollowEnabled = false);
  }

  Future<void> _recenterAndResumeFollow() async {
    setState(() => _cameraFollowEnabled = true);
    await _followCurrentLocation();
  }

  Future<void> _followCurrentLocation() async {
    final map = _mapboxMap;
    final location = widget.currentLocation;
    if (map == null || location == null) {
      return;
    }
    _programmaticCameraMove = true;
    try {
      await map.easeTo(
        mapbox.CameraOptions(
          center: mapbox.Point(coordinates: _toPosition(location)),
          zoom: math.max(
            16,
            _currentZoom.clamp(_minimumZoom, _maximumZoom).toDouble(),
          ),
          pitch: 35,
          bearing: _cameraBearing(centerLocation: location),
        ),
        mapbox.MapAnimationOptions(duration: 450),
      );
    } finally {
      Future<void>.delayed(const Duration(milliseconds: 500), () {
        _programmaticCameraMove = false;
      });
    }
  }

  Future<void> _drawMapboxAnnotations() async {
    final stopwatch = Stopwatch()..start();
    final map = _mapboxMap;
    if (map == null) {
      return;
    }

    _pointManager ??= await map.annotations.createPointAnnotationManager();
    _currentLocationManager ??= await map.annotations
        .createPointAnnotationManager();
    _circleManager ??= await map.annotations.createCircleAnnotationManager();
    _polylineManager ??= await map.annotations
        .createPolylineAnnotationManager();
    _polygonManager ??= await map.annotations.createPolygonAnnotationManager();
    await _pointManager?.deleteAll();
    await _currentLocationManager?.deleteAll();
    await _circleManager?.deleteAll();
    await _polylineManager?.deleteAll();
    await _polygonManager?.deleteAll();

    for (final orderedStop in widget.orderedStops) {
      final status = _statusFor(orderedStop);
      final ringColor = switch (status) {
        _StopBubbleStatus.visited => Colors.green,
        _StopBubbleStatus.current => Colors.blueAccent,
        _StopBubbleStatus.future => Colors.deepPurpleAccent,
      };
      final opacity = switch (status) {
        _StopBubbleStatus.visited => 0.08,
        _StopBubbleStatus.current => 0.16,
        _StopBubbleStatus.future => 0.10,
      };

      await _polygonManager?.create(
        mapbox.PolygonAnnotationOptions(
          geometry: mapbox.Polygon(
            coordinates: [
              _arrivalRadiusRing(
                orderedStop.stop.coordinates,
                orderedStop.stop.arrivalRadiusMeters,
              ),
            ],
          ),
          fillColor: ringColor.toARGB32(),
          fillOpacity: opacity,
          fillOutlineColor: ringColor.toARGB32(),
          fillSortKey: 0,
        ),
      );
    }

    final route = widget.routeGeometry.isEmpty
        ? widget.orderedStops.map((stop) => stop.stop.coordinates).toList()
        : widget.routeGeometry;
    if (route.length >= 2) {
      await _polylineManager?.create(
        mapbox.PolylineAnnotationOptions(
          geometry: mapbox.LineString(
            coordinates: route.map(_toPosition).toList(),
          ),
          lineColor: Colors.deepPurpleAccent.toARGB32(),
          lineWidth: 4,
        ),
      );
    }

    final circles = <mapbox.CircleAnnotationOptions>[
      for (final orderedStop in widget.orderedStops)
        mapbox.CircleAnnotationOptions(
          geometry: mapbox.Point(
            coordinates: _toPosition(orderedStop.stop.coordinates),
          ),
          circleColor: orderedStop.stop.isSponsored
              ? Colors.amber.toARGB32()
              : Colors.teal.toARGB32(),
          circleRadius: 7,
          circleStrokeColor: Colors.white.toARGB32(),
          circleStrokeWidth: 2,
        ),
    ];

    if (circles.isNotEmpty) {
      await _circleManager?.createMulti(circles);
    }

    final points = <mapbox.PointAnnotationOptions>[
      for (final orderedStop in widget.orderedStops)
        mapbox.PointAnnotationOptions(
          geometry: mapbox.Point(
            coordinates: _toPosition(orderedStop.stop.coordinates),
          ),
          textField:
              '${orderedStop.sequence} ${_glyphForStop(orderedStop.stop)}',
          textSize: 22,
          textColor: _colorForStop(
            orderedStop.stop,
            _statusFor(orderedStop),
          ).toARGB32(),
          textHaloColor: Colors.white.toARGB32(),
          textHaloWidth: 2,
          symbolSortKey: 500 + orderedStop.sequence.toDouble(),
        ),
    ];

    if (points.isNotEmpty) {
      await _pointManager?.createMulti(points);
    }
    await _updateCurrentLocationAnnotation();

    if (mounted) {
      setState(() {
        _annotationsDrawnByMapbox = true;
        _annotationSignature = _buildAnnotationSignature();
      });
    }
    PerformanceDiagnostics.instance.record(
      'map annotation redraw (${widget.orderedStops.length} stops)',
      stopwatch.elapsed,
    );
  }

  Future<void> _updateCurrentLocationAnnotation() async {
    final map = _mapboxMap;
    if (map == null) {
      return;
    }
    _currentLocationManager ??= await map.annotations
        .createPointAnnotationManager();
    await _currentLocationManager?.deleteAll();
    final location = widget.currentLocation;
    if (location == null) {
      return;
    }

    final stopwatch = Stopwatch()..start();
    await _currentLocationManager?.create(
      mapbox.PointAnnotationOptions(
        geometry: mapbox.Point(coordinates: _toPosition(location)),
        textField: '●',
        textSize: 30,
        textColor: Colors.blueAccent.toARGB32(),
        textHaloColor: Colors.white.toARGB32(),
        textHaloWidth: 4,
        symbolSortKey: 1000,
      ),
    );
    PerformanceDiagnostics.instance.record(
      'map current-location redraw',
      stopwatch.elapsed,
    );
  }

  String _buildAnnotationSignature() {
    final routeKey = widget.routeGeometry
        .map(
          (point) =>
              '${point.latitude.toStringAsFixed(6)},${point.longitude.toStringAsFixed(6)}',
        )
        .join('|');
    final stopKey = widget.orderedStops
        .map(
          (orderedStop) =>
              '${orderedStop.sequence}:${orderedStop.stop.id}:${orderedStop.stop.category}:${orderedStop.stop.arrivalRadiusMeters}',
        )
        .join('|');
    final completedKey = widget.completedStopIds.toList()..sort();
    return [
      widget.currentStopIndex,
      stopKey,
      routeKey,
      completedKey.join(','),
    ].join('::');
  }

  mapbox.Position _toPosition(RoverLatLng location) {
    return mapbox.Position(location.longitude, location.latitude);
  }

  double _cameraBearing({RoverLatLng? centerLocation}) {
    final heading = widget.currentHeadingDegrees;
    if (heading != null && heading >= 0 && heading <= 360) {
      return heading;
    }

    if (_lastMovementBearing != null) {
      return _lastMovementBearing!;
    }

    final origin = centerLocation ?? widget.currentLocation;
    if (origin == null) {
      return 0;
    }

    RoverLatLng? routeTarget;
    for (final point in widget.routeGeometry) {
      if (point.distanceTo(origin) > 8) {
        routeTarget = point;
        break;
      }
    }
    final stopTarget = _currentOrderedStop?.stop.coordinates;
    final target = routeTarget ?? stopTarget;
    return target == null ? 0 : _bearingBetween(origin, target);
  }

  double? _bearingFromMovement(RoverLatLng? previous, RoverLatLng? current) {
    if (previous == null || current == null) {
      return null;
    }

    if (previous.distanceTo(current) < 3) {
      return _lastMovementBearing;
    }

    return _bearingBetween(previous, current);
  }

  double _bearingBetween(RoverLatLng from, RoverLatLng to) {
    final fromLat = from.latitude * math.pi / 180;
    final toLat = to.latitude * math.pi / 180;
    final deltaLng = (to.longitude - from.longitude) * math.pi / 180;
    final y = math.sin(deltaLng) * math.cos(toLat);
    final x =
        math.cos(fromLat) * math.sin(toLat) -
        math.sin(fromLat) * math.cos(toLat) * math.cos(deltaLng);
    return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
  }

  OrderedRoverStop? get _currentOrderedStop {
    if (widget.orderedStops.isEmpty) {
      return null;
    }
    final index = widget.currentStopIndex.clamp(
      0,
      widget.orderedStops.length - 1,
    );
    return widget.orderedStops[index];
  }

  List<mapbox.Position> _arrivalRadiusRing(
    RoverLatLng center,
    int radiusMeters,
  ) {
    const earthRadiusMeters = 6378137.0;
    final lat = center.latitude * math.pi / 180;
    final lng = center.longitude * math.pi / 180;
    final angularDistance = radiusMeters / earthRadiusMeters;
    final positions = <mapbox.Position>[];

    for (var degrees = 0; degrees <= 360; degrees += 12) {
      final bearing = degrees * math.pi / 180;
      final ringLat = math.asin(
        math.sin(lat) * math.cos(angularDistance) +
            math.cos(lat) * math.sin(angularDistance) * math.cos(bearing),
      );
      final ringLng =
          lng +
          math.atan2(
            math.sin(bearing) * math.sin(angularDistance) * math.cos(lat),
            math.cos(angularDistance) - math.sin(lat) * math.sin(ringLat),
          );
      positions.add(
        mapbox.Position(ringLng * 180 / math.pi, ringLat * 180 / math.pi),
      );
    }
    return positions;
  }

  Future<void> _updateStopBubblePositions() async {
    final map = _mapboxMap;
    if (map == null || widget.orderedStops.isEmpty || !mounted) {
      return;
    }

    final coordinates = widget.orderedStops
        .map(
          (stop) =>
              mapbox.Point(coordinates: _toPosition(stop.stop.coordinates)),
        )
        .toList();
    final pixels = await map.pixelsForCoordinates(coordinates);
    if (!mounted) {
      return;
    }

    final bubbles = <_StopBubbleLayout>[];
    final occupied = <Rect>[];
    for (var i = 0; i < widget.orderedStops.length; i++) {
      final pixel = pixels[i];
      if (pixel == null) {
        continue;
      }
      final orderedStop = widget.orderedStops[i];
      final status = _statusFor(orderedStop);
      final isCurrent = i == widget.currentStopIndex;
      final width = isCurrent ? 168.0 : 116.0;
      final height = isCurrent ? 50.0 : 38.0;
      final rect = Rect.fromLTWH(
        pixel.x - (width / 2),
        pixel.y - height - 28,
        width,
        height,
      );
      if (!isCurrent &&
          occupied.any((existing) => existing.overlaps(rect.inflate(8)))) {
        continue;
      }
      occupied.add(rect);
      bubbles.add(
        _StopBubbleLayout(
          orderedStop: orderedStop,
          status: status,
          left: rect.left,
          top: rect.top,
          width: width,
        ),
      );
    }
    setState(() => _stopBubbles = bubbles);
  }

  _StopBubbleStatus _statusFor(OrderedRoverStop orderedStop) {
    if (widget.completedStopIds.contains(orderedStop.stop.id)) {
      return _StopBubbleStatus.visited;
    }
    if (orderedStop.sequence - 1 == widget.currentStopIndex) {
      return _StopBubbleStatus.current;
    }
    return _StopBubbleStatus.future;
  }

  IconData _iconForStop(RoverStop stop) {
    final category = '${stop.category} ${stop.contentType}'.toLowerCase();
    if (category.contains('burger')) return Icons.lunch_dining;
    if (category.contains('coffee') || category.contains('cafe')) {
      return Icons.coffee;
    }
    if (category.contains('tea')) return Icons.emoji_food_beverage;
    if (category.contains('history') ||
        category.contains('architecture') ||
        category.contains('landmark')) {
      return Icons.account_balance;
    }
    if (category.contains('bakery') || category.contains('cake')) {
      return Icons.cake;
    }
    return Icons.place;
  }

  String _glyphForStop(RoverStop stop) {
    final category = '${stop.category} ${stop.contentType}'.toLowerCase();
    if (category.contains('burger')) return '🍔';
    if (category.contains('coffee') || category.contains('cafe')) return '☕';
    if (category.contains('tea')) return '🍵';
    if (category.contains('bakery') || category.contains('cake')) return '🍰';
    if (category.contains('history') ||
        category.contains('architecture') ||
        category.contains('landmark')) {
      return 'H';
    }
    return '•';
  }

  Color _colorForStop(RoverStop stop, _StopBubbleStatus status) {
    if (stop.isSponsored) return Colors.amber.shade800;
    final category = '${stop.category} ${stop.contentType}'.toLowerCase();
    if (category.contains('burger')) return Colors.deepOrange.shade700;
    if (category.contains('coffee') || category.contains('cafe')) {
      return Colors.brown.shade700;
    }
    if (category.contains('tea')) return Colors.green.shade700;
    if (category.contains('bakery') || category.contains('cake')) {
      return Colors.pink.shade700;
    }
    if (category.contains('history') ||
        category.contains('architecture') ||
        category.contains('landmark')) {
      return Colors.indigo.shade700;
    }
    return switch (status) {
      _StopBubbleStatus.visited => Colors.green.shade700,
      _StopBubbleStatus.current => Colors.blueAccent,
      _StopBubbleStatus.future => Colors.deepPurpleAccent,
    };
  }

  String _sanitizeMapboxError(String value) {
    return value
        .replaceAll(RegExp(r'access_token=[^&\s]+'), 'access_token=<redacted>')
        .replaceAll(RegExp(r'pk\.[A-Za-z0-9._-]+'), 'pk.<redacted>')
        .replaceAll(RegExp(r'sk\.[A-Za-z0-9._-]+'), 'sk.<redacted>')
        .replaceAll(RegExp(r'\?.*'), '?<redacted>');
  }

  void _showStopDetails(
    BuildContext context,
    OrderedRoverStop orderedStop,
    _StopBubbleStatus status,
  ) {
    final stop = orderedStop.stop;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        final disclosure = stop.sponsoredDisclosure;
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${orderedStop.sequence}. ${stop.name}',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 6),
              Text('Status: ${status.label}'),
              const SizedBox(height: 12),
              Text(stop.shortDescription),
              if (stop.address != null) Text(stop.address!),
              if (stop.phoneNumber != null) Text(stop.phoneNumber!),
              if (stop.websiteUrl != null) Text(stop.websiteUrl!),
              if (stop.menuUrl != null) Text('Menu: ${stop.menuUrl!}'),
              const SizedBox(height: 12),
              Text('Content type: ${stop.contentType ?? stop.category}'),
              Text('Estimated visit: ${stop.estimatedVisitMinutes} min'),
              if (stop.distanceFromPreviousStopMeters > 0)
                Text(
                  'From previous stop: ${stop.distanceFromPreviousStopMeters} m',
                ),
              Text('Arrival radius: ${stop.arrivalRadiusMeters} m'),
              if (disclosure != null && disclosure.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text('Sponsored: $disclosure'),
              ],
            ],
          ),
        );
      },
    );
  }

  void _showExpandedMap(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) {
        return Dialog.fullscreen(
          child: SafeArea(
            child: Column(
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: IconButton(
                    tooltip: 'Close map',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ),
                Expanded(
                  child: RoverMapView(
                    currentLocation: widget.currentLocation,
                    orderedStops: widget.orderedStops,
                    routeGeometry: widget.routeGeometry,
                    currentStopIndex: widget.currentStopIndex,
                    completedStopIds: widget.completedStopIds,
                    arrivalDebug: widget.arrivalDebug,
                    currentHeadingDegrees: widget.currentHeadingDegrees,
                    mapProvider: widget.mapProvider,
                    height: double.infinity,
                    enableExpand: false,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class RoverArrivalDebugInfo {
  const RoverArrivalDebugInfo({
    this.currentGpsAccuracyMeters,
    this.distanceToNextStopMeters,
    this.arrivalRadiusMeters,
    this.arrivalCandidateReadingCount = 0,
    this.arrivalCandidateStopId,
  });

  final double? currentGpsAccuracyMeters;
  final double? distanceToNextStopMeters;
  final int? arrivalRadiusMeters;
  final int arrivalCandidateReadingCount;
  final String? arrivalCandidateStopId;

  bool get hasArrivalCandidate => arrivalCandidateStopId != null;
}

enum _StopBubbleStatus {
  visited('Visited', Icons.check_circle_outline),
  current('Current', Icons.navigation_outlined),
  future('Future', Icons.radio_button_unchecked);

  const _StopBubbleStatus(this.label, this.icon);

  final String label;
  final IconData icon;
}

class _StopBubbleLayout {
  const _StopBubbleLayout({
    required this.orderedStop,
    required this.status,
    required this.left,
    required this.top,
    required this.width,
  });

  final OrderedRoverStop orderedStop;
  final _StopBubbleStatus status;
  final double left;
  final double top;
  final double width;
}

class _StopBubble extends StatelessWidget {
  const _StopBubble({required this.bubble, required this.onTap});

  final _StopBubbleLayout bubble;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isCurrent = bubble.status == _StopBubbleStatus.current;
    return Semantics(
      button: true,
      label:
          'Stop ${bubble.orderedStop.sequence}, ${bubble.orderedStop.stop.name}, ${bubble.status.label}',
      child: Material(
        color: isCurrent ? scheme.primaryContainer : scheme.surface,
        elevation: isCurrent ? 4 : 2,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              children: [
                Icon(bubble.status.icon, size: 14),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    '${bubble.orderedStop.sequence}. ${bubble.orderedStop.stop.name}\n${bubble.status.label}',
                    maxLines: isCurrent ? 2 : 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MapboxDiagnosticsPanel extends StatelessWidget {
  const _MapboxDiagnosticsPanel({
    required this.tokenConfigured,
    required this.tokenLooksPublic,
    required this.tokenVariableName,
    required this.mapInitialized,
    required this.styleLoaded,
    required this.mapLoaded,
    required this.styleUri,
    required this.routingProvider,
    required this.annotationsDrawnByMapbox,
    required this.gesturesConfigured,
    required this.cameraFollowEnabled,
    required this.currentZoom,
    required this.mapSize,
    this.arrivalDebug,
    this.styleError,
  });

  final bool tokenConfigured;
  final bool tokenLooksPublic;
  final String tokenVariableName;
  final bool mapInitialized;
  final bool styleLoaded;
  final bool mapLoaded;
  final String styleUri;
  final String routingProvider;
  final bool annotationsDrawnByMapbox;
  final bool gesturesConfigured;
  final bool cameraFollowEnabled;
  final double currentZoom;
  final String mapSize;
  final RoverArrivalDebugInfo? arrivalDebug;
  final String? styleError;

  @override
  Widget build(BuildContext context) {
    final text = [
      'Mapbox debug',
      'token configured: ${tokenConfigured ? 'yes' : 'no'}',
      'token variable: $tokenVariableName',
      'token prefix: ${tokenLooksPublic ? 'pk' : 'not-public'}',
      'map initialized: ${mapInitialized ? 'yes' : 'no'}',
      'style loaded: ${styleLoaded ? 'yes' : 'no'}',
      'map loaded: ${mapLoaded ? 'yes' : 'no'}',
      'style: $styleUri',
      'annotations: ${annotationsDrawnByMapbox ? 'Mapbox' : 'pending'}',
      'gestures: ${gesturesConfigured ? 'configured' : 'pending'}',
      'camera follow: ${cameraFollowEnabled ? 'on' : 'paused'}',
      'zoom: ${currentZoom.toStringAsFixed(1)}',
      'routing provider: $routingProvider',
      'map size: $mapSize',
      if (arrivalDebug != null) ...[
        'GPS accuracy: ${_meters(arrivalDebug!.currentGpsAccuracyMeters)}',
        'distance to next: ${_meters(arrivalDebug!.distanceToNextStopMeters)}',
        'arrival radius: ${arrivalDebug!.arrivalRadiusMeters ?? '-'} m',
        'qualifying readings: ${arrivalDebug!.arrivalCandidateReadingCount}',
        'arrival candidate: ${arrivalDebug!.hasArrivalCandidate ? 'yes' : 'no'}',
      ],
      if (styleError != null) 'style error: $styleError',
    ].join(' | ');

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Text(
          text,
          style: Theme.of(context).textTheme.labelSmall,
          maxLines: 7,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }

  static String _meters(double? value) {
    return value == null ? '-' : '${value.round()} m';
  }
}

class _MapPin extends StatelessWidget {
  const _MapPin({required this.label, this.sequence, this.icon, this.color});

  final String label;
  final int? sequence;
  final IconData? icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final pinColor = color ?? Theme.of(context).colorScheme.primary;
    return Tooltip(
      message: label,
      child: Semantics(
        label: label,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: pinColor,
            shape: BoxShape.circle,
            border: Border.all(
              color: Theme.of(context).colorScheme.surface,
              width: 2,
            ),
          ),
          child: SizedBox(
            width: 34,
            height: 34,
            child: Center(
              child: Stack(
                alignment: Alignment.center,
                clipBehavior: Clip.none,
                children: [
                  Icon(
                    icon ?? Icons.place,
                    color: Theme.of(context).colorScheme.onPrimary,
                    size: 19,
                  ),
                  if (sequence != null)
                    Positioned(
                      right: -7,
                      top: -7,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surface,
                          shape: BoxShape.circle,
                          border: Border.all(color: pinColor, width: 1),
                        ),
                        child: SizedBox(
                          width: 16,
                          height: 16,
                          child: Center(
                            child: Text(
                              sequence.toString(),
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(
                                    color: pinColor,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 9,
                                  ),
                            ),
                          ),
                        ),
                      ),
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
