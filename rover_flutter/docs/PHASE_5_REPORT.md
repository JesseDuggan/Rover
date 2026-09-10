# Phase 5 Report - Location and Maps

Date: 2026-08-26

## Summary

Phase 5 adds foreground device location, map rendering, mock map fallback, and a
developer location simulator. The feature stays local and token-safe: no map
token, API key, password, or backend credential is committed.

## Packages

Added maintained Flutter packages resolved by the installed Flutter/Dart
toolchain:

- `geolocator` for foreground device location.
- `flutter_map` for map rendering.
- `latlong2` for coordinate values used by the map.

## Created and Updated

- `lib/src/location/rover_location.dart`
  - Added `RoverLocationProvider`.
  - Added `GeolocatorLocationProvider`.
  - Added `SimulatedLocationProvider`.
  - Added location result and failure models.
- `lib/src/location/location_controller.dart`
  - Added shared location controller and inherited scope.
  - Real and simulated locations flow through the same provider interface.
- `lib/src/maps/rover_map_provider.dart`
  - Added runtime map configuration using Dart environment defines.
  - Reads `ROVER_MAP_TILE_URL_TEMPLATE` and `ROVER_MAP_ACCESS_TOKEN`.
  - Uses mock-map mode when no usable token-backed tile config is available.
- `lib/src/maps/rover_map_view.dart`
  - Added reusable map view with current-location marker, mock-stop markers,
    route polyline, and mock backdrop.
- `lib/src/app.dart`
  - Added `LocationScope` around the app router.
- `lib/src/ui/placeholder_screens.dart`
  - Added manual/device/simulated starting-location controls.
  - Added explanation dialog before real OS foreground permission request.
  - Added map preview with mock Rover stops.
- `android/app/src/main/AndroidManifest.xml`
  - Added foreground-only coarse/fine location permissions.
- `ios/Runner/Info.plist`
  - Added `NSLocationWhenInUseUsageDescription`.
- `test/location_test.dart`
  - Added provider, controller, failure-recovery, and map-config tests.
- `test/widget_test.dart`
  - Added simulator-to-map widget coverage.

## Environment Configuration

No map credentials are stored in source. Runtime map configuration can be passed
with Dart defines:

```sh
flutter run \
  --dart-define=ROVER_MAP_TILE_URL_TEMPLATE="https://example.com/{z}/{x}/{y}?token={accessToken}" \
  --dart-define=ROVER_MAP_ACCESS_TOKEN="$ROVER_MAP_ACCESS_TOKEN"
```

If either no tile template is supplied, or the template requires
`{accessToken}` and no token is supplied, Rover displays functional mock-map
mode.

## Permission Behavior

ROVER does not request background location. Device foreground location is only
requested after the user taps "Use device location" and sees a benefit
explanation.

Failure states include recovery instructions for:

- Disabled Location Services.
- Denied foreground permission.
- Permanently denied foreground permission.
- Unknown location read failure.

The user can always type or edit the starting point manually.

## Developer Simulator

The developer simulator uses `SimulatedLocationProvider`, which implements the
same `RoverLocationProvider` interface as real device location. The request
screen exposes:

- `Use simulator`
- `Step simulator`

This allows demos without physically walking or granting OS location permission.

## Verification

Commands completed:

- `flutter pub add geolocator flutter_map latlong2`
- `dart --disable-dart-dev format lib test`
- `flutter analyze`
- `flutter test --no-test-assets`
- `flutter build apk --debug`

Results:

- Package resolution: passed.
- Formatting: passed.
- `flutter analyze`: passed with no issues.
- `flutter test --no-test-assets`: passed, 30 tests.
- Credential scan: no tokens, API keys, passwords, or secrets found.

Android build status:

- NDK `28.2.13676358` is now installed under the Android SDK.
- `build/app/outputs/flutter-apk/app-debug.apk` exists and was generated.
- Gradle daemon logs report a successful build result.
- The `flutter build apk --debug` process still returns exit code 1 in this
  local environment. Direct Gradle invocation from `cmd.exe` also returns 1.
- The visible daemon issue occurs after build completion during Gradle/JDK
  shutdown/registry cleanup, not as a Dart compile error.

## Definition of Done

- [x] Real and simulated location implementations use the same interface.
- [x] Permission failures have useful recovery instructions.
- [x] No credentials are committed.
- [x] Location logic has tests.
- [!] Android APK is generated, but the build command exits nonzero in the local
  Gradle/JDK environment.
- [x] Phase 5 report created.
