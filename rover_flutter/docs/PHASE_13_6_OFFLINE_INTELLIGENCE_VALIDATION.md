# ROVER Phase 13.6 - Offline Intelligence Validation

**Implementation date:** 2026-09-02  
**Status:** Implemented; automated gate passed; device field gate pending

## Delivered behavior

- Phase 13.6 is controlled by both `ROVER_PHASE13_ENABLED` and `ROVER_AI_OFFLINE`.
- An active API ROAM preloads validated Story Packs for its stops in the background.
- Story Packs survive app restarts in a bounded device-local cache.
- The cache is limited to 50 Story Packs or 5 MB and discards expired entries.
- Google-derived Story Pack content is not persisted.
- Relative location, opening hours, closures, prices, weather, current events, and other time-sensitive claims are removed before persistence.
- `Tell Me Nearby`, selected Camera stories, Camera POI overlays, and Camera OCR name resolution can fall back to cached content after a middleware connection failure.
- Offline narration identifies itself as cached and states its last verification date.
- Offline narration uses Android local speech directly and does not call ElevenLabs.
- Scout now reports real `online`, `offline`, and cache availability state without Camera updates resetting it to `unknown`.
- The On-device AI screen shows cache count, storage use, preload state, freshness, and a **Clear offline stories** control.

## Enable the phase

Add these lines to the same valid Dart define file used for the current build:

```text
ROVER_PHASE13_ENABLED=true
ROVER_AI_OFFLINE=true
```

Keep the existing API URL, Google Maps provider, Maps key, and other Phase 13 flags in that file. Every non-empty line must use `NAME=value` format.

## Device field gate

1. Start the middleware and run ROVER online with both flags enabled.
2. Create or open an API-backed ROAM.
3. Open **Profile > On-device AI** and tap refresh.
4. Confirm **Offline stories** changes from `0` to one or more Story Packs after journey preload finishes.
5. Turn on airplane mode while keeping the app open.
6. Return to the active ROAM and request a story for a cached stop.
7. Confirm the spoken response begins with “From your offline stories” and includes a `YYYY-MM-DD` verification date.
8. Open Camera Explorer near a cached stop. Confirm its status says **Offline cached match** and cached labels can appear.
9. Point Camera OCR at the cached business or landmark name. Confirm the result is explicitly identified as an offline cached name match.
10. Confirm no cached narration claims live hours, closures, prices, weather, events, or current distance/direction.
11. Return to **On-device AI**, tap **Clear offline stories**, and confirm Story Packs and storage both return to zero.
12. While still offline, confirm the cleared story can no longer be retrieved.

## Automated coverage

`test/rover_offline_intelligence_test.dart` covers:

- durable-claim filtering and offline freshness labels;
- rejection of Google-derived and expired Story Packs;
- Camera context and OCR matching from cached identities;
- repository fallback on connectivity failures;
- disk reload after an app-style restart; and
- deletion of cached data.

The full Dart analyzer passes with no issues. The focused Phase 13.6 suite passes all 6 tests, and the full Flutter suite passes all 122 tests.

## Scope boundary

Phase 13.6 supplies offline place identity and grounded narration. Creating, adapting, progressing, or synchronizing a middleware-backed ROAM still requires connectivity. Offline route mutation and synchronization are separate future work.
