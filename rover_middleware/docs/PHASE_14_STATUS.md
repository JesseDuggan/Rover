# ROVER Phase 14 Status

**Checkpoint date:** 2026-09-03  
**Overall status:** Core Phase 14 implementation complete; final device regression pass remains

**Phase 15 handoff:** Phase 15.0 discovery and the Phase 15.1 deterministic
corridor-planning foundation completed on 2026-09-03. The
repository inventory, corrected provider scope, Mapbox retirement plan, feature
flags, risks, and staged implementation plan are recorded in
`PHASE_15_IMPLEMENTATION_REPORT.md`. Bounded evidence-prefetch work may proceed
while the final Phase 14 device regression is completed; automatic Phase 15
narration remains gated on that regression.

## Package status

| Package | Status | Confirmed outcome | Remaining gate |
| --- | --- | --- | --- |
| 14.1 Grounding foundation | Complete | Canonical identity, evidence claims, citations, validation, and deterministic fallback | None |
| 14.2 Story Pack content | Complete | Schema 1.1 Camera, arrival, and deeper sections with profile ordering and sparse-evidence behavior | None |
| 14.3 Google Places and identity | Complete | OpenTripMap removed; Google Places nearby and OCR search, Wikipedia/Wikidata identity, attribution, and collision safeguards implemented | Continue ordinary field coverage |
| 14.3 Google Maps UI migration | Implemented and field tested | Google map, route, pins, geofences, gestures, location following, and recentering operate on Android | Keep Mapbox fallback until final parity decision |
| 14.4 Persistent Story Packs | Complete | Validated non-Google Story Packs and evidence survive middleware restarts; prohibited Google content is excluded | None |
| 14.5 Google rollout and Flutter consumption | Implemented; automated gate complete; field hardening in progress | Google Places supplies walk stops and Camera candidates; Google Maps attribution is carried through Flutter; Google Routes supplies walking geometry and maneuvers | Re-test Camera speed, automatic off-route rebuilding, and audible geofence narration after the 2026-09-03 fixes |
| 14.6 Optional provider expansion | Not started | Gemini Maps Grounding, Overture ingestion, and current-events adapters remain optional | Product decision before implementation |

## Field evidence

- Google Maps loads on the physical Android device with route geometry, stop pins, and geofence circles.
- Google Places is configured server-side and supplies real Westport businesses and landmarks.
- Active ROAM displays Google Maps attribution for Google-derived stops.
- Camera Explorer displays directional nearby candidates and resolves intentional OCR captures.
- Persistent offline Story Packs were created and reported by the on-device diagnostics screen.
- Wireless LAN development works without a USB tether after the API address is configured.
- Westport field testing exposed Camera latency, stale off-route maneuvers, and silent arrival audio; targeted fixes are implemented and awaiting a rebuilt-device pass.

## Latest hardening

The 2026-09-03 field fixes:

- Serialize live GPS submissions and retain only the newest pending reading, preventing stale responses from racing geofence and route state.
- Automatically request and accept a Google `RejoinRoute` after the middleware confirms the user is off route.
- Reset route-position progress when a rejoin route is accepted and track it separately from overall walk completion.
- Use an exact OCR match against already sourced Camera labels without making a duplicate Google Places request.
- Request Android navigation audio focus for premium narration and fallback text-to-speech.

## Automated baseline

- Flutter analyzer: no issues.
- Flutter tests: 130 passed, 0 failed.
- Middleware build: 0 warnings, 0 errors.
- Middleware tests: 104 passed, 0 failed.

The latest suite includes regression coverage for automatic client rejoin and middleware route-tracking reset.

## Known deferred items

- ElevenLabs and Android fallback have occasionally overlapped. Provider arbitration remains a separate audio hardening task.
- Android can route narration to a connected Bluetooth device. The next audio field pass should test both Bluetooth-connected and device-speaker cases.
- Phase 13.6 still needs its final airplane-mode device gate.
- Mapbox fallback code and credentials should be removed only after Google Maps, Google Routes, and Google Places pass the final parity review.
- Optional Phase 14.6 providers are not required to close the core Phase 14 implementation.

## Exit recommendation

Treat Phase 14.1 through 14.5 as code complete. Close Phase 14 after one rebuilt Android field pass confirms:

1. Camera sign matching returns promptly for an already visible candidate.
2. Leaving the route rebuilds the Google route and updates the maneuver banner.
3. Entering a fresh geofence plays one audible narration through the expected Android output.
4. Google attribution remains visible and Google-derived content is not persisted as an offline Story Pack.
