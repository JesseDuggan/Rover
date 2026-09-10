# ROVER Technical Handoff

Date: 2026-08-30

## Purpose

ROVER is a Flutter mobile walking-experience application backed by an ASP.NET Core middleware API. The current build supports live map rendering, local route creation, road-snapped walking routes, nearby POI discovery, route adaptation, arrival detection, ElevenLabs premium narration, OpenAI-assisted local storytelling, profile/preferences scaffolding, diagnostics, and private-beta field testing.

This handoff summarizes the technical state through Phase 10. It is intended for backend, mobile, QA, DevOps, and product/technical leadership.

## Repository Layout

- `SRC/rover_middleware`
  - ASP.NET Core 10 middleware solution.
  - Clean architecture structure:
    - `Rover.Api`
    - `Rover.Application`
    - `Rover.Domain`
    - `Rover.Infrastructure`
    - `Rover.Tests`
- `SRC/rover_flutter`
  - Existing Flutter application.
  - Connects to Rover.Api through configurable Dart defines.
  - No server-side provider secrets are stored in Flutter.

## Current Capability Summary

### Middleware

- Health endpoint and development Swagger/OpenAPI.
- Clean-architecture walk-session API.
- In-memory storage mode for local/private-beta testing.
- PostgreSQL/PostGIS scaffolding is present but not the active default.
- Local `.env.local` support for developer secrets and provider mode flags.
- Mapbox routing mode for walking route geometry.
- Mapbox local discovery for POI search.
- Location Intelligence service that aggregates and normalizes:
  - Mapbox POIs
  - Wikipedia geosearch
  - Wikidata geospatial entities
  - OpenStreetMap/Overpass
  - weather/time context when configured
- OpenAI story synthesis with deterministic fallback.
- ElevenLabs premium speech rendering with server-side key handling.
- Route adaptation proposals:
  - add discovery
  - skip stop
  - shorten walk
  - extend walk
  - rejoin route
  - return to start
- Private-beta diagnostics and problem-report endpoints.
- Phase 10 route-quality and stop-lifecycle diagnostics.
- Phase 10 route-aware journey narration decision endpoint.

### Flutter

- Configurable API base URL.
- Configurable public Mapbox token through `MAPBOX_PUBLIC_TOKEN`.
- Active ROAM screen with live map, route line, markers, geofences, route options, itinerary, location updates, and Rover voice controls.
- Physical Samsung testing via `adb reverse tcp:5080 tcp:5080`.
- Route-option category chips preload from the API and refresh after movement.
- Arrival narration and Ask/Tell Me Nearby route storytelling call the middleware, not external providers directly.
- Premium voice playback uses audio returned by Rover.Api.

## Important Runtime URLs

Local API:

```text
http://127.0.0.1:5080
```

Health:

```text
http://127.0.0.1:5080/health
```

Swagger:

```text
http://127.0.0.1:5080/swagger
```

Diagnostics:

```text
http://127.0.0.1:5080/api/beta/diagnostics
```

Local discovery options:

```text
http://127.0.0.1:5080/api/beta/local-discovery-options?latitude=44.678&longitude=-76.395
```

Location context:

```text
http://127.0.0.1:5080/api/location-context?lat=44.678&lng=-76.395&radiusMeters=1500
```

## Key API Endpoints

- `GET /health`
- `GET /swagger`
- `POST /api/walks`
- `GET /api/walks/{walkSessionId}`
- `POST /api/walks/{walkSessionId}/start`
- `POST /api/walks/{walkSessionId}/location`
- `POST /api/walks/{walkSessionId}/stops/{stopId}/arrive`
- `POST /api/walks/{walkSessionId}/ask`
- `POST /api/walks/{walkSessionId}/adaptations/evaluate`
- `POST /api/walks/{walkSessionId}/adaptations/{adaptationId}/accept`
- `POST /api/walks/{walkSessionId}/adaptations/{adaptationId}/reject`
- `POST /api/walks/{walkSessionId}/journey-narration/evaluate`
- `GET /api/location-context`
- `POST /api/location-story`
- `POST /api/speech/render`
- `GET /api/beta/configuration`
- `GET /api/beta/diagnostics`
- `GET /api/beta/local-discovery-options`
- `GET /api/beta/mapbox-smoke-test`
- `POST /api/beta/problem-reports`
- `POST /api/beta/crash-breadcrumbs`

## Provider Boundaries

### Flutter

Flutter may contain:

- public Mapbox token only
- local API base URL
- development user id for local testing

Flutter must not contain:

- OpenAI API keys
- ElevenLabs API keys
- Mapbox server-side routing/search secrets
- OpenWeather API keys
- Overpass/Wikidata/Wikipedia custom backend logic

### Middleware

Middleware owns:

- server-side Mapbox routing/search tokens
- OpenAI API key and model selection
- ElevenLabs API key, voice id, model id, output format, and usage controls
- provider timeout/cache behavior
- safe error redaction
- attribution preservation

## Phase 10 Additions

Phase 10 added a field-hardening layer rather than a major new product feature.

Walk responses now include:

- `routeQuality`
  - total route distance
  - walking time
  - stop time
  - total experience time
  - requested-time utilization
  - backtracking estimate
  - repeated segment count
  - return-to-start estimate
  - warnings
- `lifecycleConsistency`
  - consistency flag
  - stop count
  - route revision
  - next stop id
  - warnings

New endpoint:

```text
POST /api/walks/{walkSessionId}/journey-narration/evaluate
```

This endpoint returns a safe decision such as:

- approaching stop
- local history
- nearby landmark
- fun fact
- weather/time context
- quiet walk

It does not implement full turn-by-turn navigation.

## Verification Status

Latest backend verification:

```text
dotnet build .\SRC\rover_middleware\Rover.sln --no-restore
Build succeeded. 0 warnings, 0 errors.
```

```text
dotnet test .\SRC\rover_middleware\Rover.sln --no-restore
67 passed, 0 failed, 67 total.
```

Flutter CLI verification note:

Flutter `dart format`, `flutter analyze`, focused `flutter test`, and `flutter build apk --debug` repeatedly hung silently in this local Codex environment during the latest Phase 10 pass and were interrupted. Previous phases did successfully build and deploy to the Samsung device during field testing.

## Known Field Observations

- Mapbox basemap rendering was fixed after standardizing public token usage.
- ElevenLabs premium voice is confirmed working after API environment correction.
- Rural areas can return sparse or inconsistent local POI/story data.
- City geofence radius must be tuned carefully; too large causes early or overlapping arrivals.
- Geofence entry works sometimes but still needs field hardening for moving users, especially while driving or when GPS accuracy fluctuates.
- Route options now recover politely if no live addable option exists.
- Route option counts must represent addable samples, not raw provider candidates.
- Route quality still needs stronger optimization so walks use requested time and avoid excessive backtracking.

## Non-Goals Already Preserved

- No Quests implementation.
- No full spoken turn-by-turn navigation.
- No provider secrets in Flutter.
- No silent fallback from configured live providers to mock providers.
- No permanent database dependency for local private-beta testing.

## Recommended Next Technical Focus

1. Stabilize arrival detection on-device.
2. Add app-side route-aware journey narration polling/scheduling using the Phase 10 endpoint.
3. Improve route optimization with route-quality diagnostics as acceptance criteria.
4. Add full Flutter CI verification outside the local hanging toolchain.
5. Move private-beta persistence to durable storage before wider testing.
6. Add production deployment hardening, secrets management, and provider cost controls.
