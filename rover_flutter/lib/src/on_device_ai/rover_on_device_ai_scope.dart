import 'package:flutter/widgets.dart';

import 'rover_on_device_ai_coordinator.dart';

class RoverOnDeviceAiScope extends InheritedWidget {
  const RoverOnDeviceAiScope({
    required this.coordinator,
    required super.child,
    super.key,
  });

  final RoverOnDeviceAiCoordinator coordinator;

  static RoverOnDeviceAiCoordinator of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<RoverOnDeviceAiScope>();
    assert(scope != null, 'No RoverOnDeviceAiScope found in context.');
    return scope!.coordinator;
  }

  static RoverOnDeviceAiCoordinator? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<RoverOnDeviceAiScope>()
        ?.coordinator;
  }

  @override
  bool updateShouldNotify(RoverOnDeviceAiScope oldWidget) {
    return coordinator != oldWidget.coordinator;
  }
}
