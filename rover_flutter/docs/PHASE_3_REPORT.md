# Phase 3 Report

## Summary

Built Rover's local onboarding and personalization experience.

No real account authentication was added. Preferences are stored locally behind a repository interface so the storage mechanism can be replaced later without rewriting the onboarding UI.

## What Was Added

- `RoverPreferences` model for local personalization state.
- `PreferencesRepository` interface.
- `FilePreferencesRepository` for local JSON persistence.
- `MemoryPreferencesRepository` for unit and widget tests.
- `PreferencesController` and `PreferencesScope` for app-wide preference access.
- Multi-step onboarding flow with friendly Rover/Riley language.
- Continue as Guest path from Welcome.
- Preferences review screen in Profile settings.
- Edit preferences flow by returning to onboarding with saved values prefilled.
- Reset onboarding action.
- Unit tests for memory and file-backed repositories.
- Widget tests for onboarding, persistence after app restart, review, edit, reset, and existing route behavior.

## Collected Preferences

The onboarding flow supports:

- First name.
- Interests: history, food, architecture, nature, art, movies, current events, hidden gems.
- Preferred walking pace.
- Typical available time.
- Accessibility and mobility considerations.
- Content depth: quick highlights or deeper stories.
- Audio preference.
- Notification preference.
- Distance-unit preference.
- Language preference.

All questions can be skipped. Skipped values appear as `Skipped for now` on the review screen.

## Location Explanation

Onboarding explains that location access will eventually help ROVER estimate distance, travel time, and nearby stops. The app does not request location permission in this phase.

## Accessibility And Usability

- Form fields use labels and helper text.
- Choice groups are wrapped in semantic labels.
- Progress has a semantic label and step value.
- Buttons, chips, fields, and preference rows use Material touch-target sizing.
- Phone layout remains the priority with single-column scrolling screens.
- Larger screens remain usable through the existing responsive shell.

## Files Created Or Updated

- `lib/src/preferences/rover_preferences.dart`
- `lib/src/preferences/preferences_repository.dart`
- `lib/src/preferences/preferences_controller.dart`
- `lib/src/app.dart`
- `lib/src/routing/rover_router.dart`
- `lib/src/ui/placeholder_screens.dart`
- `test/preferences_repository_test.dart`
- `test/widget_test.dart`
- `docs/PHASE_3_REPORT.md`

## Verification

- `flutter pub get`: passed as part of direct Flutter tool verification.
- `dart --disable-dart-dev format lib test`: passed.
- `flutter analyze`: passed with `No issues found`.
- `flutter test --no-test-assets`: passed, `19` tests.

## Android Build Status

`flutter build apk --debug` remains blocked by the local Android/Gradle environment:

- Command used Android Studio's bundled JDK at `C:\Program Files\Android\Android Studio\jbr`.
- Command used a workspace-local `GRADLE_USER_HOME`.
- Gradle started, emitted Java native-access warnings, then exited with code `1`.
- No APK was produced.
- No Rover source or Android compilation error was emitted.

This matches the Gradle build blocker observed in Phase 2 and appears environment-level rather than app-code-level.

## Notes

`dart format .` is still not ideal in this sandbox because the workspace-local `.gradle` cache created while diagnosing Android builds contains Gradle documentation paths that the formatter tries to traverse. Source formatting was verified with `dart --disable-dart-dev format lib test`.

No map, AI, authentication, backend service, API key, token, password, or secret integration was added.
