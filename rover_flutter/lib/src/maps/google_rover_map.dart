import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as google;

import '../adventure/roam.dart';
import '../diagnostics/performance_diagnostics.dart';
import '../location/rover_location.dart';

class GoogleRoverMap extends StatefulWidget {
  const GoogleRoverMap({
    required this.currentLocation,
    required this.orderedStops,
    required this.routeGeometry,
    required this.currentStopIndex,
    required this.completedStopIds,
    required this.onStopTap,
    this.currentHeadingDegrees,
    this.routingProvider = 'Unknown',
    this.showDebugOverlay = false,
    this.hasExpandButton = true,
    super.key,
  });

  final RoverLatLng? currentLocation;
  final List<OrderedRoverStop> orderedStops;
  final List<RoverLatLng> routeGeometry;
  final int currentStopIndex;
  final Set<String> completedStopIds;
  final double? currentHeadingDegrees;
  final String routingProvider;
  final bool showDebugOverlay;
  final bool hasExpandButton;
  final ValueChanged<OrderedRoverStop> onStopTap;

  @override
  State<GoogleRoverMap> createState() => _GoogleRoverMapState();
}

class _GoogleRoverMapState extends State<GoogleRoverMap> {
  static const _initialZoom = 16.0;
  static const _minimumZoom = 12.0;
  static const _maximumZoom = 20.0;

  google.GoogleMapController? _controller;
  bool _mapInitialized = false;
  bool _cameraFollowEnabled = true;
  bool _programmaticCameraMove = false;
  double _currentZoom = _initialZoom;
  double? _lastMovementBearing;

  @override
  void didUpdateWidget(covariant GoogleRoverMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentStopIndex != widget.currentStopIndex) {
      _cameraFollowEnabled = true;
    }
    if (_cameraFollowEnabled &&
        widget.currentLocation != null &&
        (oldWidget.currentLocation != widget.currentLocation ||
            oldWidget.currentHeadingDegrees != widget.currentHeadingDegrees)) {
      _lastMovementBearing = _bearingFromMovement(
        oldWidget.currentLocation,
        widget.currentLocation,
      );
      unawaited(_followCurrentLocation());
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.currentLocation == null &&
        widget.routeGeometry.isEmpty &&
        widget.orderedStops.isEmpty) {
      return const Center(child: Text('Map unavailable'));
    }
    final center = _googleLatLng(
      widget.currentLocation ??
          (widget.routeGeometry.isNotEmpty
              ? widget.routeGeometry.first
              : null) ??
          widget.orderedStops.first.stop.coordinates,
    );

