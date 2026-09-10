# ROVER Phase 15 - Living Journey Story Engine

**Discovery checkpoint:** 2026-09-04  
**Checkpoint status:** Phase 15.0 through Phase 15.9 complete  
**Runtime behavior changed by default:** No

## Implementation progress

| Package | Status | Result | Remaining gate |
| --- | --- | --- | --- |
| 15.0 Discovery | Complete | Architecture inventory, corrected provider scope, Mapbox retirement plan, flags, risks, and tests documented | None |
| 15.1 Corridor planning | Complete | Deterministic walking-route segmentation, trigger windows, direction classification, revision-keyed plan storage, creation/adaptation integration, and bounded next-segment evidence prefetch | Physical-device behavior remains unchanged until the disabled flags are deliberately enabled |
| 15.2 Story Pack 2.0 | Complete | Additive 2.0 metadata, strict validation, versioned persistence, 1.1 read compatibility, API transport, Flutter parsing, and offline retention enforcement | Runtime remains on 1.1 until the disabled 2.0 flag is deliberately enabled |
| 15.3 Historical retrieval | Complete | Parks Canada geospatial heritage adapter, source allowlist, attribution, seven-day expiry, quiet failures, and deterministic fixtures | Keep disabled until the master, package, and provider gates are deliberately enabled |
| 15.4 Live context | Complete | Separate expiring contracts/store, Google Weather, Ticketmaster Discovery, and cited OpenAI web-search adapters; additive API endpoint | Keep all three provider gates disabled until credentials, cost controls, and physical-device presentation pass |
| 15.5 Narrative arc | Complete | Deterministic revision-aware journey openings, themes, transitions, supported connections, foreshadowing, arrivals, context moments, and recaps | Keep disabled until the scheduler and physical-device narration flow are ready |
| 15.6 Scheduler and audio priority | Complete | Typed deterministic scheduling plus single-owner Flutter interruption, freshness/relevance checks, guarded resumption, and premium/fallback race protection | Keep disabled until physical-device navigation interruption and Bluetooth/speaker playback pass |
| 15.7 User story controls | Complete | Persisted Quiet, Highlights, and Story-Rich modes; live category preferences; and typed Phase 13 commands executed by the existing voice owner | Keep behind `ROVER_PHASE15_ENABLED` until Fold7 command and navigation-priority validation |
| 15.8 Memory and scoring | Complete | Consent-gated bounded event memory feeds the existing learned preferences and deterministic narration ranking | Validate interaction signals during the Fold7 field run |
| 15.9 Caching and offline | Complete | Provider-aware Story Pack sanitization, bounded retention classes, and expiring generated-audio metadata | Validate offline playback during the Fold7 field run |

### Phase 15.1 files implemented

- `Rover.Application/Journeys/RouteStoryPlanning.cs` contains Phase 15 options,
  route-plan/segment/opportunity/candidate/trigger models, deterministic walking
  segmentation, directional classification, the plan service, and an in-memory
  revision-keyed repository.
- `Rover.Application/Walks/WalkSessionService.cs` refreshes a plan after walk
  creation and queues bounded lookahead after walk start or a confirmed arrival
  when all relevant Phase 15 flags are enabled.
- `Rover.Application/Adaptations/WalkAdaptationService.cs` refreshes a plan after
  an accepted route revision when both flags are enabled.
- `Rover.Infrastructure/Performance/QueuedRouteStoryEvidencePrefetcher.cs`
  processes a bounded, single-reader queue, deduplicates segment work, and
  discards results from superseded route revisions.
- `Rover.Infrastructure/Performance/QueuedWalkPrefetchService.cs` suppresses the
  legacy broad warmup on ordinary GPS updates while Phase 15 corridor prefetch
  owns that responsibility.
- Application and infrastructure dependency injection register the services and
  bind disabled-by-default options from configuration/environment.
- `Rover.Api/appsettings.json` and `.env.example` document disabled defaults.
- `Rover.Tests/Program.cs` verifies segmentation, deterministic revision IDs,
  trigger bounds, empty unverified candidates, direction classification,
  disabled behavior, creation storage, and accepted-revision regeneration.

