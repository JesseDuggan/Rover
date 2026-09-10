# ROVER Field Test Guide

Date: 2026-08-30

## Goal

Validate the live Rover experience on a physical Android device using real location, Mapbox map/routing/POI data, Location Intelligence, OpenAI story synthesis, and ElevenLabs premium voice.

## Before Leaving

Start Rover.Api:

```powershell
cd "C:\Users\jesse\Documents\Codex\2026-08-27\create-a-new-production-quality-asp\SRC\rover_middleware"
```

```powershell
.\run_rover_api.ps1
```

In a second PowerShell window:

```powershell
Invoke-RestMethod "http://127.0.0.1:5080/health"
```

Check provider status:

```powershell
Invoke-RestMethod "http://127.0.0.1:5080/api/beta/diagnostics"
```

Expected:

```text
apiHealth: Healthy
mapboxConfigured: True
elevenLabsEnabled: True
elevenLabsConfigured: True
routingMode: Mapbox
localDiscoveryMode: Mapbox
conversationMode: OpenAI
```

Connect Samsung:

```powershell
& "C:\Users\jesse\AppData\Local\Android\Sdk\platform-tools\adb.exe" devices
```

```powershell
& "C:\Users\jesse\AppData\Local\Android\Sdk\platform-tools\adb.exe" -s RFGYA0RB5HY reverse tcp:5080 tcp:5080
```

Launch Flutter:

```powershell
cd "C:\Users\jesse\Documents\Codex\2026-08-27\create-a-new-production-quality-asp\SRC\rover_flutter"
```

```powershell
flutter run -d RFGYA0RB5HY --dart-define=ROVER_API_BASE_URL=http://127.0.0.1:5080 --dart-define=ROVER_DEV_USER=voice-dev --dart-define=MAPBOX_PUBLIC_TOKEN=$env:MAPBOX_PUBLIC_TOKEN
```

## Smoke Test

1. Open Rover on Samsung.
2. Use device location.
3. Create a live ROAM.
4. Confirm the map loads.
5. Confirm route line appears.
6. Confirm markers and geofences appear.
7. Start the walk.
8. Confirm Live GPS is active.
9. Tap Tell Me Nearby.
10. Confirm premium voice plays when context is available.

## Route Options Test

For each available option:

- Coffee
- Tea
- Cakes
- Burgers
- Sites

Check:

1. Button count appears only when named options are loaded.
2. Disabled categories are visibly disabled.
3. Tapping a category opens a list of named places.
4. Place details include what is available:
   - name
   - category
   - distance
   - address
   - phone
   - website
   - menu URL
5. Add one place to the walk.
6. Confirm the app says the place was added to the walk and map.
7. Confirm itinerary updates.
8. Confirm a marker/geofence appears for the added place.

## Arrival Test

Walk toward the next ordered stop.

Record:

- GPS accuracy
- distance to next stop
- arrival radius
- whether arrival triggered
- whether premium voice played
- whether the arrival was too early, late, or accurate

Expected:

- Only the next ordered stop should trigger arrival.
- The app should not arrive at multiple stops from one reading.
- Arrival narration should play through ElevenLabs when premium voice is available.
- If GPS accuracy is poor, arrival should avoid false positives.

## Tell Me Nearby Test

Try this in three contexts:

1. Rural/low-density area.
2. Village/small-town main street.
3. City/downtown area.

Expected:

- In sparse areas, Rover should recover politely.
- In towns/cities, Rover should use verified nearby facts when available.
- Response should not say it lacks context when API location context has ranked places with usable facts.
- Voice should use ElevenLabs if configured and reachable.

## Performance Panel

Watch for slow entries:

- `POST /api/speech/render`
- `GET /api/location-context`
- `GET /api/beta/local-discovery-options`
- `POST /api/walks/{walkId}/adaptations/evaluate`
- map annotation redraws

Record:

- operation name
- latency
- whether it succeeded
- user-visible impact

## Route Quality Field Notes

For each walk, note:

- requested walk length
- actual generated estimated duration
- estimated walking time
- estimated stop time
- whether the route doubled back
- whether the final stop felt too far from the start
- whether the route felt efficient
- whether any POI felt low-value or out of the way

## Failure Recovery Expectations

API stopped:

- App should show a clear connection issue.
- Restart API and re-run `adb reverse`.

No POIs:

- Category buttons should disable or show no count.
- App should not pretend an option can be added.

No story content:

- Rover should say a short polite fallback only when there are genuinely no verified facts.

Voice provider unavailable:

- App may fall back to device voice.
- Performance/API headers should show fallback reason.

Mapbox issue:

- Map should show an understandable connection/configuration message.
- Token values must never be printed.

## What To Send Back To Engineering

For each issue:

- city/location name
- approximate coordinate if safe to share
- walk duration requested
- route option selected
- what the app displayed
- what voice said
- performance panel text
- API diagnostics output with secrets removed
- screenshot or screen recording
- whether API and adb reverse were running
