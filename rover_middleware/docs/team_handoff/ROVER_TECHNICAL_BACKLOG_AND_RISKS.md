# ROVER Technical Backlog And Risks

Date: 2026-08-30

## Highest Priority

### 1. Arrival Detection Reliability

Current status:

- Server evaluates only the next ordered stop.
- Arrival radius comes from the stop.
- GPS accuracy is considered.
- Consecutive readings and hysteresis are supported.
- Crossing through a geofence between GPS readings is covered by tests.

Observed issue:

- Real-world geofence entry sometimes fails to trigger voice narration.
- City geofences can overlap if radius is too large.
- Driving through a geofence is not representative of walking behavior but reveals timing issues.

Recommended work:

- Add app-side geofence state tracking for the current stop and next few stops.
- Continue server validation as the source of truth.
- Send location updates more frequently during active walking, then reduce frequency when paused/completed.
- Add debug panel fields for:
  - last location timestamp
  - GPS accuracy
  - distance to next stop
  - arrival radius
  - candidate reading count
  - last arrival decision
  - whether the reading crossed the geofence edge
- Tune radius by context:
  - rural/low-density: larger
  - city/high-density: smaller
  - always use a buffer for GPS accuracy

### 2. Route Quality And Optimization

Current status:

- Mapbox can produce road-snapped walking geometry.
- Adaptation insertion checks multiple positions and chooses a lower-duration/lower-distance option.
- Phase 10 added measurable route-quality diagnostics.

Observed issue:

- Routes can double back.
- Requested 90-minute walks have sometimes generated only 45-50 minutes of experience.
- User expects smarter start/end sequencing and less inefficient walking.

Recommended work:

- Use route-quality diagnostics as acceptance criteria before returning a route.
- Target requested-time utilization bands:
  - short walk: 75-105%
  - long walk: 80-110%
- Penalize:
  - backtracking
  - repeated segments
  - final stop far from start when a loop is expected
  - large detours for low-value POIs
- Consider a deterministic route-order optimizer:
  - nearest-neighbor seed
  - 2-opt improvement pass
  - Mapbox duration validation
  - time-budget expansion using high-story-worth POIs

### 3. Journey Narration Between Stops

Current status:

- Location Intelligence can gather verified local context.
- OpenAI can synthesize safe story text from supplied facts.
- ElevenLabs premium voice can play rendered narration.
- Phase 10 added a backend journey-narration decision endpoint.

Observed issue:

- Too much dead time between stop arrivals.
- User wants local history, fun facts, films, weather, nearby places, and a stronger story layer.

Recommended work:

- Add app-side scheduler that calls:

```text
POST /api/walks/{walkSessionId}/journey-narration/evaluate
```

- Trigger between-stop checks based on:
  - distance from previous narration
  - elapsed time since last narration
  - route progress
  - proximity to next stop
  - user audio settings
- Respect backend `priority` and `cooldownSeconds`.
- Do not interrupt safety, navigation, or arrival messages with background stories.
- Track fact ids already narrated during the walk to prevent repetition.

## Medium Priority

### 4. Route Option UX

Current status:

- Route option buttons preload from API.
- Counts should represent selectable samples.
- No-option add-discovery now recovers as an unchanged proposal.

Recommended work:

- Add loading/refresh timestamp to route option panel.
- Disable category chips until samples are loaded.
- Refresh automatically when user moves more than 500 meters.
- Show "No nearby options" per category instead of retaining stale counts.
- When a POI is added:
  - show confirmation toast
  - update itinerary
  - update map marker
  - update geofence overlay
  - prefetch arrival narration

### 5. Map UX And Symbols

Requested icons:

- user location: person
- historical stop: styled H marker
- burger place: burger
- coffee: coffee mug
- tea: teacup

Recommended work:

- Use Mapbox symbol layers or annotation images.
- Keep sequence numbers visible.
- Use accessible labels in Flutter.
- Add itinerary tap-to-focus behavior.
- Add optional full-screen map mode.
- Orient camera toward direction of travel only while follow mode is active.

### 6. Performance Hardening

Current status:

- Flutter has a performance panel.
- Backend has diagnostics and background prefetch.
- Speech render and location context can still be slow.

Recommended work:

- Add explicit latency budgets:
  - location update: under 250 ms
  - route option refresh: under 1500 ms
  - speech cache hit: under 100 ms
  - speech cache miss: under 3000 ms
  - location context cached: under 250 ms
  - location context cold: under 5000 ms
- Prefetch:
  - next stop arrival narration
  - next route-option category samples
  - nearby story context
  - first contextual journey narration decision
- Add queue wait-time metrics.
- Add provider-level timeout and circuit-breaker behavior.

## Production Readiness Risks

### Data Licensing And Attribution

Rover aggregates provider data from Mapbox, OpenStreetMap, Wikipedia, Wikidata, and weather sources. Attribution must remain attached to generated stories, POI cards, and any persisted content. Terms must be reviewed before commercial release.

### Secrets Management

Local `.env.local` is appropriate for development only. Staging/production should use managed secrets such as AWS Secrets Manager, Parameter Store, Railway variables, or equivalent.

### Persistent Storage

In-memory storage is suitable for local testing only. Before broader beta:

- enable durable profile/walk/session storage
- define retention policies
- add migrations
- add backup/restore strategy
- add deletion/export verification

### Provider Costs And Rate Limits

OpenAI, ElevenLabs, Mapbox, and weather providers need:

- usage budgets
- per-user limits
- caching
- request deduplication
- graceful degradation
- monitoring/alerts

### Mobile Battery And Privacy

Active navigation requires careful location polling. The app should:

- use high-frequency updates only during active walks
- reduce updates when paused/inactive
- disclose foreground location behavior
- avoid sending unnecessary location points
- keep debug logs privacy-safe

## Suggested Phase 10.5

Phase 10.5 should focus on route-aware navigation and narration orchestration:

- integrate journey-narration endpoint into Flutter
- add audio priority scheduler
- use route maneuvers for future turn prompts
- do not overtalk during walking
- prefetch narration before arrival
- surface attribution in POI/detail cards

## Suggested Phase 11

Phase 11 should focus on private beta reliability:

- CI build pipeline for middleware and Flutter
- clean Android debug/release build verification
- persistent storage
- staging deployment
- structured logs and metrics
- field-test dashboard
- crash/error reporting workflow

## Deferred Product Areas

Do not begin these until explicitly approved:

- Quests
- gamification
- payments
- ads marketplace
- social sharing
- white-label customer portals
- AR/camera recognition
- full production launch
