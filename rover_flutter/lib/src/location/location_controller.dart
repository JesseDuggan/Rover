import 'package:flutter/widgets.dart';

import 'rover_location.dart';

class LocationController extends ChangeNotifier {
  LocationController({
    RoverLocationProvider? realProvider,
    SimulatedLocationProvider? simulatedProvider,
  }) : _realProvider = realProvider ?? const GeolocatorLocationProvider(),
       _simulatedProvider = simulatedProvider ?? SimulatedLocationProvider();

  final RoverLocationProvider _realProvider;
  final SimulatedLocationProvider _simulatedProvider;

  bool _useSimulator = false;
  RoverLatLng? _location;
  LocationFailure? _failure;
  bool _isLoading = false;
  Future<RoverLocationResult>? _deviceLocationRequest;

  bool get useSimulator => _useSimulator;
  bool get isLoading => _isLoading;
  RoverLatLng? get location => _location;
  LocationFailure? get failure => _failure;
  RoverLocationProvider get activeProvider =>
      _useSimulator ? _simulatedProvider : _realProvider;

  Future<RoverLocationResult> locate() async {
    _isLoading = true;
    _failure = null;
    notifyListeners();

    final result = await activeProvider.getCurrentLocation();
    _location = result.location;
    _failure = result.failure;
    _isLoading = false;
    notifyListeners();
    return result;
  }

  Future<RoverLocationResult> useRealDeviceLocation() async {
    _useSimulator = false;
    return locate();
  }

  Future<RoverLocationResult> ensureDeviceLocation({
    bool forceRefresh = false,
  }) {
    _useSimulator = false;
    if (!forceRefresh && _location != null) {
      return Future.value(RoverLocationResult.success(_location!));
    }

    final pending = _deviceLocationRequest;
    if (pending != null) {
      return pending;
    }

    final request = locate();
    _deviceLocationRequest = request;
    return request.whenComplete(() {
      if (identical(_deviceLocationRequest, request)) {
        _deviceLocationRequest = null;
      }
    });
  }

  Future<RoverLocationResult> useSimulatedLocation() async {
    _useSimulator = true;
    return locate();
  }

  Future<RoverLocationResult> advanceSimulation() async {
    _useSimulator = true;
    _simulatedProvider.moveNext();
    return locate();
  }

  void resetSimulation() {
    _simulatedProvider.reset();
    _location = null;
    _failure = null;
    _useSimulator = false;
    notifyListeners();
  }
}

class LocationScope extends InheritedNotifier<LocationController> {
  const LocationScope({
    required LocationController controller,
    required super.child,
    super.key,
  }) : super(notifier: controller);

  static LocationController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<LocationScope>();
    assert(scope != null, 'No LocationScope found in context.');
    return scope!.notifier!;
  }
}