    return Stack(
      fit: StackFit.expand,
      children: [
        google.GoogleMap(
          initialCameraPosition: google.CameraPosition(
            target: center,
            zoom: _initialZoom,
            tilt: 35,
            bearing: _cameraBearing(centerLocation: widget.currentLocation),
          ),
          minMaxZoomPreference: const google.MinMaxZoomPreference(
            _minimumZoom,
            _maximumZoom,
          ),
          mapType: google.MapType.normal,
          compassEnabled: true,
          buildingsEnabled: true,
          indoorViewEnabled: true,
          mapToolbarEnabled: false,
          myLocationEnabled: widget.currentLocation != null,
          myLocationButtonEnabled: false,
          rotateGesturesEnabled: true,
          scrollGesturesEnabled: true,
          tiltGesturesEnabled: true,
          zoomControlsEnabled: true,
          zoomGesturesEnabled: true,
          gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
            Factory<_RoverMapGestureRecognizer>(
              () => _RoverMapGestureRecognizer(_pauseCameraFollow),
            ),
          },
          markers: _markers(),
          polylines: _polylines(),
          circles: _geofences(),
          onMapCreated: _onMapCreated,
          onCameraMoveStarted: _pauseCameraFollow,
          onCameraMove: (position) => _currentZoom = position.zoom,
        ),
        if (!_cameraFollowEnabled && widget.currentLocation != null)
          Positioned(
            right: 12,
            top: widget.hasExpandButton ? 64 : 12,
            child: FloatingActionButton.small(
              heroTag: 'google-rover-map-recenter-${widget.hashCode}',
              tooltip: 'Recenter on current location',
              onPressed: _recenterAndResumeFollow,
              child: const Icon(Icons.my_location),
            ),
          ),
        if (kDebugMode && widget.showDebugOverlay)
          Positioned(
            left: 12,
            right: 12,
            bottom: 12,
            child: _GoogleMapDiagnosticsPanel(
              mapInitialized: _mapInitialized,
              cameraFollowEnabled: _cameraFollowEnabled,
              currentZoom: _currentZoom,
              markerCount: widget.orderedStops.length,
              routingProvider: widget.routingProvider,
            ),
          ),
      ],
    );
  }

  Set<google.Marker> _markers() {
    return {
      for (final orderedStop in widget.orderedStops)
        google.Marker(
          markerId: google.MarkerId('rover-stop-${orderedStop.stop.id}'),
          position: _googleLatLng(orderedStop.stop.coordinates),
          zIndexInt: 500 + orderedStop.sequence,
          icon: google.BitmapDescriptor.defaultMarkerWithHue(
            _markerHue(orderedStop),
          ),
          infoWindow: google.InfoWindow(
            title: '${orderedStop.sequence}. ${orderedStop.stop.name}',
            snippet: _status(orderedStop).label,
            onTap: () => widget.onStopTap(orderedStop),
          ),
          onTap: () => widget.onStopTap(orderedStop),
        ),
    };
  }

  Set<google.Polyline> _polylines() {
    final route = widget.routeGeometry.isEmpty
        ? widget.orderedStops.map((stop) => stop.stop.coordinates).toList()
        : widget.routeGeometry;
    if (route.length < 2) {
      return const {};
    }
    return {
      google.Polyline(
        polylineId: const google.PolylineId('rover-route'),
        points: route.map(_googleLatLng).toList(),
        color: Colors.deepPurpleAccent,
        width: 5,
        geodesic: true,
        startCap: google.Cap.roundCap,
        endCap: google.Cap.roundCap,
        jointType: google.JointType.round,
      ),
    };
  }

  Set<google.Circle> _geofences() {
    return {
      for (final orderedStop in widget.orderedStops)
        google.Circle(
          circleId: google.CircleId('rover-geofence-${orderedStop.stop.id}'),
          center: _googleLatLng(orderedStop.stop.coordinates),
          radius: orderedStop.stop.arrivalRadiusMeters.toDouble(),
          fillColor: _statusColor(orderedStop).withValues(
            alpha: _status(orderedStop) == _GoogleStopStatus.current
                ? 0.16
                : 0.09,
          ),
          strokeColor: _statusColor(orderedStop).withValues(alpha: 0.85),
          strokeWidth: _status(orderedStop) == _GoogleStopStatus.current
              ? 3
              : 1,
          zIndex: 1,
        ),
    };
  }

  Future<void> _onMapCreated(google.GoogleMapController controller) async {
    _controller = controller;
    if (mounted) {
      setState(() => _mapInitialized = true);
    }
    PerformanceDiagnostics.instance.record(
      'google map initialize',
      Duration.zero,
    );
    await _followCurrentLocation();
  }

  void _pauseCameraFollow() {
    if (_programmaticCameraMove || !_cameraFollowEnabled || !mounted) {
      return;
    }
    setState(() => _cameraFollowEnabled = false);
  }

  Future<void> _recenterAndResumeFollow() async {
    setState(() => _cameraFollowEnabled = true);
    await _followCurrentLocation();
  }

  Future<void> _followCurrentLocation() async {
    final controller = _controller;
    final location = widget.currentLocation;
    if (controller == null || location == null) {
      return;
    }

    _programmaticCameraMove = true;
    try {
      await controller.animateCamera(
        google.CameraUpdate.newCameraPosition(
          google.CameraPosition(
            target: _googleLatLng(location),
            zoom: math.max(
              16,
              _currentZoom.clamp(_minimumZoom, _maximumZoom).toDouble(),
            ),
            tilt: 35,
            bearing: _cameraBearing(centerLocation: location),
          ),
        ),
      );
    } finally {
      Future<void>.delayed(const Duration(milliseconds: 500), () {
        _programmaticCameraMove = false;
      });
    }
  }

  google.LatLng _googleLatLng(RoverLatLng location) {
    return google.LatLng(location.latitude, location.longitude);
  }

  _GoogleStopStatus _status(OrderedRoverStop orderedStop) {
    if (widget.completedStopIds.contains(orderedStop.stop.id)) {
      return _GoogleStopStatus.visited;
    }
    if (orderedStop.sequence - 1 == widget.currentStopIndex) {
      return _GoogleStopStatus.current;
    }
    return _GoogleStopStatus.future;
  }

  Color _statusColor(OrderedRoverStop orderedStop) {
    if (orderedStop.stop.isSponsored) {
      return Colors.amber.shade800;
    }
    return switch (_status(orderedStop)) {
      _GoogleStopStatus.visited => Colors.green.shade700,
      _GoogleStopStatus.current => Colors.blueAccent,
      _GoogleStopStatus.future => Colors.deepPurpleAccent,
    };
  }

  double _markerHue(OrderedRoverStop orderedStop) {
    if (orderedStop.stop.isSponsored) {
      return google.BitmapDescriptor.hueOrange;
    }
    return switch (_status(orderedStop)) {
      _GoogleStopStatus.visited => google.BitmapDescriptor.hueGreen,
      _GoogleStopStatus.current => google.BitmapDescriptor.hueAzure,
      _GoogleStopStatus.future => google.BitmapDescriptor.hueViolet,
    };
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
}

class _RoverMapGestureRecognizer extends EagerGestureRecognizer {
  _RoverMapGestureRecognizer(this.onPointerDown);

  final VoidCallback onPointerDown;

  @override
  void addAllowedPointer(PointerDownEvent event) {
    onPointerDown();
    super.addAllowedPointer(event);
  }
}

enum _GoogleStopStatus {
  visited('Visited'),
  current('Current'),
  future('Future');

  const _GoogleStopStatus(this.label);

  final String label;
}

class _GoogleMapDiagnosticsPanel extends StatelessWidget {
  const _GoogleMapDiagnosticsPanel({
    required this.mapInitialized,
    required this.cameraFollowEnabled,
    required this.currentZoom,
    required this.markerCount,
    required this.routingProvider,
  });

  final bool mapInitialized;
  final bool cameraFollowEnabled;
  final double currentZoom;
  final int markerCount;
  final String routingProvider;

  @override
  Widget build(BuildContext context) {
    final text = [
      'Google Maps debug',
      'map initialized: ${mapInitialized ? 'yes' : 'no'}',
      'markers: $markerCount',
      'camera follow: ${cameraFollowEnabled ? 'on' : 'paused'}',
      'zoom: ${currentZoom.toStringAsFixed(1)}',
      'routing provider: $routingProvider',
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
          maxLines: 4,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}
