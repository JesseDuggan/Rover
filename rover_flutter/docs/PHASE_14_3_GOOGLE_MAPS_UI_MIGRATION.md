# ROVER Phase 14.3 - Google Maps UI Migration

**Implemented:** 2026-09-02  
**Status:** Flutter implementation complete; physical-device field validation pending

## Outcome

Google Maps is now ROVER's preferred Flutter map renderer. The migration preserves the current Active ROAM and route-preview contracts while aligning the visible map with the Google Places provider introduced in the middleware.

The existing Mapbox renderer remains available as a temporary field-comparison fallback. It should be removed after Google map and routing validation is complete.

## Implemented behavior

- Google Maps SDK for Flutter renderer on route preview, Active ROAM, and expanded-map views.
- Native blue location dot when foreground location is available.
- Camera following centered on the current location.
- Camera bearing from device heading, movement, route geometry, or the current stop.
- User pan, rotate, tilt, and zoom gestures pause automatic following.
- A recenter control resumes location and direction following.
- Route polyline rendering.
- Stop markers with sequence in their information title, visit state, and stop details.
- Arrival geofence circles using each stop's configured radius.
- Completed, current, future, and sponsored marker states.
- Google legal notices entry under Profile.
- Existing development renderer and Mapbox fallback remain operational.

## Configuration

Add these values to `.env.local`:

```text
GOOGLE_MAPS_ANDROID_API_KEY=<android-restricted-key>
ROVER_MAP_PROVIDER=google
```

The Gradle build decodes Flutter's `dart-defines` and injects only `GOOGLE_MAPS_ANDROID_API_KEY` into the Android manifest placeholder required by Maps SDK for Android.

Use a separate Google Cloud key from `GOOGLE_PLACES_API_KEY`. Restrict the mobile key to:

- Maps SDK for Android.
- Android package `ai.myrover.rover`.
- Debug and release signing-certificate SHA fingerprints as applicable.

## Provider selection

Provider selection is deterministic:

1. Google is selected when `ROVER_MAP_PROVIDER=google` and its key is present.
2. A valid Mapbox public token is used temporarily when Google is selected but not configured.
3. The development renderer is used when neither live renderer is configured.
4. `ROVER_MAP_PROVIDER=mapbox` explicitly selects the migration fallback.
5. `ROVER_MAP_PROVIDER=development` explicitly selects the local development renderer.

## Current boundary

This package replaces the Flutter map UI only. Route geometry and local discovery can still be supplied by Mapbox middleware adapters. Their migration to Google Routes and Google Places is a separate server-side step and should be completed before Mapbox credentials and code are removed.

Google Places remains disabled by default until every consuming Camera and place-detail surface displays required Google attribution and storage behavior has been reviewed.

## Field validation

On the physical Samsung device:

1. Confirm the route-preview map is Google Maps and includes Google's built-in attribution.
2. Start a ROAM and confirm the blue location dot appears.
3. Move at least 100 metres and confirm the camera follows location and direction of travel.
4. Pan the map and confirm following pauses and a recenter control appears.
5. Tap recenter and confirm following resumes.
6. Confirm route line, all stops, and geofence circles render.
7. Tap several stop markers and confirm the correct stop details open.
8. Complete a stop and confirm its visual state updates without losing the route.
9. Expand and close the map and confirm both views remain responsive.
10. Open Profile > Legal notices and confirm the licenses page opens.

## Next migration package

- Add a Google Routes middleware adapter for walking route geometry and duration.
- Complete Google Places attribution in Camera Explorer and place details.
- Enable Google Places for field testing.
- Replace Mapbox diagnostics with provider-neutral diagnostics.
- Remove Mapbox Flutter and middleware dependencies after parity testing.
