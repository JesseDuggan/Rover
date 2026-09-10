# Phase 9 Field Test Plan

Use this plan for Rover private-beta walks. Record pass/fail, notes, and severity for every scenario.

Severity levels:

- Critical: safety, security, privacy, data exposure, or complete inability to walk.
- High: route, arrival, login, recovery, or audio feature unusable.
- Medium: feature works but is confusing or unreliable.
- Low: visual polish, wording, or minor inconvenience.

Defect template:

- Build number:
- Device:
- Scenario:
- Reproduction steps:
- Expected result:
- Actual result:
- Frequency:
- Severity:
- Screenshot/log reference:
- Resolution status:

## Scenarios

### Sunny Outdoor Conditions
- Setup: Samsung RFGYA0RB5HY, Rover API reachable, location allowed while using app.
- Steps: Create a 30-minute walk, start it, walk to the first stop.
- Expected result: Map, route, voice, and arrival detection work normally.
- Pass/fail:
- Notes:
- Issue severity:

### Dense Buildings
- Setup: Stand near tall buildings with precise location enabled.
- Steps: Start an active walk and watch GPS accuracy and arrival candidate state.
- Expected result: Rover ignores noisy jumps and offers manual "I'm Here" only near the stop.
- Pass/fail:
- Notes:
- Issue severity:

### Poor GPS Accuracy
- Setup: Use an area where GPS accuracy is degraded.
- Steps: Approach a stop slowly and wait near the visible geofence.
- Expected result: Arrival waits for qualifying readings and does not false-arrive outside the geofence.
- Pass/fail:
- Notes:
- Issue severity:

### Weak Cellular Connection
- Setup: Reduce connectivity or move to weak coverage.
- Steps: Open current walk, ask Rover, submit a problem report.
- Expected result: Current walk remains visible; new route generation explains connectivity need; problem report queues if API is unreachable.
- Pass/fail:
- Notes:
- Issue severity:

### Screen Locked
- Setup: Start an active walk.
- Steps: Lock the screen for two minutes, unlock Rover.
- Expected result: Rover resumes the same walk and never resumes the wrong walk.
- Pass/fail:
- Notes:
- Issue severity:

### Bluetooth Headphones
- Setup: Pair Bluetooth headphones.
- Steps: Play stop narration, trigger Ask Rover, then navigation direction.
- Expected result: Audio priority is navigation, microphone, Ask Rover, narration.
- Pass/fail:
- Notes:
- Issue severity:

### Phone Call Interruption
- Setup: Start narration, then receive or simulate a phone call.
- Steps: End the call and return to Rover.
- Expected result: Rover does not overlap audio or restart long narration unexpectedly.
- Pass/fail:
- Notes:
- Issue severity:

### Wrong Turn
- Setup: Start a route.
- Steps: Walk away from the next maneuver.
- Expected result: Rover detects off-route after thresholds and avoids recalculation loops.
- Pass/fail:
- Notes:
- Issue severity:

### Walk Away From Route
- Setup: Active walk with route visible.
- Steps: Move more than the off-route threshold away from the route.
- Expected result: Rover tells the tester clearly and keeps the current walk recoverable.
- Pass/fail:
- Notes:
- Issue severity:

### Skip Stop
- Setup: Active walk with multiple stops.
- Steps: Use discovery/detour controls or manual flow to move past a stop when supported.
- Expected result: Rover never marks multiple stops from one reading and preserves visited stops.
- Pass/fail:
- Notes:
- Issue severity:

### Manual "I'm Here"
- Setup: Stand close to the next stop with poor GPS.
- Steps: Tap "I'm Here."
- Expected result: Arrival succeeds only when reasonably close to the next ordered stop.
- Pass/fail:
- Notes:
- Issue severity:

### Ask Rover During Narration
- Setup: Play stop narration.
- Steps: Ask Rover a typed or microphone question.
- Expected result: Narration pauses/stops, answer appears, spoken answer plays without overlap.
- Pass/fail:
- Notes:
- Issue severity:

### ElevenLabs Unavailable
- Setup: Run API with ElevenLabs disabled.
- Steps: Trigger stop narration and Ask Rover answer.
- Expected result: Device TTS fallback is used and the app remains usable.
- Pass/fail:
- Notes:
- Issue severity:

### Middleware Restarted
- Setup: Active walk on phone.
- Steps: Restart Rover.Api and return to the app.
- Expected result: App shows recoverable state and does not discard server history.
- Pass/fail:
- Notes:
- Issue severity:

### App Terminated And Reopened
- Setup: Active walk.
- Steps: Force close Rover, reopen it.
- Expected result: Rover offers resume/end and never resumes the wrong walk silently.
- Pass/fail:
- Notes:
- Issue severity:

### Low Battery
- Setup: Enable battery saver if available.
- Steps: Start walk and monitor tracking, map, and voice.
- Expected result: Rover remains battery-conscious without weakening arrival accuracy.
- Pass/fail:
- Notes:
- Issue severity:

### Accessibility Preference
- Setup: Select step-free preferred or avoid-stairs preferences.
- Steps: Create a walk and inspect route language.
- Expected result: Rover uses "step-free preferred" unless route data can prove accessibility.
- Pass/fail:
- Notes:
- Issue severity:

### Guest User
- Setup: Continue as guest.
- Steps: Complete a walk, restart app, inspect history and feedback.
- Expected result: Guest history remains on device and feedback submits with privacy-safe context.
- Pass/fail:
- Notes:
- Issue severity:

### Authenticated User
- Setup: Use configured beta auth when available.
- Steps: Sign in, create walk, complete it, restart app.
- Expected result: Account history and profile preferences remain isolated to that user.
- Pass/fail:
- Notes:
- Issue severity:

### Second-Device Sign-In
- Setup: Sign in on another device when beta auth is configured.
- Steps: Inspect active/recovered walk state.
- Expected result: Rover does not unknowingly resume a stale or wrong walk.
- Pass/fail:
- Notes:
- Issue severity:

## Private-Beta Distribution Notes

- Release application ID: confirm in Android Gradle before Play internal testing.
- Versioning: use `version` in `pubspec.yaml`, plus `--build-name` and `--build-number` for release builds.
- Android App Bundle: `flutter build appbundle --release --build-name 1.0.0-beta --build-number 9`.
- Release signing: configure local signing outside source control using Android Studio or Gradle properties.
- Signing-key storage: keep keystores out of the repo; store recovery material in a password manager.
- Google Play internal testing: create an internal-testing release, upload the AAB, add tester emails, and submit for internal review.
- Installing beta: testers install from the Play internal-testing opt-in link.
- Updating beta: increment build number and upload a new AAB.
- Rollback: promote the previous stable internal-testing build if a regression blocks field testing.
- Feedback: collect in-app problem reports, post-walk feedback, and this plan's defect template.
- Samsung debug install remains available with `flutter run -d RFGYA0RB5HY`.
