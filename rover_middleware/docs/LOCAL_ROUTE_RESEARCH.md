# Local Route Research

## Scope

The first version discovers local online sources dynamically for a route, rather
than requiring a separate Ontario, BIA, or city integration. It supplements the
existing story pack and does not change automatic playback or arrival priority.

During pack generation, a web-search request asks for up to six cited passages
covering history, culture, architecture, local people, and dated events. It favors
primary local sources and searches in the local language. A second, tool-free
request classifies those passages and locates their subjects; it cannot write new
narration. Accepted passages become route stories with source links.

## Configuration

Both server flags must be enabled:

```text
ROVER_PHASE16_ENABLED=true
ROVER_LOCAL_RESEARCH_ENABLED=true
```

The existing `OPENAI_API_KEY` stays on the API server. The model defaults to the
existing current-information model. `ROVER_LOCAL_RESEARCH_MODEL` optionally
overrides it; the selected model must support Responses web search and structured
outputs. Never put this API key in Flutter configuration.

The local `run_rover_api.ps1` and `run-rover-api-lan.ps1` launchers enable research
with the other local story features. Their `-DisableRouteStories` switch disables
it too. Other deployment paths default research to disabled.

There are at most two Responses requests per research attempt. The combined
timeout defaults to 60 seconds and can be configured through
`Rover:Phase16:LocalResearch:TimeoutSeconds` (clamped to 10-90 seconds). Search and
model requests incur provider usage charges. Research runs within background pack
generation, not location updates, but can delay the pack becoming ready.

## Validation and Storage

- Only paragraphs containing usable web citation annotations are accepted.
- Source URLs must be public-looking HTTPS URLs, without IP literals or credentials.
- The classifier must identify a locality phrase present in the cited paragraph.
- A subject must be within 1,000 meters of a route segment anchor.
- Events require supported start/end dates, must not have ended, and must start
  within the next seven days. Undated event suggestions are discarded.
- Historical and cultural research expires after six hours. Event research
  expires within 30 minutes or at its end, whichever comes first.
- Only coarse route anchors, area context, public place names, interests, and
  language are sent. User IDs and precise device GPS traces are not sent.
- Researched sources have unknown reuse permission and are online-only. They are
  excluded from durable story/audio downloads. Eligible stories in a mixed pack
  can still be downloaded.
- Source links are available through the story's source list in Flutter.

Citation and geographic checks are not independent verification of every fact.
Coordinates are model-classified, not independently geocoded. Sparse coverage,
model mistakes, unsupported sources, or timeouts can leave no accepted research
stories; existing sources remain available. There is no shared cross-user research
cache or semantic deduplication in this version. Refreshes can repeat research.

## Field Test

1. Restart the API through the local launcher and rebuild/reinstall Flutter.
2. Create a fresh walk so an older pack is not reused.
3. Wait for Route Stories to finish preparing. Inspect story sources and open a
   research citation to compare the narration with its source.
4. Walk through the route and confirm stories play between arrival announcements,
   without replaying completed stories or delaying navigation.
5. Check event dates and locality carefully. Record rejected/empty research warnings
   and total preparation time, especially on slower hotspot connections.

Automated fixtures cover invalid citations, geography, unsupported location
phrases, missing/invented event dates, provider failure, disabled research, and
mixed-pack offline filtering. Live source quality and device behavior still need
field validation.

## Provider References

- [Responses web search](https://developers.openai.com/api/docs/guides/tools-web-search)
- [Structured outputs](https://developers.openai.com/api/docs/guides/structured-outputs)
- [Flutter source-link launcher](https://pub.dev/packages/url_launcher)
