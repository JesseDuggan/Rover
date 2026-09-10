# ROVER Phase 11 Camera Explorer and AR Field Test Plan

## Scope

Phase 11A adds Camera Explorer: a live rear-camera view that overlays nearby Rover places, lets the user hear sourced location stories, and can add a selected place to the active walk. ARCore is represented by an abstraction layer, but the current field build uses the camera overlay fallback.

## Build Under Test

- Flutter app: `rover_flutter`
- Target device: Samsung Android handset
- API environment: Development
- Required permissions: foreground location and camera
- Required services: Rover middleware, Mapbox, OpenAI, ElevenLabs when configured

## Acceptance Criteria

- Camera Explorer opens from Active ROAM and Explore.
- The app requests camera permission when needed and does not crash if permission is denied.
- The camera preview is live and rear-facing.
- Rover does not continuously upload camera frames.
- Nearby labels appear only when Rover has device location, usable heading, and nearby candidates.
- Labels are directionally plausible when the phone is pointed toward known route stops or nearby POIs.
- Poor GPS, missing heading, or empty local context produces a polite recovery message.
- Hear Story and Tell Me More use the existing grounded Location Intelligence narration flow.
- Add to Walk works during an active server-backed ROAM.
- When no server-backed walk is active, Camera Explorer can seed a new walk request from the selected place.
- Existing Phase 10 route options, geofence diagnostics, voice, and active ROAM screens still work.

## Field Test Script

1. Start the Rover middleware and confirm `/health` is healthy.
2. Run `adb reverse tcp:5080 tcp:5080`.
3. Build and run the Flutter app on the Samsung device with `.env.local`.
4. Confirm camera and location permissions are granted.
5. Start a ROAM in Westport using live device location.
6. Open Active ROAM and tap Camera Explorer.
7. Point the phone slowly toward a known route stop.
8. Confirm the status pill reports GPS accuracy, heading, label count, AR fallback mode, and POI refresh.
9. Tap a label and confirm the place card opens.
10. Tap Hear Story and confirm audio plays or a clear safe error appears.
11. Tap Tell Me More and confirm it reuses the same narrated location story path.
12. Tap Add to Walk and confirm Active ROAM returns with the route updated.
13. Move more than 0.5 km and reopen or continue Camera Explorer.
14. Confirm the POI list refreshes and labels change for the new location.
15. Deny camera permission in Android settings and reopen Camera Explorer.
16. Confirm Rover shows a polite camera-unavailable message.

## Diagnostics To Capture

- Screenshot of Camera Explorer with visible labels.
- Screenshot of the selected place card.
- Performance panel after Hear Story.
- Performance panel after Add to Walk.
- `Field log:` entries for camera initialization, POI refresh, overlay refresh, voice, and geofence state.
- API diagnostics including request counts, slow operations, background queue counts, and last safe error code.

## Known Limitations

- ARCore/native spatial anchors are not enabled in this build.
- Visual object recognition is intentionally disabled until there is an explicit capture-and-consent flow.
- Heading can be unavailable while stationary; move the phone slowly or walk briefly to seed compass/GPS course.
- Overlay labels are GPS and heading based, so dense streets may still require user confirmation.
- Weather and third-party source failures should not block camera labels or narration, but should appear in diagnostics.

## Regression Areas

- Active ROAM geofence arrival narration.
- Route option button disabling and option counts.
- Premium voice startup and fallback speech.
- Map camera following, current-location indicator, and route orientation.
- Background task counts after journey narration and location warmup.