Automated result after this slice: middleware build succeeded with zero warnings
and errors; 111 tests passed with zero failures. No provider is called by the
planner or on ordinary GPS updates. Evidence work is queued only for plan
creation, walk start, confirmed arrival, and accepted route revisions. The
worker fetches normalized location context only; it does not synthesize stories
or audio.

### Phase 15.2 files implemented

- `Rover.Application/LocationIntelligence/GroundedStoryModels.cs` adds stable
  story/entity identity, geographic route anchors, supported categories,
  quick/standard/deep variants, freshness, cache eligibility, interaction
  state, follow-up prompts, and related-pack references without replacing the
  existing claims, sentences, sources, or validation result.
- `Rover.Application/LocationIntelligence/GroundedStoryServices.cs` emits
  deterministic Story Pack 2.0 metadata only when the Phase 15 master and 2.0
  flags are enabled. It retains sentence-level evidence and produces 15, 60,
  and 180 second target variants.
- `Rover.Application/LocationIntelligence/StoryPackPersistence.cs` versions
  storage keys by schema and rebuilds safe narration references after transient
  evidence removal.
- `Rover.Application/LocationIntelligence/LocationStoryContextService.cs`
  reads a versioned 2.0 cache first and then falls back to an existing 1.1 cache
  during migration.
- Existing API contracts/mapping carry 2.0 metadata as additive fields. The
  existing location-story endpoint also accepts optional route-segment and
  directional context.
- Flutter `location_story_models.dart` exposes typed 2.0 metadata while keeping
  the raw Story Pack map and all 1.1 behavior compatible.
- Flutter offline intelligence rejects 2.0 packs whose retention metadata does
  not explicitly allow offline storage and sanitizes narration references.

Automated result after Phase 15.2: middleware build succeeded with zero warnings
and errors; 115 middleware tests and 133 Flutter tests passed. Flutter static
analysis reported no issues. The 2.0 feature remains disabled by default, so no
device behavior changes until it is deliberately enabled.

### Phase 15.3 files implemented

- `Rover.Infrastructure/LocationIntelligence/ParksCanadaHeritageLocationContextProvider.cs`
  adds the first authoritative-source adapter to the existing
  `ILocationContextProvider` aggregation path. It queries Parks Canada's public
  ArcGIS Interest Points feature service by coordinate and radius, filters for
  heritage-relevant records, and emits normalized places and factual claims.
- The adapter accepts HTTPS endpoints only from the approved
  `services2.arcgis.com` host. It is not a generic ArcGIS adapter or web scraper.
- Every claim retains the Parks Canada record ID, Open Data attribution,
  Open Government Licence - Canada label, source dataset URL, retrieval time,
  confidence, and expiry metadata.
- The official layer states that it is incomplete and updated weekly. The
  default retention window is therefore seven days, and absence from a response
  must never be interpreted as evidence that no heritage place exists.
- `Rover:Phase15:HistoricalRetrievalEnabled` and
  `ROVER_PHASE15_HISTORICAL_RETRIEVAL_ENABLED` add the package gate. The
  independent `ParksCanadaHeritage` provider gate must also be enabled. All
  gates remain false by default, so existing journeys do not make a new request.
- Deterministic fixtures verify spatial query construction, heritage filtering,
  stable IDs, attribution, licensing, expiry, caching, allowlist rejection,
  network failure, timeout behavior, and master-gate enforcement.

Provider selection note: the newer Federal Heritage Designations export was
evaluated first. It contains richer designation text but no coordinates, so it
was not used as a nearby-location provider. The geospatial Interest Points API
was selected because its official Open Government record supplies a public
point service suitable for radius queries. A future identity-enrichment stage
may join richer official designation exports only when deterministic place
matching is available.

Automated result after Phase 15.3: middleware build succeeded with zero warnings
and errors; 120 middleware tests passed. The provider fixture suite makes no
live calls. A separate development-only probe confirmed that the approved
ArcGIS endpoint accepts the bounded spatial heritage query and returns GeoJSON.

### Phase 15.4 files implemented

- `Rover.Application/LiveContext/LiveContextModels.cs` defines separate live
  weather, alert, event, and current-information contracts. Every item retains
  retrieval, source-update, and expiry times plus an explicit automatic-speech
  policy. These types are not Story Pack evidence and are not persistable by
  the evergreen repositories.
