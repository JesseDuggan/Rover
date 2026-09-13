# Story-Led Walk Planning

This opt-in API feature chooses destinations before a walk is created. It does
not change arrival triggers, story playback, narration text, or active rerouting.

## Enable after deployment

Set these Railway server variables:

```text
ROVER_STORY_LED_PLANNING_ENABLED=true
ROVER_ROUTING_MODE=Google
ROVER_LOCAL_DISCOVERY_MODE=GooglePlaces
```

Keep the existing server OPENAI_API_KEY and Google credentials. The model uses
ROVER_STORY_LED_PLANNING_MODEL when set, otherwise OPENAI_MODEL, otherwise the
existing Rover:Conversation:OpenAI:Model configuration. No new Flutter flag,
provider key, or APK is required for this server-only planning feature.
The separately reconciled Flutter improvements still require their own build.

The feature is off by default and also inactive outside Google routing and
Google Places discovery. Enable it deliberately after deploying the code.
Set ROVER_STORY_LED_PLANNING_ENABLED=false to roll back without an APK change.

## Behavior

- Fetch up to 30 local Google candidates through the existing discovery service.
- Filter out candidates without Google identity/source metadata, invalid
  coordinates, duplicate IDs, or distance greater than 5 km from the start.
- Allow up to three seconds for the existing Wikipedia provider. Attach only
  fresh summary evidence whose normalized name matches the Google venue and
  whose coordinates are within 100 m. Same-name distant venues are not merged.
- Ask OpenAI once to select 2-12 existing IDs in priority order, emphasizing
  supplied history/culture/architecture and user interests rather than chains.
- Validate the entire selection. Unknown IDs, duplicates, incomplete responses,
  malformed output, missing configuration, provider failures and timeouts use
  the existing deterministic planner instead.
- Preserve all original stop identity, coordinates, source attribution and
  arrival narration. Code orders the route; Google supplies walking geometry
  and maneuvers. The existing Google routing failure behavior is unchanged.
- If selected stops exceed available time, remove lower-priority stops and
  request at most one shorter route. Always report actual returned duration
  plus visit time in this mode. Warn if even the reduced route remains too long.

The whole enrichment/selection step has a 12-second default budget, configurable
with Rover__StoryLedPlanning__TimeoutSeconds (clamped 1-20 seconds). Google
discovery and routing retain their separate existing timeouts. No retry handler
is added to the OpenAI selection call.

## Diagnostics and privacy

The existing route preview summary includes either "Story-led planning: OpenAI
selected ..." with a Wikipedia match count, or "Story-led planning fallback"
and a non-secret reason. This status is about destination selection, not loaded
or played story counts. A match count of zero is possible and disclosed.

OpenAI receives bounded public place names, categories, descriptions, matched
evidence, approximate distances, interests, pace and available time. It does not
receive user/profile IDs, precise starting GPS or a route trace. Response storage
is disabled. Candidate text is untrusted input. Structured output contains IDs
only; AI-generated narration, coordinates and access claims are never accepted.
See https://developers.openai.com/api/docs/guides/structured-outputs.

## First-version limits

This improves selection within the Google candidate pool; it is not a global
web-search destination discovery system. Wikipedia-only destinations are not
added, and exact-name matching intentionally misses aliases. Wikipedia provider
coverage, language and configured result limits still apply. No inferred hours,
current events, public access or accessibility assurances are added. Existing
accessibility behavior is unchanged; this does not certify accessible routes.
The separate research/story pipeline still supplies between-stop stories.

## Verification

Local verification: 154 backend tests passed; Release API build succeeded with
zero warnings and errors. Live-provider quality and field behavior remain
unverified until deployment. No repository push or Railway change was made.

Automated tests cover ID validation, incomplete/malformed responses, disabled
and missing configuration, HTTP failure, timeout, caller cancellation, exact
evidence matching, source expiry, original narration/attribution, fallback,
bounded rerouting and truthful duration warnings. No live OpenAI or Google
requests are used by these tests.

After deployment, create a NEW walk with history/culture interests. Check the
preview summary for selection versus fallback and review retained destinations
and duration. Compare against a new walk with the flag off. Then confirm normal
Google directions and arrival narration on a short walk. Existing walks are
not replanned by enabling this feature.
