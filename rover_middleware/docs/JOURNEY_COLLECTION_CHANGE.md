# Journey Collections: Post-Route Story Curation

Date: 2026-09-16
Status: First implementation increment completed locally; deployment and live
field verification pending. The full direction below remains the target.

## First Increment (2026-09-16)

Implemented:

- Opt-in post-route brief with coarse start/end areas, loop detection, ordered
  corridor sections, distances/timings, public POIs, interests, language, pace,
  time budget, and already-covered topic titles. Endpoint precision is reduced
  to two decimal places; internal journey IDs and raw GPS traces are excluded.
- Collection-mode research requests 3-8 chapters by walking duration (default
  maximum 8), targeting 100-180 words each, with brief and full narration variants.
  Evidence must pass the existing citation, locality, expiry and event checks.
- Route-ordered chapter metadata, available narration duration, and uncovered
  segment IDs. Flutter shows a Journey collection label and coverage information.
- Same-walk generation is serialized within one API process; matching requests
  reuse the pack. Language/audience and feature version are part of the key.
- Fresh matching packs remain available during refresh and after refresh failure.
  Empty refresh results retain fresh stories rather than replacing them with none.
- Offline filtering removes collection coverage when it excludes chapters, on
  both server and device, instead of advertising unavailable narration.

Enable only after deploying the API and rebuilding Flutter:

```text
ROVER_JOURNEY_COLLECTIONS_ENABLED=true
ROVER_LOCAL_RESEARCH_ENABLED=true
ROVER_PHASE16_ENABLED=true
```

Existing Phase 15 corridor configuration and server OpenAI credentials/model are
still required. No new provider or Google lookup is added by this increment.
Set ROVER_JOURNEY_COLLECTIONS_ENABLED=false to return to starter-pack research.
New generation uses a versioned key, so enabling/disabling does not silently reuse
the other mode's collection. Start a new walk or explicitly refresh its stories.

Collection research is limited to two model requests, up to six built-in tool
calls in the search response, the existing output-token limits (8192 search,
4096 classification by default), and the existing research timeout (60 seconds
by default, clamped to 10-90). This bounds consumption, not a fixed dollar cost.
MaximumCollectionStories is configurable under
Rover:Phase16:LocalResearch:MaximumCollectionStories, clamped to 3-12. Fewer
chapters are valid when evidence is scarce; requested chapter count is not a
quality or coverage guarantee. No live paid-provider requests were made in tests.

Remaining increments: progressive initial publication, narrated introduction and
conclusion, richer thematic transitions, narration-density preference controls,
gap-specific top-up after rerouting, semantic fact deduplication across sources,
distributed job coordination, and measured field coverage/spending targets.
Existing heard-story IDs and navigation priority are retained; this increment
does not claim full cross-revision heard-fact persistence or whole-ROAM saving.

Local verification: 158 backend tests and 182 Flutter tests passed. Release API
build succeeded with zero warnings/errors. Flutter analysis reported no errors
or warnings and five pre-existing informational braces notices. No APK build,
Git commit/push, Railway deployment, or live field verification was performed.

## Problem And Scope

Field testing now confirms story playback, but sparse short stories leave too
much dead time between POIs. Build a coherent, sourced collection for the
accepted walking journey, rather than researching isolated stops independently.
Extend the existing adaptive route-story packs and playback system.

This is separate from [Story-Led Walk Planning](STORY_LED_WALK_PLANNING.md),
which selects destinations before route creation. The new curation stage runs
after route acceptance and does not replace the routing provider, choose a
different endpoint, or silently reorder the accepted walk.

## Start-To-End Process

1. Create and accept the walking route using existing discovery and routing.
2. Build a privacy-filtered route brief with the start, endpoint, ordered POIs,
   walking corridor, segment distances, and estimated segment walking times.
   A loop explicitly identifies the endpoint as the return to its starting area.
3. Submit the brief and reusable evidence to an OpenAI-backed research/curation
   workflow. Start/end alone are insufficient: research must follow the actual
   path, not an imagined journey between two points.
4. Research the uncovered sections and validate citations, place identity,
   geographic relevance, freshness, and source-use permissions.
5. Assemble a Journey Collection with an introduction, connected walking
   chapters, POI chapters, and a conclusion. Publish usable chapters progressively
   while completing the collection within a bounded research budget.
6. Prepare upcoming audio and let Rover schedule chapters using actual progress.
   Navigation, arrivals, manual pauses, and user questions retain priority.
7. On a meaningful route revision, retain still-relevant evidence and heard
   history, discard obsolete queued chapters, and research only coverage gaps.

OpenAI is the proposed research and editorial component, not the navigation
authority or a presumed dedicated "trip planning API." Implementation should
use supported API tools and structured output, with deterministic validation.

## Route Brief Inputs

- Public starting area and endpoint, including loop versus point-to-point intent.
- Privacy-filtered walking corridor and ordered route segments; precise private
  endpoints and raw movement history are not sent to the model.
- Stable public POI identifiers, names, categories, addresses, coordinates,
  source attribution, and relevant existing evidence.