- `Rover.Application/LiveContext/LiveJourneyContextService.cs` runs providers
  independently, returns partial success, and uses a dedicated short-lived
  in-memory store. One provider timeout cannot block the remaining providers or
  route, arrival, and narration services.
- `GoogleWeatherLiveProvider` reads Google current conditions, a bounded hourly
  forecast, and public alerts. Ordinary conditions are request-only. A weather
  result becomes actionable only for a material near-term condition,
  precipitation, wind, or temperature change; public alerts are actionable.
- `TicketmasterLiveEventProvider` uses a geohash, bounded radius, journey time
  window, result cap, and short expiry. Events are request-only and are never
  inserted into evergreen Story Packs.
- `OpenAICurrentInformationProvider` uses backend Responses web search with
  `store: false`, approximate city/region context, optional trusted-domain
  filtering, required URL citations, and a short expiry. It never sends the
  query coordinates to web search. Crime, politics, distressing incidents, and
  non-immediate emergency news are excluded from the discovery prompt.
- `POST /api/live-context` exposes the aggregate as an additive endpoint. The
  master flag and each provider flag remain false by default; missing keys
  return typed unavailable results rather than startup or journey failures.

Automated result after Phase 15.4: middleware build succeeded with zero warnings
and errors; 125 middleware tests passed. Fixture tests cover disabled defaults,
actionable weather changes and alerts, journey-bounded events, citation-required
current information, partial provider failure, and short-lived cache reuse. No
automated test makes a live provider request.

### Phase 15.5 files implemented

- `Rover.Application/Journeys/JourneyNarrativeArc.cs` defines typed arc moments,
  validation, revision-keyed storage, deterministic construction, and collection
  of accepted Story Packs for an active walk.
- The builder emits an opening and interest-derived theme, evidence-safe context
  moments, generic transitions, supported category connections, upcoming-story
  foreshadowing, arrival introductions, and a recap. Sparse and empty arcs remain
  valid and do not fabricate factual content.
- Factual moments retain only current verified evidence IDs. Expired evidence,
  invalid packs, and unavailable claims are excluded without discarding other
  usable verified claims in the same pack.
- Walk creation initializes the arc, accepted adaptations create a new arc for
  the incremented route revision, and grounded Story Packs produced for journey
  narration are folded into the current arc.
- `GET /api/walks/{walkSessionId}/narrative-arc` exposes the current revision for
  inspection without changing the existing walk response.
- `Rover:Phase15:NarrativeArcEnabled` and
  `ROVER_PHASE15_NARRATIVE_ARC_ENABLED` provide an independent package gate.
  The master and package flags are both false by default.
- This package creates narrative structure only. It does not schedule, request,
  render, queue, or play audio and therefore cannot enable automatic narration.

Automated result after Phase 15.5: middleware build succeeded with zero warnings
and errors; 129 middleware tests passed. Coverage verifies disabled defaults,
grounded deterministic multi-stop arcs, valid sparse arcs, mixed
verified/unavailable claims, and regeneration after accepted route revisions.

### Phase 15.6 files implemented

- `Rover.Application/Journeys/NarrativeScheduler.cs` provides deterministic,
  typed `Narrate`, `Silence`, `Interrupt`, `Resume`, and `Discard` outcomes.
- The scheduler considers maneuver timing, estimated story duration, density,
  route state, walking speed, arrival proximity, attention, recent direct
  interaction, repeated facts, evidence strength, freshness, connectivity,
  queued audio, battery saver, and serious/critical thermal pressure.
- `JourneyNarrationOrchestrator` remains the one server decision path. It can
  suppress work before provider lookup and annotates accepted stories with a
  stable story ID, expiry, estimated duration, and scheduling reason.
- The existing journey-narration API contract carries scheduler context and
  typed results additively, retaining compatibility with older Flutter builds.
- Flutter `RoverVoiceController` remains the sole playback arbiter. Google
  navigation interrupts optional scheduled stories, repeated maneuver updates
  preserve intentional silence, and only the same fresh, route-relevant story
  can resume outside the maneuver and arrival windows.
- Playback generations invalidate canceled asynchronous work. A stopped or
  superseded ElevenLabs request cannot subsequently start Android fallback
  speech, and successful premium playback never invokes fallback speech.
- Existing upcoming-stop ElevenLabs prefetch remains in the same coordinator
  and now skips off-route, arrival-sensitive, and urgent-navigation states.
