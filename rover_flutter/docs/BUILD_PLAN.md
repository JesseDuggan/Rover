# ROVER Flutter Build Plan

## Phase 0 - Fresh Flutter Foundation

Status: Implementation complete; verification partially blocked by local environment policy

Goals:
- Verify installed Flutter and Dart toolchain.
- Confirm `SRC/rover_flutter` is clean before project generation.
- Create project governance docs.
- Generate a new Flutter app named `rover` with organization `ai.myrover`.
- Generate Android and iOS platforms using Flutter's current project structure.
- Build a simple branded startup screen.
- Verify dependencies, formatting, analysis, tests, and Android debug build.

Non-goals:
- No legacy project migration or repair.
- No map services.
- No AI services.
- No authentication.
- No backend integrations.
- No hardcoded secrets.

## Phase 0 Verification Checklist

- [x] Run `flutter --version`.
- [x] Run `flutter doctor`.
- [x] Confirm working directory.
- [x] Confirm `SRC/rover_flutter` did not contain another project.
- [x] Create `AGENTS.md`.
- [x] Create `docs/BUILD_PLAN.md`.
- [x] Generate Flutter project.
- [x] Implement ROVER startup screen.
- [x] Run `flutter pub get`.
- [x] Run `dart format .`.
- [x] Run `flutter analyze`.
- [!] Run `flutter test` - blocked by Windows Application Control policy for Flutter SDK executables.
- [!] Run Android debug build - blocked by local Android/JDK/Gradle environment.
- [x] Document Phase 0 in `docs/PHASE_0_REPORT.md`.

## Phase 2 - Navigation and Responsive Shell

Status: Complete

Goals:
- Add maintained declarative routing with Android back support.
- Create primary destinations: Home, Explore, My ROAMs, Profile.
- Add routes for welcome, onboarding, home, adventure request, route preview,
  active ROAM, stop details, saved ROAMs, and profile/settings.
- Preserve navigation state between primary destinations.
- Provide friendly not-found and error screens.

Verification:
- [x] Every route is covered by widget tests.
- [x] Android back navigation is covered by widget tests.
- [x] Navigation state preservation is covered by widget tests.
- [x] `flutter analyze` passed.
- [x] `flutter test --no-test-assets` passed.
- [!] Android debug build remains blocked by local Android SDK/NDK setup.

## Phase 3 - Onboarding and Personalization

Status: Complete

Goals:
- Add guest onboarding without real authentication.
- Store preferences locally behind a repository interface.
- Collect first name, interests, pace, time, accessibility, content depth,
  audio, notifications, units, and language.
- Explain future location need.
- Support preference review/edit and onboarding reset.

Verification:
- [x] Onboarding flow is covered by widget tests.
- [x] Local preference persistence is covered by unit and widget tests.
- [x] Reset onboarding is covered by widget tests.
- [x] `flutter analyze` passed.
- [x] `flutter test --no-test-assets` passed.
- [!] Android debug build remains blocked by local Android SDK/NDK setup.

## Phase 4 - Adventure Request

Status: Complete; Android debug build blocked by local SDK toolchain

Goals:
- Make Home center the experience around "What do you want to do?"
- Add quick actions for 30, 60, and 90 minutes, nearby, and Surprise me.
- Capture a complete mock `AdventureRequest` without AI, maps, auth, or backend
  services.
- Validate realistic available time and required request details with friendly
  language.
- Let users edit the current request and preview mock suggestions.

Verification:
- [x] `flutter pub get` passed.
- [x] `dart --disable-dart-dev format lib test` completed.
- [x] `flutter analyze` passed.
- [x] `flutter test --no-test-assets` passed.
- [!] Android debug build blocked because Android SDK Manager/Android CLI could
  not install NDK `28.2.13676358`.
- [x] Document Phase 4 in `docs/PHASE_4_REPORT.md`.

## Phase 5 - Device Location and Maps

Status: Implementation complete; Android APK generated with nonzero Gradle
process exit in local JDK/Gradle environment

Goals:
- Add location provider abstractions for real foreground device location and a
  developer simulator.
- Add map provider abstraction that reads runtime tile/token configuration from
  Dart environment defines.
- Keep a functional mock-map mode when no token or tile URL is supplied.
- Explain the benefit before requesting OS foreground location permission.
- Handle disabled services, denied permission, permanently denied permission,
  and unknown location failures with recovery guidance.
- Display current or simulated location and mock Rover stop markers.
- Allow the starting point to remain manually editable.

Verification:
- [x] `flutter pub get` passed.
- [x] `dart --disable-dart-dev format lib test` completed.
- [x] `flutter analyze` passed.
- [x] `flutter test --no-test-assets` passed.
- [x] Location logic has unit tests.
- [x] No credentials found in source scan.
- [!] `flutter build apk --debug` produced
  `build/app/outputs/flutter-apk/app-debug.apk`, but the Gradle process returned
  exit code 1 after daemon logs reported a successful build result.
- [x] Document Phase 5 in `docs/PHASE_5_REPORT.md`.

## Phase 6 - Route Preview and Itinerary

Status: Implementation complete; Android debug build command still exits
nonzero in local JDK/Gradle environment

Goals:
- Add mock route-generation service with realistic ROAM sample data.
- Model generated ROAMs with title, summary, time totals, distance, starting
  point, ordered stops, geometry, accessibility notes, and warnings.
- Model stops with generated sequence number, name, image reference,
  description, visit time, coordinates, category, optional audio, and selection
  rationale.
- Generate marker numbering from ordered itinerary data, never from static map
  imagery.
- Support refresh, regenerate, remove, reorder, and replace stop actions.
- Recalculate time and distance after itinerary edits.

Verification:
- [x] Ordered-stop logic has unit tests.
- [x] Time-budget calculation has boundary tests.
- [x] Reordering cannot produce duplicate numbers.
- [x] Route preview works without a backend.
- [x] `dart --disable-dart-dev format lib test` completed.
- [x] `flutter analyze` passed.
- [x] `flutter test --no-test-assets` passed.
- [!] `flutter build apk --debug --no-pub` still returns exit code 1 in the
  local Gradle/JDK environment.
- [x] Document Phase 6 in `docs/PHASE_6_REPORT.md`.

## Phase 7 - Active ROAM

Status: Implementation complete; Android debug build artifact regenerates but
the command still exits nonzero in local JDK/Gradle environment

Goals:
- Add persistent Active ROAM session state.
- Support start, pause, resume, end, stop completion, skip, reroute placeholder,
  audio play/pause/replay, screen-awake handling, and walking-safety messaging.
- Show live mock map, route progress, current stop, Next Up, distance, and
  estimated time to next stop.
- Add simulated arrival detection.
- Add developer demo mode that advances through the San Francisco route without
  real movement.
- Demonstrate Union Square, nearby history/current events, movie/pop-culture
  content, Coit Tower as Next Up, and correctly ordered stops.

Verification:
- [x] Active ROAM logic has unit tests.
- [x] Arrival and completion logic has tests.
- [x] Progress survives an app restart via repository-backed session state.
- [x] Critical controls are covered by widget tests.
- [x] Integration test file covers starting and completing a mock ROAM.
- [!] Integration test execution is blocked by local `adb` failing to create
  `\.android`.
- [x] `dart --disable-dart-dev format lib test integration_test` completed.
- [x] `flutter analyze` passed.
- [x] `flutter test --no-test-assets` passed.
- [!] `flutter build apk --debug --no-pub` regenerated the debug APK artifact
  but still returned exit code 1 in the local Gradle/JDK environment.
- [x] Document Phase 7 in `docs/PHASE_7_REPORT.md`.
