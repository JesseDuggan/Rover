# ROVER Phase 16 - Adaptive Route Story Engine

## Status

Phase 16.3 is implemented. Route packs are prepared in the background, consumed in Active ROAM, and retained on the device when their source licenses permit offline storage. The feature remains behind the disabled-by-default Phase 16 feature flag.

## Implemented in 16.1

- Versioned Adaptive Route Story Pack `3.0` contracts.
- Route-revision-scoped and idempotent pack generation.
- Reuse of Phase 15 corridor segments and the existing grounded location evidence pipeline.
- Deterministic classification for every Phase 16 story intent.
- Prompt-like input detection and evidence-only constraints for on-demand questions.
- Quick, Short, Standard, and Deep narration variants derived only from source-backed facts.
- Navigation-aware variant selection with a configurable safety buffer before Google maneuvers.
- Evidence score ordering, place deduplication, and basic adjacent-category diversity.
- Explicit partial and insufficient-evidence results rather than invented narration.
- Pack status, retrieval, next-story, question, story/source, and playback-event endpoints.
- In-memory runtime state plus durable offline storage for eligible non-Google evidence.
- Automatic exclusion of Google-sourced content from persistent offline packs.
- Flutter request/response models, HTTP client methods, repository boundary, and disabled feature flag.

## Implemented in 16.2

- Background route-pack generation after walk creation and accepted route adaptations.
- Route-revision invalidation and refresh so stale stories do not follow a changed route.
- Active ROAM pack status, current-story selection, and unobtrusive preparation state.
- Automatic contextual playback only in suitable route gaps.
- Strict priority for geofence arrival narration and nearby Google navigation maneuvers.
- Automatic suppression while off route or close to the next stop.
- Grounded `Ask about route`, Play, Pause, Resume, Skip, Tell Me More, Save, and Sources controls.
- Heard and saved story state retained by the route-pack service.
- Source and provider metadata shown without speaking citations aloud.
- Adaptive route-story status, counts, errors, and offline eligibility in On-device AI diagnostics.
- Legacy Phase 15 contextual scheduling suppressed while Phase 16 is enabled; arrival and turn guidance remain active.

## Implemented in 16.3

- Persistent Flutter device cache for unexpired Phase 16 route packs.
- Strict exclusion of Google-sourced stories from device persistence.
- Deterministic local story selection using route windows, heard IDs, exclusions, evidence score, preferred length, and the navigation safety buffer.
- Automatic fallback to downloaded route stories only for connection and timeout failures.
- Offline `Ask about route` fallback using the current downloaded route window.
- Ordered offline playback-event queue with partial-success recovery and automatic reconciliation when the API returns.
- Local heard and saved state updates while offline so completed stories are not repeated.
- Sentence-boundary adaptive narration playback with preserved interruption state.
- Google navigation and geofence arrival can interrupt an adaptive story; the story resumes only when route safety permits.
- User Pause remains paused and is never mistaken for an automatic navigation resume.
- Device cache availability, active playback source, and queued event count in On-device AI diagnostics.
- Privacy-safe pack latency, cache, intent, completion, skip, failure, and event-queue field diagnostics without raw question text or precise coordinates.
- Existing eligible premium-audio cache is reused; downloaded narration text remains playable through device TTS when premium audio is unavailable.

## API

- `POST /api/walks/{walkSessionId}/route-story-pack/generate`
- `GET /api/walks/{walkSessionId}/route-story-pack/status`
- `GET /api/walks/{walkSessionId}/route-story-pack`
- `POST /api/walks/{walkSessionId}/route-story-pack/next`
- `POST /api/walks/{walkSessionId}/route-story-pack/ask`
- `GET /api/walks/{walkSessionId}/route-story-pack/stories/{storyId}`
- `POST /api/walks/{walkSessionId}/route-story-pack/playback-events`

## Rollout

Phase 16 requires the Phase 15 route corridor:

```text
ROVER_PHASE15_ENABLED=true
ROVER_PHASE15_CORRIDOR_ENABLED=true
ROVER_PHASE16_ENABLED=true
```

Flutter consumption remains independently gated with:

```text
ROVER_PHASE16_ENABLED=true
```

Production middleware configuration remains disabled by default. The local API
launchers enable the required Phase 15 corridor and Phase 16 gates unless
`-DisableRouteStories` is supplied. Flutter consumption is enabled by default
and can be disabled explicitly with `ROVER_PHASE16_ENABLED=false`. Arrival-only
geofence narration remains authoritative when Phase 16 is enabled.

## Storage and source policy

The runtime pack can reference current providers, including Google Places. Persistent storage follows the existing ROVER licensing policy: Google-sourced stories are not written to offline storage. Durable stories retain their claims, source IDs, attribution, retrieval timestamps, confidence, and expiry.

Files are stored under the configured location-intelligence directory in `route-story-packs`.

The Flutter device stores eligible packs in its existing application temporary-storage location. The cache is bounded to 12 route revisions, rejects expired packs, and treats corrupt cache data as unavailable. Google-sourced route stories remain online-only.

## Verification

- Middleware solution builds with zero warnings and zero errors.
- Middleware suite: 145 passed.
- Flutter analyzer: no issues.
- Flutter suite: 153 passed.

## Next checkpoint: Phase 16.4

1. Field-test story timing, category variety, source presentation, offline transitions, and arrival/turn suppression on a live route.
2. Tune configurable ranking and story-density weights from field telemetry.
3. Add explicit content-sensitivity metadata and spoken/visual notices for deeper difficult-history stories.
4. Add a saved-story library surface backed by the retained saved story IDs.