- `Rover:Phase15:NarrativeSchedulerEnabled` and
  `ROVER_PHASE15_SCHEDULER_ENABLED` provide an independent gate. The
  master and package flags remain false by default.

Automated result after Phase 15.6: middleware build succeeded with zero warnings
and errors; 133 middleware tests passed. The complete Flutter suite passed 135
tests, the focused voice suite passed 13 tests, and Flutter static analysis
reported no issues. Tests cover urgent pre-provider silence, scheduler metadata,
resume/discard decisions, navigation interruption, stale generation rejection,
and exclusive premium-versus-device playback.

### Phase 15.7 files implemented

- Existing middleware and Flutter profile models now persist `StoryDensity` and
  excluded story categories additively. Older stored profiles and local files
  default to `Highlights` without migration work.
- Preferences exposes Quiet, Highlights, and Story-Rich as a segmented control
  plus the existing interest chips expanded to the Phase 15 story categories.
- Each journey-narration evaluation carries the current preferred and excluded
  categories, so changes made during an active walk take effect before the next
  story is selected. Excluded weather suppresses optional weather narration,
  not safety or navigation audio.
- `RoverOnDeviceAiCoordinator` deterministically recognizes the required typed
  story commands. `RoverVoiceController` executes local controls through the
  existing single playback owner and sends factual follow-up/current-info
  questions through the existing Ask Rover API.
- Quiet for ten minutes is a temporary client state. It suppresses scheduled
  stories only; Google navigation, safety, direct answers, and geofence arrival
  narration retain their established priorities. Resume clears the temporary
  window, while skip invalidates current optional playback safely.
- The new UI and command interception are gated by Flutter
  `ROVER_PHASE15_ENABLED`. Existing Phase 13 and Phase 14 behavior remains the
  default when that compile-time flag is absent or false.

Automated result after Phase 15.7: middleware build succeeded with zero warnings
and errors; 135 middleware tests passed. The complete Flutter suite passed 139
tests and Flutter static analysis reported no issues. Coverage includes density
normalization/defaults, live category exclusion, request serialization, all
required typed command classifications, and local quiet/resume behavior without
an API call.

## Objective

Phase 15 extends the existing journey, location-intelligence, Story Pack,
narration, audio, preferences, and offline systems so that verified stories can
be discovered and scheduled throughout a route corridor. It does not create a
second assistant, mapping stack, evidence model, or audio player.

The first shipping mode remains walking. Contracts may retain speed and travel
mode fields for later use, but Phase 15 must not claim driving support until a
separate driving safety and field-validation gate exists.

## Decisions made at discovery

1. Google Maps, Google Routes, and Google Places are the only active map,
   routing, and commercial place-discovery platform for Phase 15.
2. OpenTripMap remains removed and must not be reintroduced. Historical
   retrieval will use Wikipedia, Wikidata, OpenStreetMap where its terms and
   data are appropriate, and approved authoritative local sources.
3. Story Pack 2.0 is an additive schema evolution. Existing 1.1 packs remain
   readable during migration; no parallel Story Pack repository is created.
4. All Phase 15 behavior is disabled by default behind server and client feature
   flags. Existing Phase 13 and Phase 14 behavior remains the fallback.
5. Five relevant story moments across three categories is a field-test target,
   not a content quota. Weak evidence, poor timing, or navigation pressure must
   result in intentional silence rather than filler.
6. Every factual sentence keeps evidence identifiers through ranking,
   composition, scheduling, API transport, playback, and persistence.
7. Live information is backend-only, timestamped, independently expiring, and
   never substituted for evergreen content when credentials or connectivity are
   unavailable.
8. Audio arbitration must prevent ElevenLabs and Android fallback playback from
   overlapping before automatic corridor storytelling is enabled in the field.

## Phase 14 entry gate

Phase 14.1 through 14.5 are code complete. Before Phase 15 automatic narration
is enabled on a physical device, one rebuilt Fold7 pass must confirm:

- Camera OCR promptly selects an already visible sourced candidate.
- Leaving the route rebuilds the Google route and refreshes the maneuver banner.
- Entering a fresh geofence produces one audible arrival narration.
- ElevenLabs and Android fallback do not speak simultaneously.
- Google attribution remains visible and Google-derived content is not stored as
  an offline Story Pack.

