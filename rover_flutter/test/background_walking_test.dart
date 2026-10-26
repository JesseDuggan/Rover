import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:rover/src/location/rover_location.dart';
import 'package:rover/src/location/background_walk_policy.dart';

void main() {
  test('visible navigation is responsive and hidden navigation conserves battery', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    const provider = GeolocatorLocationProvider(backgroundWalking: true);
    final visible = provider.navigationSettings(mapVisible: true) as AndroidSettings;
    final hidden = provider.navigationSettings(mapVisible: false) as AndroidSettings;
    expect(visible.intervalDuration, const Duration(seconds: 1));
    expect(visible.distanceFilter, 1);
    expect(hidden.intervalDuration, const Duration(seconds: 10));
    expect(hidden.distanceFilter, 10);
    expect(hidden.foregroundNotificationConfig?.enableWakeLock, isFalse);
  });
  test('Android screen lock continues walking but engine detach stops it', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    expect(shouldPauseWalking(AppLifecycleState.inactive), isFalse);
    expect(shouldPauseWalking(AppLifecycleState.hidden), isFalse);
    expect(shouldPauseWalking(AppLifecycleState.paused), isFalse);
    expect(shouldPauseWalking(AppLifecycleState.detached), isTrue);
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    expect(shouldPauseWalking(AppLifecycleState.paused), isTrue);
  });
  test(
    'only walking opts into Android foreground service and CPU wakelock',
    () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final settings =
          const GeolocatorLocationProvider(backgroundWalking: true)
                  .streamSettings
              as AndroidSettings;
      expect(settings.foregroundNotificationConfig?.enableWakeLock, isTrue);
      expect(settings.foregroundNotificationConfig?.setOngoing, isTrue);
      expect(settings.intervalDuration, const Duration(seconds: 5));
      expect(
        const GeolocatorLocationProvider().streamSettings,
        isNot(isA<AndroidSettings>()),
      );
    },
  );

  test('unsupported platforms do not advertise Android background service', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    expect(
      const GeolocatorLocationProvider(backgroundWalking: true).streamSettings,
      isNot(isA<AndroidSettings>()),
    );
  });
}
