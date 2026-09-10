# Phase 4 Report - Adventure Request

Date: 2026-08-26

## Summary

Phase 4 builds Rover's primary adventure-request experience using only local
state and placeholder data. The Home destination now prominently asks "What do
you want to do?" and offers quick paths into a mock request builder. No AI,
maps, authentication, backend services, secrets, or API keys were added.

## Created and Updated

- `lib/src/adventure/adventure_request.dart`
  - Added the `AdventureRequest` model.
  - Added realistic-time and completeness validation.
  - Added `MockAdventureSuggestion` and `createMockSuggestions`.
- `lib/src/adventure/adventure_request_controller.dart`
  - Added an in-memory controller and inherited scope for the active request.
- `lib/src/app.dart`
  - Added `AdventureRequestScope` around the router app.
- `lib/src/ui/placeholder_screens.dart`
  - Reworked Home around the prompt "What do you want to do?"
  - Added quick actions for 30, 60, and 90 minutes, nearby, and Surprise me.
  - Built the adventure-request form.
  - Updated route preview to show request details and mock suggestions.
- `test/adventure_request_test.dart`
  - Added model and validation tests.
- `test/widget_test.dart`
  - Added request creation, editing, and validation widget coverage.

## Request Fields

The request builder currently collects:

- Natural-language request
- Available time
- Starting point
- Walking or accessible route
- Interests
- Desired pace
- Loop route or different destination
- Solo, couple, family, or group
- Indoor/outdoor preference
- Free-only or include paid attractions
- Surprise me

## Validation

The model rejects:

- Missing or non-realistic available time.
- Requests under 20 minutes.
- Requests over 6 hours.
- Missing starting point.
- Missing interests unless Surprise me is enabled.

The UI surfaces field-level validation for time and starting point, then shows a
friendly snack bar for request-level validation such as missing interests.

## Mock Suggestions

Route preview creates three placeholder suggestions from the saved request:

- Warm-up stop
- Main wander
- Soft landing

These are deterministic local mock suggestions and do not call AI, maps, or a
backend service.

## Verification

Commands completed:

- `flutter pub get`
- `dart --disable-dart-dev format lib test`
- `flutter analyze`
- `flutter test --no-test-assets`

Results:

- `flutter pub get`: passed.
- Formatting: passed.
- `flutter analyze`: passed with no issues.
- `flutter test --no-test-assets`: passed, 25 tests.

Android debug build status:

- Attempted `flutter build apk --debug`.
- Build did not produce `build/app/outputs/flutter-apk/app-debug.apk`.
- Flutter/Gradle reached Android configuration, then failed because the Android
  SDK manager did not install NDK `28.2.13676358`.
- Manual `sdkmanager` retry also failed inside the Android CLI embedded JRE with
  an access error while loading `java.security`.
- Retried `android.exe sdk install` directly with a workspace-local
  `ANDROID_USER_HOME`; it failed with the same Android CLI embedded JRE
  `java.security` access error.

## Definition of Done

- [x] A user can create a complete `AdventureRequest` model.
- [x] Input validation is clear and friendly.
- [x] Requests can be edited from route preview.
- [x] Tests cover request validation.
- [x] Phase 4 report created.
- [!] Android debug build remains blocked by local Android SDK/NDK installation
  failure, not by Rover Dart code.
