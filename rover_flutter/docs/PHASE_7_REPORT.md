# Phase 7 Report - Active ROAM

Date: 2026-08-26

## Summary

Phase 7 adds a persistent Active ROAM experience with local state, simulated
arrival detection, screen-awake handling, audio controls, walking-safety
messaging, and a developer demo mode for the San Francisco route. The feature
does not require backend services or real movement.

## Created and Updated

- `lib/src/active_roam/active_roam_session.dart`
  - Added `RoamSession`, `RoamSessionStatus`, and `AudioPlaybackStatus`.
  - Tracks current stop, next stop, completed/skipped stops, simulated
    location, progress, audio state, and screen-awake state.
  - Serializes session progress for restart recovery.
- `lib/src/active_roam/active_roam_repository.dart`
  - Added file and memory repositories for Active ROAM progress.
- `lib/src/active_roam/screen_awake_controller.dart`
  - Added screen-awake abstraction.
  - Uses `wakelock_plus` in the app and an in-memory implementation in tests.
- `lib/src/active_roam/active_roam_controller.dart`
  - Added start, pause, resume, end, complete stop, skip stop, reroute
    placeholder, simulated advance, auto demo, arrival detection, and audio
    actions.
- `lib/src/adventure/roam.dart`
  - Added San Francisco Active ROAM demo route:
    - Union Square
    - Lotta's Fountain
    - Dragon Gate
    - Jackson Square brick lanes
    - Coit Tower
- `lib/src/app.dart`
  - Loads Active ROAM progress on startup and provides `ActiveRoamScope`.
- `lib/src/ui/placeholder_screens.dart`
  - Replaced the Active ROAM placeholder with a working navigation surface.
  - Shows live mock map, progress, current stop, Next Up, distance/time to next
    stop, full stop details, audio controls, and safety messaging.
- `test/active_roam_test.dart`
  - Added start/pause/resume/end, arrival detection, stop completion, skip,
    persistence, ordering, and auto-demo tests.
- `integration_test/active_roam_flow_test.dart`
  - Added an integration test that starts and completes a mock Active ROAM.

## Demo Behavior

The developer demo mode starts the ordered San Francisco route at Union Square
and can advance without physical movement. It demonstrates:

- Union Square as the first current stop.
- Nearby current-events and history content.
- Movie and pop-culture content at Dragon Gate.
- Coit Tower as a later "Next Up" example.
- Sequential route stops generated from ordered ROAM data.

The `Run auto demo` control completes the simulated route end-to-end. Manual
controls remain available for step-by-step demos.

## Recovery

Active progress is stored behind `ActiveRoamRepository`. The default app uses a
small local file repository, while tests use `MemoryActiveRoamRepository`.
Restart recovery is covered by widget and unit tests.

## Verification

Commands completed:

- `flutter pub add wakelock_plus`
- `flutter pub get`
- `dart --disable-dart-dev format lib test integration_test`
- `flutter analyze`
- `flutter test --no-test-assets`
- `flutter test integration_test/active_roam_flow_test.dart --no-test-assets`
- `flutter build apk --debug --no-pub`

Results:

- Package resolution: passed.
- Formatting: passed.
- `flutter analyze`: passed with no issues.
- `flutter test --no-test-assets`: passed, 45 tests.
- Credential scan: no tokens, API keys, passwords, or secrets found.
- Integration test file exists and covers starting/completing a mock ROAM.
- Integration test execution is blocked locally because `adb.exe` exits while
  trying to create `\.android`.

Android build status:

- `build/app/outputs/flutter-apk/app-debug.apk` was regenerated at
  2026-08-26 4:40:55 PM.
- `flutter build apk --debug --no-pub` still returns exit code 1 in the local
  Gradle/JBR environment.
- Because the command exit code is nonzero, the Android build requirement is
  not marked complete.

## Definition of Done

- [x] A complete simulated ROAM can be demonstrated.
- [x] Progress survives an app restart.
- [x] Arrival and completion logic has tests.
- [x] Critical controls are accessible and covered by widget tests.
- [x] Integration test covers starting and completing a mock ROAM.
- [!] Integration test execution is blocked by local `adb` configuration.
- [!] Android debug build artifact is generated, but the command still exits
  nonzero in the local Gradle/JBR environment.
- [x] Phase 7 report created.