- Segment distance and walking duration, planned visit time, total time budget,
  walking pace, and the accepted route's geographic bounds.
- User-selected interests, narration language, and Quiet/Balanced/Story-rich
  preference. Send only preferences needed for curation, not profile identifiers.
- Already-covered subjects and heard fact/chapter identifiers to avoid repetition.
- Existing evidence with source URLs, publisher, retrieval time, relevant dates,
  confidence, and reuse/offline restrictions.
- Fresh optional context such as local time, season, weather, or events only when
  available from an appropriate source and relevant to the walk.

Keep route/session IDs and precise live playback state inside Rover where
possible. A sanitized start/end brief should still distinguish the correct town
and neighbourhood and preserve route order without exposing a home address.

## Story Material

Prioritize municipal heritage records, museums, historical societies, archives,
park authorities, libraries, and official place/business websites. Other reliable
sources may supplement these; publisher type alone does not establish accuracy.

Potential topics include local history, architecture, notable people, community
and cultural history, parks and ecology, waterways, public art, documented film
locations, and distinctive local businesses or food traditions. Include local
anecdotes only when supported; distinguish documented history from attributed
folklore. Broader neighbourhood context must be labelled as such, not presented
as a fact about the building directly in front of the user.

Weather, events, hours, and other changing conditions require fresh evidence and
expiry rules. Do not infer current access, safety, accessibility, or opening hours
from historical material. Do not invent connective facts to make chapters fit.
Treat retrieved pages as untrusted evidence, never as workflow instructions.

## Collection Contract

- Collection identity, route revision, language, theme, generation/expiry times,
  readiness state, coverage gaps, and total available narration duration.
- Stable chapter identity and type: introduction, walking, POI, or conclusion.
- Chapter title, theme, sequence/dependencies, and links to related chapters.
- Place/area anchor, applicable segment IDs, geographic scope, and playback window.
- Short and longer narration variants with estimated audio durations.
- Claim-level sources and attribution, retrieval/expiry times, evidence quality,
  and permitted cache/offline use.
- Fact identifiers for deduplication and a distinction between optional detail
  and essential context. Skipping a chapter must not make later narration false.

Use natural transitions only when the relevant earlier chapter was heard.
Arrival chapters and walking chapters must not repeat the same facts. Sparse
evidence should produce an honest coverage gap, not filler or mock stories.

## Playback And Coverage

OpenAI curates; Rover schedules. The collection is not a fixed audio playlist.
Choose relevant chapters that fit the time before the next navigation or arrival
interruption, resume interrupted narration appropriately, and preserve manual
pause/stop intent. Prepare audio ahead without triggering new research per GPS fix.

Initial tuning proposal, not a guarantee: in adequately sourced areas, offer a
45-90-second chapter every 2-3 minutes in a richer narration mode. Retain shorter
variants for brief walking intervals. Quiet/Balanced/Story-rich timing and final
coverage targets require field testing; never fill every silence at the expense
of navigation or evidence quality.

Measure available narration minutes, played minutes, eligible walking time,
longest unexplained silent interval, repeated facts, and research cost. Record
why playback waits: no content, ahead/outside window, navigation, arrival,
user pause, audio failure, or regeneration. Story count alone is insufficient.

## Cost, Persistence, And Failure Handling

- One logical curation job per accepted route revision and relevant preferences;
  idempotent retries must not launch duplicate research jobs.
- Bound provider calls, tokens, latency, and cost per collection. Final numeric
  budgets are an implementation decision; exhaustion returns a partial collection.
- Reuse eligible evidence/collections across compatible requests where terms
  permit; honor source expiry and restrictions, including Google-sourced content.
- Keep valid chapters playable during top-up or revision work. Do not clear a
  usable collection merely because a refresh is running or fails.
- Store collection metadata and playback progress against the journey. Whole-ROAM
  saving/resume UX remains a separate feature and must not be claimed as shipped.
- Keep keys server-side; redact private endpoints and sensitive traces from logs.
  No new paid-provider calls are authorized merely by recording this proposal.

## Acceptance And Delivery

1. Add the validated route-brief and collection contracts behind a feature flag.
2. Implement bounded, progressively available source research and curation using
   existing evidence/provider integrations where suitable.
3. Integrate collection scheduling, deduplication, audio preparation, and coverage
   diagnostics into the existing adaptive story controller.
4. Verify using fixture-backed tests before any paid-provider or field evaluation.

Acceptance tests must cover point-to-point and loop routes, private endpoints,
off-route/distant evidence, invalid citations, duplicate facts, stale dynamic
information, sparse rural sources, quota/timeouts, partial availability, revision
changes, and duplicate job requests. Playback tests must cover walking intervals,
navigation/arrival priority, interruption/resume, user pause, heard-state
persistence, and chapter transitions after a skipped chapter.

Field acceptance should demonstrate improved narration coverage on the same
representative route without increased repetition, unsafe interruptions, or
unbounded spending. Record the selected mode and actual metrics; a collection
being marked Ready is not sufficient evidence of a successful experience.
