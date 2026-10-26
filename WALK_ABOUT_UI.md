# Walk About UI

## Implemented

- Home has an optional request, duration, GPS starting point and Create my walk.
- Fine tune retains companions, pace, accessibility, route shape, environment and paid-attraction choices.
- Profile owns interests and default pace/accessibility/paid preferences. Native preferences migrate from temporary storage to application support storage.
- Route creation calls the existing API before showing preview. Preview uses returned geometry, stops, distance and duration. Start walking calls the existing start endpoint.
- Existing Explore, camera/AR, active-walk, narration and journey entry points remain. User-facing navigation uses Walk About and My walks; API/package identifiers stay unchanged.

## Deployment and Limitations

Deploy both API changes and Flutter changes. The API now accepts the request text and fine-tuning fields. Their use in AI stop selection requires the existing ROVER_STORY_LED_PLANNING_ENABLED flag and configured Google routing/Places providers. These fields guide selection; they are not hard guarantees of accessible paths, indoor availability, fees or route shape.

Starting point remains GPS-only, matching the existing location flow. Explore remains a fourth tab to preserve camera discovery. Try another returns to the request screen. Profile defaults apply when a fresh request draft is created; an existing edited draft is retained. Home does not add a new microphone workflow; existing active-walk voice controls remain.

## Verification

- API Release build: passed, no warnings or errors.
- API tests: 166 passed.
- Flutter full suite: 223 passed, one optional visual capture skipped.
- Flow tests cover 320- and 390-pixel widths, persisted interests, fine-tuning payload, create/start separation and generation failure.
- Optional visual capture: CAPTURE_WALK_ABOUT=1 flutter test test/walk_about_visual_test.dart.
- Captures are under rover_flutter/build/walk_about_screenshots. Preview capture uses an explicitly test-only API fixture; native maps cannot render in widget tests.
- Native Android build and emulator verification could not be completed: local Gradle exited without useful diagnostics and ADB encountered a home-directory permission failure. No new APK or live map/API result is claimed.
- Analyzer reported three style infos in unrelated existing files; no type errors. Those existing changes were left untouched.

The prototype's Munich route was not copied into production. Live device verification of map framing, GPS and deployed API preferences remains required.
