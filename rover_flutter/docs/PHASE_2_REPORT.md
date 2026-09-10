# Phase 2 Report

## Summary

Implemented Rover's responsive navigation shell and declarative routing foundation.

The app now uses `go_router` `18.0.0`, a maintained Flutter-team declarative routing package built on Flutter's Router API. Navigation is URL-based, compatible with Android back handling, and structured around state-preserving primary destinations.

## Primary Destinations

The app shell has four primary destinations:

- Home
- Explore
- My ROAMs
- Profile

Phone layouts use `NavigationBar`. Wider layouts switch to `NavigationRail` at `720` logical pixels while keeping the same destination model.

## Routes

Implemented routes:

- `/welcome` - Welcome
- `/onboarding` - Onboarding
- `/home` - Home
- `/home/adventure-request` - Adventure request
- `/home/route-preview` - Route preview
- `/home/active-roam` - Active ROAM
- `/home/stop-details` - Stop details
- `/roams` - Saved ROAMs / My ROAMs
- `/profile` - Profile
- `/profile/settings` - Settings

## Navigation Behavior

- Primary destination state is preserved with `StatefulShellRoute.indexedStack`.
- Nested Home routes remain on their branch stack when switching between primary destinations.
- Android-style back navigation is handled by Flutter's Router API through `go_router`.
- Detail pages use normal app bars, so platform back affordances are available.
- Unknown paths render a friendly not-found screen.
- Unexpected routing failures render a friendly generic error screen.

## Placeholder Data

All content uses static placeholder data only:

- Sample route stops.
- Sample saved ROAM.
- Guest profile placeholder.
- Local settings placeholder.

No map, AI, authentication, backend, analytics, API key, token, password, or secret integration was added.

## Files Created Or Updated

- `pubspec.yaml`: added `go_router`.
- `pubspec.lock`: resolved `go_router` and transitive dependencies.
- `lib/main.dart`: app entry point.
- `lib/src/app.dart`: Material 3 app shell and router config.
- `lib/src/routing/rover_router.dart`: declarative route table and stateful shell route.
- `lib/src/shell/rover_shell.dart`: responsive primary navigation shell.
- `lib/src/ui/placeholder_screens.dart`: placeholder route screens, not-found screen, error screen, and shared UI helpers.
- `test/widget_test.dart`: route reachability, shell navigation, branch state, not-found, and Android-style back tests.
- `docs/PHASE_2_REPORT.md`: this report.

## Verification Results

- `flutter pub add go_router:^18.0.0`: passed.
- `dart format lib test`: passed.
- `flutter analyze`: passed with `No issues found`.

## Blocked Verification

`flutter test --no-test-assets` remains blocked by Windows Application Control before any Rover test logic executes:

- Blocked executable: `C:\src\flutter\bin\cache\dart-sdk\bin\dartaotruntime.exe`.
- Error: `An Application Control policy has blocked this file`.

`flutter build apk --debug` remains blocked by local Android/Gradle environment behavior:

- With no Java environment, Gradle fails because `JAVA_HOME` is not set.
- With `JAVA_HOME` set to `C:\Program Files\Android\Android Studio\jbr`, Gradle starts but exits with code `1` without producing an APK or a project-level compilation error.
- `flutter doctor` previously reported Android license status unknown, so `flutter doctor --android-licenses` should be completed from a normal user shell.

`dart format .` is currently not reliable in this sandbox because a workspace-local Gradle cache created during Android build diagnosis contains Gradle documentation paths that Dart's formatter tries to traverse. Source formatting was verified with `dart format lib test`.

## Definition Of Done Status

Complete:

- Every requested route is implemented.
- Every route is reachable from app navigation or direct route rendering.
- Android back behavior is covered by widget tests.
- Primary destination state is preserved by the shell route.
- Friendly not-found and error screens exist.
- Placeholder data only.
- Phone-first layout with larger-screen usability.
- `flutter analyze` passes.
- Navigation widget tests are written.

Blocked by local environment:

- `flutter test` execution.
- Android debug build.
- Runtime Android start verification.

## Recommended Next Actions

1. Allow Flutter SDK executables blocked by Windows Application Control, especially `dartaotruntime.exe`.
2. Run `flutter doctor --android-licenses` and accept Android SDK licenses if appropriate.
3. Configure a supported Android build JDK in the normal user environment.
4. Rerun `flutter test --no-test-assets` and `flutter build apk --debug`.