Phase 15.1 domain and deterministic planning work may proceed while this field
gate is being completed.

## Existing architecture to extend

| Concern | Existing implementation | Phase 15 use |
| --- | --- | --- |
| Route geometry and maneuvers | `Rover.Domain/Walks/WalkRoute.cs`, `WalkRouteManeuver.cs`, and `Rover.Infrastructure/Walks/GoogleRoutesWalkRouteProvider.cs` | Segment the existing Google route; do not request a second route for storytelling |
| Journey state and location | `WalkSession`, `LocationUpdateCommand`, `LocationUpdateResult`, `RouteMath`, and Flutter `ActiveRoamController` | Generate plans on route creation/revision and evaluate windows from serialized location updates |
| Narration decision | `Rover.Application/Journeys/JourneyNarrationOrchestrator.cs` | Extend the current decision path with planned corridor opportunities and scheduler context |
| Location knowledge | `ILocationStoryContextService`, `LocationStoryContextService`, and provider-neutral `ILocationContextProvider` implementations | Retrieve and normalize evidence without creating a second provider aggregator |
| Evidence and grounding | `GroundedStoryModels.cs`, `StrictStoryGroundingValidator`, and `LocationIntelligenceResponseMapper` | Evolve to sentence-level Story Pack 2.0 metadata while preserving strict validation |
| Story persistence | `IStoryPackRepository`, `IEvidenceRepository`, `DefaultStoryPackPersistencePolicy`, and `FileLocationIntelligenceRepository` | Add schema-aware keys and retention classes to the current repository |
| Background prefetch | `QueuedWalkPrefetchService` and `IRoverWalkPrefetchService` | Replace broad current-location warming with bounded next-segment work items |
| Premium speech | `IRoverSpeechService`, `RoverSpeechService`, `ElevenLabsTextToSpeechProvider`, and generated-audio caches | Prefetch only scheduler-eligible evergreen audio and retain existing fallback semantics |
| Client audio priority | Flutter `RoverVoiceController`, `RoverAudioSessionCoordinator`, and native voice channel | Remain the single playback owner and enforce navigation interruption/resumption |
| Typed assistant actions | `RoverOnDeviceAiCoordinator`, Curator, Scout, and existing conversation/profile APIs | Add typed Phase 15 commands without adding another assistant surface |
| Preferences | Middleware profile preferences and Flutter `RoverPreferences` repositories/controllers | Add story density and category preferences through backward-compatible optional fields |
| Offline intelligence | Flutter `RoverOfflineIntelligence` and middleware Story Pack persistence | Reuse bounded caches; keep live and provider-restricted content out |
| Camera/AR | Flutter `CameraExplorerScreen`, Lens service, and observation resolution APIs | Reuse verified place identity; camera pixels are not a corridor-story source |

## Current provider status

| Provider or capability | Status at checkpoint | Phase 15 disposition |
| --- | --- | --- |
| Google Maps Flutter SDK | Operational and preferred | Keep; remove temporary Mapbox renderer fallback after parity gate |
| Google Routes API | Operational for walking geometry and maneuvers | Required route source for corridor segmentation |
| Google Places API (New) | Operational server-side for places and camera resolution | Identity/current place data only; obey attribution and storage restrictions |
| Wikipedia Geosearch | Implemented and configurable | Retain as evergreen historical discovery/evidence source |
| Wikidata | Implemented and configurable | Retain for identity and structured evergreen claims |
| OpenStreetMap/Overpass | Implemented and configurable | Retain only where approved terms and attribution permit |
| OpenTripMap | Removed | Prohibited; no adapter, configuration, or fallback |
| Existing weather adapter | OpenWeather-based and optional | Keep disabled during migration; add a separate Google Weather adapter in 15.4 |
| Google Weather API | Implemented, disabled by default | Backend-only current, bounded forecast, and public-alert adapter |
| Ticketmaster Discovery API | Implemented, disabled by default | Backend-only journey-window event adapter |
| OpenAI story synthesis | Implemented behind configuration | Reuse for grounded composition; output still passes strict validation |
| OpenAI web search | Separate current-information adapter implemented, disabled by default | Keep request-only until current-info presentation and field gates pass |
| Municipal/heritage sources | No general adapter registry | Add approved source definitions incrementally; do not silently scrape |
| ElevenLabs | Implemented with generated-audio cache | Reuse after dual-playback arbitration passes |
| Android device speech | Implemented fallback | Reuse as fallback through the same playback owner |

