import 'package:flutter/widgets.dart';

import 'rover_location.dart';

class LocationController extends ChangeNotifier {
  LocationController({RoverLocationProvider? realProvider})
    : _realProvider = realProvider ?? const GeolocatorLocationProvider();

  final RoverLocationProvider _realProvider;

  RoverLatLng? _location;
  LocationFailure? _failure;
  bool _isLoading = false;
  Future<RoverLocationResult>? _deviceLocationRequest;

  bool get isLoading => _isLoading;
  RoverLatLng? get location => _location;
  LocationFailure? get failure => _failure;
  RoverLocationProvider get activeProvider => _realProvider;

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
    return locate();
  }

  Future<RoverLocationResult> ensureDeviceLocation({
    bool forceRefresh = false,
  }) {
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
