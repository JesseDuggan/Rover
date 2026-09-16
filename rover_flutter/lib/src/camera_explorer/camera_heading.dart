import 'package:flutter/foundation.dart';
import 'package:flutter_compass/flutter_compass.dart';

double? cameraHeading(CompassEvent event, TargetPlatform platform) {
  // Android already remaps heading for an upright phone; its camera field is 0.
  final value = platform == TargetPlatform.iOS
      ? event.headingForCameraMode
      : event.heading;
  if (value == null ||
      !value.isFinite ||
      (platform == TargetPlatform.iOS && value < 0)) {
    return null;
  }
  return value % 360;
}