Missing credentials or provider failures must return typed unavailable results;
they must never prevent route creation, navigation, arrival handling, or use of
already validated evergreen content.

## Remaining Mapbox inventory

Mapbox is disabled in the primary field configuration but is still a real code
and build dependency. Removal must be staged rather than treated as a text-only
cleanup.

### Flutter runtime and build

- `pubspec.yaml` and `pubspec.lock` include `mapbox_maps_flutter`.
- `lib/main.dart` initializes the Mapbox SDK token.
- `lib/src/maps/rover_map_view.dart` contains the Mapbox renderer and annotation
  implementation alongside the Google renderer.
- `lib/src/maps/mapbox_config.dart` and `rover_map_provider.dart` expose the
  fallback selection.
- `.env.example`, Samsung/Chrome run scripts, README instructions, tests, and
  Android Gradle comments still reference Mapbox.
- Flutter beta diagnostic models still expose `mapboxConfigured`.

### Middleware runtime and configuration

- `MapboxWalkRouteProvider`, `MapboxLocalDiscoveryProvider`,
  `MapboxLocationContextProvider`, and `MapboxNearbyDiscoveryProvider` remain.
- Dependency injection still registers Mapbox HTTP clients, options, providers,
  environment fallbacks, and discovery modes.
- API diagnostics and `/api/beta/mapbox-smoke-test` remain.
- Application/API contracts retain Mapbox-specific diagnostic and provider-ID
  fields.
- `appsettings*.json`, `.env.example`, README, runbooks, and tests retain Mapbox
  configuration and examples.

### Compatibility distinction

Operational dependencies, configuration, and selectable provider modes will be
removed. Nullable Mapbox identifiers inside schema 1.1 data may be retained only
for backward deserialization until Story Pack 2.0 migration is proven. Archived
phase reports may describe what existed historically, but active setup guides
must not instruct developers to configure or run Mapbox.

### Retirement sequence

1. Confirm the Phase 14 Google parity gate on Fold7.
2. Move Google rendering into the sole `RoverMapView` path; remove Mapbox token
   initialization, selection, dependency, scripts, and Flutter tests.
3. Remove Mapbox routing/discovery/context providers, DI registrations, smoke
   endpoint, settings, environment variables, and active documentation.
4. Replace Mapbox-named test fixtures with provider-neutral or Google fixtures.
5. Keep schema 1.1 read compatibility, but prevent new Mapbox identifiers from
   being produced.
6. Add a repository check that fails when active source/configuration introduces
   `mapbox_maps_flutter`, Mapbox endpoints, tokens, or selectable modes. Exclude
   explicitly archived reports from that check.

## Feature flags

The middleware should add a single options object bound from
`Rover:Phase15` with environment overrides. Defaults are false.

| Flag | Purpose |
| --- | --- |
| `ROVER_PHASE15_ENABLED` | Master server gate |
| `ROVER_PHASE15_CORRIDOR_ENABLED` | Route segmentation and opportunity planning |
| `ROVER_PHASE15_EVIDENCE_PREFETCH_ENABLED` | Bounded next-segment evidence warming |
| `ROVER_PHASE15_STORY_PACK_V2_ENABLED` | Story Pack 2.0 production and transport |
| `ROVER_PHASE15_LIVE_WEATHER_ENABLED` | Actionable Google Weather context |
| `ROVER_PHASE15_EVENTS_ENABLED` | Scheduled event retrieval |
| `ROVER_PHASE15_CURRENT_INFO_ENABLED` | Cited current local information |
| `ROVER_PHASE15_NARRATIVE_ARC_ENABLED` | Journey theme and evidence-safe transitions |
| `ROVER_PHASE15_SCHEDULER_ENABLED` | Automatic corridor story scheduling |
| `ROVER_PHASE15_MEMORY_ENABLED` | Privacy-safe story interaction memory |

Flutter should use `ROVER_PHASE15_ENABLED` as its master compile-time gate and
consume server capability fields for individual behavior. Flutter must not carry
live-provider secrets.

## Planned packages and file changes

### 15.1 - Route corridor planning

