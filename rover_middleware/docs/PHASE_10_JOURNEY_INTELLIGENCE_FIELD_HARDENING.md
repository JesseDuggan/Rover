# Rover Phase 10 - Journey Intelligence and Field Hardening

Phase 10 strengthens the existing Phase 4-9 foundation without starting Quests or full turn-by-turn spoken navigation.

## What Changed

- Walk responses now include `routeQuality` diagnostics with:
  - route distance
  - walking minutes
  - stop minutes
  - total estimated experience minutes
  - requested-time utilization
  - backtracking estimate
  - repeated segment count
  - return-to-start estimate
  - warnings suitable for debug and field reports
- Walk responses now include `lifecycleConsistency` diagnostics with:
  - stop count
  - active route revision
  - next stop id
  - consistency flag
  - warnings for duplicate stops, broken sequencing, missing arrival radii, route geometry issues, or route revision mismatch
- Add-discovery route options recover politely when no addable live POI is available. The API returns an unchanged proposal instead of surfacing a hard lifecycle conflict.
- A new route-aware journey narration endpoint is available:
  - `POST /api/walks/{walkSessionId}/journey-narration/evaluate`
  - It can return approaching-stop narration, verified local-history/context narration, weather/time context, or a quiet decision.
  - It does not generate full turn-by-turn navigation instructions.
- Flutter models can parse the new route-quality, lifecycle, and journey-narration contracts.
- Flutter now schedules journey narration from active walk session updates using time, movement, route revision, audio state, distance-to-stop, and cooldown gates rather than calling the API for every GPS reading.
- Flutter audio playback now gives arrival narration priority over contextual journey narration, suppresses duplicate journey facts, and records stale journey jobs when route revisions change before playback.
- Add-discovery route insertion now scores candidate routes with route quality inputs, including estimated experience-time utilization, backtracking, terminal distance, route duration, and route distance.
- Recoverable lifecycle issues are repaired after accepted adaptations when it is safe to do so, including stale arrival-candidate state, non-consecutive stop sequence numbers, and missing route geometry rebuilt from ordered stops.
- The debug performance panel now includes the last journey-narration decision, priority, fact ids, latency, cooldown/stale-job state, route-quality summary, and lifecycle summary.

## Safety Boundaries

- No new external providers were added.
- No secrets are stored in Flutter.
- No full spoken turn-by-turn navigation was added.
- No Quest behavior was added.
- Arrival detection remains ordered: only the next unvisited stop should be evaluated for arrival.

## Field Test Checklist

1. Start Rover.Api with the existing `.env.local` configuration.
2. Confirm `/api/beta/diagnostics` reports Mapbox, local discovery, OpenAI, and ElevenLabs in the expected modes.
3. Launch the Flutter app on Samsung.
4. Create a live ROAM from device location.
5. Confirm the Mapbox basemap, stop markers, route line, and geofences render.
6. Confirm route-option buttons only show counts when samples are available.
7. Tap Coffee, Tea, Cakes, Burgers, and Sites where available.
8. Confirm each option sheet shows named places and that unavailable choices are disabled or recover politely.
9. Add a live POI and confirm the app reports that the place was added to the walk and map.
10. Walk toward stops and confirm only the next ordered stop can trigger arrival.
11. Confirm arrival voice uses ElevenLabs when the API reports `X-Rover-Speech-Provider: ElevenLabs`.
12. Try "Tell Me Nearby" between stops and confirm it uses verified nearby facts when available.
13. Watch the performance panel for:
    - speech render latency
    - location-context latency
    - local-discovery option latency
    - route adaptation latency
    - last journey-narration decision, priority, fact ids, and playback status
    - route-quality utilization and backtracking
    - lifecycle consistency warnings
14. Record any route-quality warnings, especially:
    - low requested-time utilization
    - backtracking
    - repeated segments
    - final stop too far from start
15. Field-test journey narration:
    - confirm contextual narration does not play when arrival is imminent
    - confirm arrival narration interrupts or supersedes contextual narration
    - confirm "Tell Me Nearby" remains user-priority audio
    - confirm the same fact is not repeated after the walk progresses
    - confirm route changes suppress stale queued narration

## Samsung Field Test Matrix

| Scenario | Setup | Expected Result | Evidence To Capture |
| --- | --- | --- | --- |
| Startup configuration | API running with `.env.local`, Samsung `adb reverse tcp:5080 tcp:5080` | Diagnostics show Mapbox, local discovery, OpenAI, and ElevenLabs configured | `/api/beta/diagnostics` plus app health |
| Live route creation | Create ROAM from device location | Mapbox basemap, route line, geofences, numbered stops render | Screenshot of map and route preview |
| Route options preload | Open Active ROAM near current location | Coffee/Tea/Cakes/Burgers/Sites show counts only when selectable samples exist | Screenshot of route-options panel |
| Route option add | Select a live POI and tap Add to Walk | Snackbar confirms the place was added; itinerary, map marker, geofence, and route revision update together | Screenshot of snackbar, itinerary, map |
| Stale adaptation recovery | Tap route option after route revision changes | App refreshes or shows a polite retry message without corrupting route state | Performance panel and visible error text |
| Contextual narration | Walk at least 80 m or wait two minutes away from arrival radius | Approved journey narration plays through ElevenLabs or device fallback | Performance panel narration row and voice provider row |
| Arrival priority | Enter next-stop geofence while other contextual audio could play | Arrival narration wins; no long story plays right before arrival | Caption text, voice provider row, arrival panel |
| Duplicate suppression | Continue walking after a nearby fact played | Same fact id is not repeated | Performance panel fact id row |
| Route quality | Add, skip, extend, and return options | Candidate route avoids unnecessary backtracking where viable; limitations appear in warnings | Route-quality row before and after action |
| Lifecycle consistency | Accept add/skip/extend options | Stops, order, map, geofences, itinerary, arrival state, narration state remain synchronized | Lifecycle row and map/itinerary screenshots |

## Useful API Checks

```powershell
Invoke-RestMethod "http://127.0.0.1:5080/health"
Invoke-RestMethod "http://127.0.0.1:5080/api/beta/diagnostics"
Invoke-RestMethod "http://127.0.0.1:5080/api/beta/local-discovery-options?latitude=44.678&longitude=-76.395"
```

## Notes For Phase 10.5

- The existing route `maneuvers` are preserved for future spoken navigation work.
- The Phase 10 journey narration scheduler is intentionally not full spoken turn-by-turn navigation.
- Route optimization now scores add-discovery candidates, but full whole-route rebalancing for long walks is still a future hardening item.
