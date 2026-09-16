import 'package:flutter/foundation.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rover/src/camera_explorer/camera_heading.dart';

void main() {
  test('Android uses sensor heading, not the unpopulated camera field', () {
    expect(
      cameraHeading(
        CompassEvent.fromList([-90, 0, 15]),
        TargetPlatform.android,
      ),
      270,
    );
    expect(
      cameraHeading(CompassEvent.fromList([90, 0, 15]), TargetPlatform.android),
      90,
    );
  });

  test('iOS uses back-of-device heading', () {
    expect(
      cameraHeading(CompassEvent.fromList([0, 180, 15]), TargetPlatform.iOS),
      180,
    );
    expect(
      cameraHeading(CompassEvent.fromList([0, -1, 15]), TargetPlatform.iOS),
      isNull,
    );
  });

  test('missing and non-finite sensor readings do not invent north', () {
    expect(
      cameraHeading(CompassEvent.fromList(null), TargetPlatform.android),
      isNull,
    );
    expect(
      cameraHeading(
        CompassEvent.fromList([double.nan, 0, 15]),
        TargetPlatform.android,
      ),
      isNull,
    );
    expect(
      cameraHeading(
        CompassEvent.fromList([double.infinity, 0, 15]),
        TargetPlatform.android,
      ),
      isNull,
    );
  });
}