Add provider-free application/domain models for route segments, opportunities,
directional context, and trigger windows. Add a deterministic planner that takes
`WalkRoute`, stops, interests, and walking assumptions. Store the plan with the
walk session or a repository keyed by walk ID and route revision. Regenerate it
only when the route revision changes.

Expected areas:

- `Rover.Application/Journeys/` for corridor models, planner interface, and
  deterministic implementation.
- `Rover.Application/Walks/` for narrowly scoped integration with creation and
  accepted route revisions.
- `Rover.Tests/Program.cs` for segmentation, direction, bounds, deduplication,
  and route-revision tests.

15.1 must make no external request on a GPS update. It produces opportunities,
not factual stories and not audio.

### 15.2 - Story Pack 2.0

Extend `GroundedStoryModels.cs` and API/Flutter models with stable story and
entity IDs, route anchors, categories, tags, directional context, duration
variants, freshness class, narration state, related packs, prompts, and
sentence-level evidence references. Add explicit 1.1 read compatibility and 2.0
storage-key versioning.

The existing validator and repository remain authoritative. Schema migration
tests must load 1.1 fixtures and round-trip 2.0 packs.

### 15.3 - Authoritative historical retrieval

Extend the existing `ILocationContextProvider` system with approved,
provider-specific adapters and allowlists. Start with one source whose API,
license, attribution, and retention rules are documented. Do not add a generic
web scraper and do not add OpenTripMap.

### 15.4 - Live journey context

Create separate weather, event, and current-information interfaces so their
short expiry and automatic-speech policies cannot leak into evergreen Story
Packs. Add disabled/no-op implementations first, then Google Weather,
Ticketmaster or an approved equivalent, and backend OpenAI cited search behind
independent flags.

### 15.5 - Narrative arc

Add a lightweight journey arc referencing only accepted Story Pack evidence.
Transitions may connect existing supported claims but may not introduce facts.
An empty or sparse arc is valid.

### 15.6 - Scheduler and audio priority

Extend `JourneyNarrationOrchestrator` and Flutter `RoverVoiceController`; do not
create a second queue or player. The server chooses a typed opportunity and the
client remains the final playback arbiter. Navigation and safety interrupt
stories. Resumption requires the same story to remain fresh, relevant, and
outside an urgent maneuver window.

### 15.7 - User controls

Add Quiet, Highlights, and Story-Rich density plus category preferences using
the existing preference and typed-action paths. Add quiet/resume/skip/short/more
actions to the existing Phase 13 coordinator.

### 15.8 - Memory and scoring

Add privacy-safe event records and deterministic ranking. Do not infer sensitive
traits. Retention and deletion must use existing privacy controls.

### 15.9 - Caching and offline

Extend existing repositories and `RoverOfflineIntelligence`. Separate evergreen
packs, live context, and audio metadata. Provider retention policy is evaluated
before storage. Expired live material is never narrated offline.

## Data and request flow

1. Google Routes creates or revises a walking route.
2. The corridor planner divides that existing geometry into deterministic
   travel-time segments and trigger windows.
3. Bounded background work prefetches evidence for the next segments.
4. The Location Knowledge Engine resolves identities and normalizes evidence.
5. Story Pack composition creates duration variants and retains evidence IDs.
6. Strict grounding validation rejects unsupported output.
7. The scheduler evaluates navigation pressure, freshness, user settings,
   repetition, device state, and available time.
8. The existing journey narration API returns a typed decision.
9. `RoverVoiceController` arbitrates playback against navigation and direct user
   actions.
10. Eligible evergreen packs and audio are cached according to provider policy;
    live context expires independently.

## Main risks and mitigations

| Risk | Mitigation |
| --- | --- |
| Story work competes with navigation | Scheduler uses maneuver windows; client navigation priority remains final |
| Duplicate ElevenLabs/device speech | One playback owner, cancellation token/generation checks, and physical-device regression before scheduler enablement |
| Provider latency repeats Camera issues | Segment prefetch, bounded concurrency, timeouts, and no external calls per GPS reading |
| Unsupported narrative transitions | Transitions carry evidence IDs and pass the same validator as factual sentences |
| Google content retained illegally | Existing persistence policy remains deny-by-default; add provider-specific retention metadata |
| Story Pack migration breaks offline data | Read 1.1, write 2.0 only behind flag, migration fixtures, bounded cache reset fallback |
| Live information content becomes stale | Separate interfaces and stores with retrieval, source, and expiry timestamps |
| Forced story volume creates filler | Silence is a valid planner and scheduler result |
| Mapbox removal breaks an overlooked path | Staged removal plus source/configuration detector and Google parity tests |
| Route revisions strand prefetched work | Key plans and work items by walk ID plus route revision; discard stale results |

