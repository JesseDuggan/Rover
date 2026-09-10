# ROVER Phase 13 Continuation Checkpoint

**Checkpoint date:** 2026-09-01  
**Purpose:** Preserve the exact Phase 13 handoff while Phase 14 work begins

## Current status

| Package | Status | Field evidence | Remaining gate |
| --- | --- | --- | --- |
| 13.0 architecture inventory | Complete | Repository and integration points documented | None |
| 13.1 contracts, flags, Guardian, coordinator | Complete | Automated behavior and privacy boundaries passed | None |
| 13.2 Android bridge and capability detection | Complete | Fold7, Samsung SM-F966W, Android API 36 capability screen verified | Gemini Nano Prompt and Image Description remain downloadable, not downloaded |
| 13.3 Lens OCR | Complete | Online restaurant/business signs and bad-weather storefront text were recognized | Continue collecting difficult-sign fixtures; no automatic scan by design |
| 13.4 Camera place resolution | Implemented and substantially field tested | OCR names resolve to sourced nearby candidates; verified/ambiguous/unresolved states and business detail panel operate | Revalidate selected-card voice after the wrong-place narration fix |
| 13.5 Scout and Curator | Implemented; automated gate complete | Diagnostics screen and deterministic ranking exercised on Fold7 | Complete a focused live ranking/refresh pass; autonomous speech remains disabled |
| 13.6 offline intelligence | Implemented; automated gate complete | Flutter now preloads bounded validated Story Packs, reports connectivity/cache state, supports offline ROAM/Camera/OCR story retrieval, strips transient claims, labels freshness, and exposes cache deletion | Complete the airplane-mode field gate |

## Confirmed design decisions

- ROVER remains the only user-facing assistant. Scout, Lens, Curator, Guardian, Listener, and Guide are internal responsibilities.
- Camera OCR is intentional/manual, not continuous or automatic.
- Local OCR output is a candidate until middleware evidence resolves it.
- Camera images remain on device for OCR and temporary captures are deleted.
- Curator ranks only candidates with verified evidence IDs.
- Curator does not independently start ElevenLabs or Android TTS in 13.5.
- Phase 14 Story Packs will become the evidence object consumed by future 13.6 offline intelligence.

## Recent fixes that require one more field regression

- Camera story playback now preserves the selected POI instead of playing a broad-area story such as “Westport is a town.”
- Middleware deterministic fallback honors the selected place even when that place has only thin evidence.
- Flutter rejects a story response whose `placeId` does not match the selected Camera card and speaks a selected-card fallback.
- The On-device AI diagnostics refresh path was corrected so returning to the screen or tapping refresh requests a new snapshot.
- Arrival narration claims a stop atomically and geofence entry tracks outside-to-inside transitions to prevent repeated mid-sentence restarts.

## Deferred issues retained explicitly

- ElevenLabs and Android fallback speech have occasionally both played. Audio-provider arbitration remains a known deferred bug.
- Geofence narration improved during field hardening but still deserves a quiet, repeated-entry regression test.
- Object detection and visual identification such as “what mountain is this?” remain future Lens work.
- Gemini Nano Prompt and Image Description models are supported/downloadable on the Fold7 but have not been installed or enabled.
- Hotel identification and rate lookup architecture exists separately; verified live-rate provider integration remains dependent on an approved provider.

## Resume order

1. Phase 14.1 grounded Story Pack foundation: complete.
2. Phase 14.2 multi-length grounded Story Pack content: complete.
3. Phase 14.3 provider expansion and place identity hardening: complete.
4. Phase 14.4 persistent Story Pack storage: complete.
5. Phase 13.6 offline intelligence: implemented on 2026-09-02; complete its airplane-mode device gate.
6. Phase 14.5 Google Places discovery and Flutter attribution: code complete; server key configured and initial Westport field gate completed.
7. Re-test the 2026-09-03 Camera latency, automatic Google reroute, and Android narration-audio fixes after a full rebuild.
8. Run the selected Camera-card narration, diagnostics refresh, arrival deduplication, and dual-voice field regressions.
9. Decide whether to enable bounded autonomous Curator narration only after audio arbitration and offline evidence are reliable.
10. Phase 15.0 discovery and the Phase 15.1 deterministic corridor-planning
    foundation are complete. Bounded evidence prefetch is next, but automatic
    corridor narration remains gated on the Phase 14 rebuilt-device regression
    and the unresolved dual-voice arbitration issue. See
    `../../rover_middleware/docs/PHASE_15_IMPLEMENTATION_REPORT.md`.

## Last known automated baselines

- Phase 13.4 checkpoint: 105 Flutter tests passed; 75 middleware tests passed.
- Phase 13.5 checkpoint: 111 Flutter tests passed.
- Phase 14.1 middleware baseline: 81 tests passed after grounding integration.
- Phase 14.2 middleware baseline: 87 tests passed after multi-section Story Pack composition.
- Phase 14.3 middleware provider was migrated to Google Places API (New); final replacement test baseline is recorded in the Phase 14.3 report.
- Phase 14.4 middleware baseline: 98 tests passed after persistent Story Pack and evidence storage.
- Phase 13.6 and 14.5 Flutter baseline: 123 tests passed after offline Story Pack caching and Google stop-attribution integration.
- Phase 14.5 middleware baseline: 100 tests passed after Google walk discovery and provider-selection integration.
- Current hardening baseline: 130 Flutter tests and 104 middleware tests passed on 2026-09-03.

The consolidated Phase 14 checkpoint is `rover_middleware/docs/PHASE_14_STATUS.md`.

This checkpoint supersedes ambiguous “pending” labels in older package sections without rewriting their historical implementation notes.