## Automated test plan

- Route segmentation across short, long, sparse, looping, and revised routes.
- Trigger windows, route direction, left/right/ahead/behind classification, and
  walking-time estimates.
- Deterministic ranking, density modes, duration choice, and intentional silence.
- Story Pack 1.1 compatibility and Story Pack 2.0 validation/round trip.
- Sentence evidence propagation and unsupported-fact rejection.
- Provider timeout, missing credentials, no-op fallback, and stale-result discard.
- Navigation interruption, eligible story resumption, stale discard, and no
  ElevenLabs/device overlap.
- Freshness and expiry for weather, events, closures, and current information.
- Offline evergreen success and expired/restricted live-content rejection.
- Typed user commands and privacy-safe interaction logging/deletion.
- Active Mapbox package, endpoint, token, configuration, and selectable-mode
  detection.

All provider tests use deterministic fixtures. Automated suites must not require
live Google, OpenAI, Ticketmaster, weather, Wikipedia, or Wikidata calls.

## Fold7 field plan

After packages are implemented, run one 30-45 minute walking journey in folded
and unfolded layouts. Capture:

- At least three evidence-supported categories when locally available.
- Story offer/start/completion/skip and one `Tell me more` action.
- A navigation interruption and a safe eligible resumption.
- One requested current-information result and one relevant/requested weather
  result, each with visible freshness/source data.
- Screen lock/resume, background/foreground, poor GPS, route revision, and loss
  of connectivity.
- Offline evergreen narration with no expired live content.
- Audio output through the device speaker and, separately, Bluetooth if
  connected.

Do not claim field success from emulator or automated results.

## Phase 15.8 implementation

Phase 15.8 records coarse story lifecycle events only when Improve
Recommendations is enabled. Events are idempotent, retention bounded, and
cleared by the existing learning reset, opt-out, and profile deletion paths.
Completed, skipped, replayed, tell-more, and dismissed signals feed the existing
learned category preferences. Journey narration applies those category scores
inside its existing deterministic rank and returns an explainable score and
reason list for diagnostics. No sensitive traits, raw location trails, camera
data, transcripts, or narration audio are stored as interaction memory.

Automated result after Phase 15.8: middleware API and test builds succeeded with
zero warnings and 137 middleware tests passed. Flutter analysis and tests cover
the new request, response, and event contracts.

## Phase 15.9 implementation

Phase 15.9 completes the provider-aware offline boundary. Story Pack persistence
now separates evergreen, expiring, mixed, live, and restricted material. Mixed
packs may retain grounded durable facts only after hours, closures, prices,
weather, events, availability, relative position, and other live claims are
removed. Live-only and Google-derived packs remain unavailable for persistent
offline narration.

Flutter applies the same deny-by-default policy before writing device Story
Packs, caps evergreen and expiring retention, removes live sentences and their
evidence, clears prefetched audio references, and refuses unknown retention
classes. Expired live material cannot be selected by offline story, nearby, or
Camera matching paths.

Generated premium audio is reusable only when the narration path explicitly
marks it eligible. Versioned metadata records creation and expiry, content
version, byte length, and optional story/variant identity. Expired, mismatched,
legacy, or incomplete entries are removed with their audio file. Google, live,
mixed, direct-answer, and local-only speech remains playable without entering
the reusable cache.

Automated result after Phase 15.9: middleware API and test builds succeeded with
zero warnings and 138 middleware tests passed. Flutter analysis reported no
issues; focused cache, API-contract, and voice suites passed 41 tests, and the
complete Flutter suite passed 143 tests.

## Phase 15 completion state

Phase 15.0 through 15.9 are code complete. The remaining acceptance work is the
documented Fold7 physical-device field run, including online/offline transition,
expired-live rejection, navigation interruption, narration resumption, and
speaker/Bluetooth playback checks.
