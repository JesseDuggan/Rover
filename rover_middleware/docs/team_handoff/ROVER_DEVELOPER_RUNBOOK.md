# ROVER Developer Runbook

Date: 2026-08-30

## Prerequisites

- Windows PowerShell
- .NET 10 SDK on `PATH`
- Flutter SDK on `PATH`
- Android SDK platform tools on `PATH`, or available at:

```text
C:\Users\jesse\AppData\Local\Android\Sdk\platform-tools\adb.exe
```

- Samsung test device:

```text
RFGYA0RB5HY
```

## Important Paths

Middleware:

```powershell
cd "C:\Users\jesse\Documents\Codex\2026-08-27\create-a-new-production-quality-asp\SRC\rover_middleware"
```

Flutter:

```powershell
cd "C:\Users\jesse\Documents\Codex\2026-08-27\create-a-new-production-quality-asp\SRC\rover_flutter"
```

## Local Environment File

The middleware can load local developer settings from:

```text
SRC\rover_middleware\.env.local
```

This file must remain local and must not be committed.

Expected categories of settings:

```text
ROVER_STORAGE_MODE
ROVER_ROUTING_MODE
ROVER_DISCOVERY_MODE
ROVER_LOCAL_DISCOVERY_MODE
ROVER_CONVERSATION_MODE
MAPBOX_DIRECTIONS_TOKEN
MAPBOX_SEARCH_TOKEN
OPENAI_API_KEY
OPENAI_MODEL
ElevenLabs__Enabled
ElevenLabs__ApiKey
ElevenLabs__VoiceId
ElevenLabs__ModelId
ElevenLabs__OutputFormat
ROVER_LOCATION_PROVIDER_MAPBOX_ENABLED
ROVER_LOCATION_PROVIDER_WIKIPEDIA_ENABLED
ROVER_LOCATION_PROVIDER_WIKIDATA_ENABLED
ROVER_LOCATION_PROVIDER_OPENSTREETMAP_ENABLED
ROVER_LOCATION_PROVIDER_WEATHER_ENABLED
```

Use real values locally. Do not paste secrets into documentation, code, issue comments, screenshots, or chat logs.

## Start Rover.Api

Recommended:

```powershell
cd "C:\Users\jesse\Documents\Codex\2026-08-27\create-a-new-production-quality-asp\SRC\rover_middleware"
```

```powershell
.\run_rover_api.ps1
```

Manual fallback:

```powershell
cd "C:\Users\jesse\Documents\Codex\2026-08-27\create-a-new-production-quality-asp\SRC\rover_middleware"
```

```powershell
dotnet run --project ".\Rover.Api\Rover.Api.csproj" --urls http://127.0.0.1:5080
```

Health check from a second PowerShell window:

```powershell
Invoke-RestMethod "http://127.0.0.1:5080/health"
```

Diagnostics:

```powershell
Invoke-RestMethod "http://127.0.0.1:5080/api/beta/diagnostics"
```

Expected live-provider diagnostic values during field testing:

```text
mapboxConfigured: True
elevenLabsEnabled: True
elevenLabsConfigured: True
routingMode: Mapbox
localDiscoveryMode: Mapbox
conversationMode: OpenAI
```

## Build And Test Middleware

```powershell
cd "C:\Users\jesse\Documents\Codex\2026-08-27\create-a-new-production-quality-asp\SRC\rover_middleware"
```

```powershell
dotnet restore ".\Rover.sln"
```

```powershell
dotnet build ".\Rover.sln" --no-restore
```

```powershell
dotnet test ".\Rover.sln" --no-restore
```

Latest known result:

```text
67 passed, 0 failed, 67 total
```

## Configure Samsung Port Forwarding

Run this while Rover.Api is running locally:

```powershell
& "C:\Users\jesse\AppData\Local\Android\Sdk\platform-tools\adb.exe" devices
```

```powershell
& "C:\Users\jesse\AppData\Local\Android\Sdk\platform-tools\adb.exe" -s RFGYA0RB5HY reverse tcp:5080 tcp:5080
```

The Flutter app should use:

```text
http://127.0.0.1:5080
```

because `adb reverse` maps device localhost back to the developer machine.

## Launch Flutter On Samsung

```powershell
cd "C:\Users\jesse\Documents\Codex\2026-08-27\create-a-new-production-quality-asp\SRC\rover_flutter"
```

```powershell
flutter run -d RFGYA0RB5HY --dart-define=ROVER_API_BASE_URL=http://127.0.0.1:5080 --dart-define=ROVER_DEV_USER=voice-dev --dart-define=MAPBOX_PUBLIC_TOKEN=$env:MAPBOX_PUBLIC_TOKEN
```

If multiple devices are connected, keep `-d RFGYA0RB5HY`.

If the app reports that the API cannot be reached:

1. Confirm Rover.Api is still running.
2. Run:

```powershell
Invoke-RestMethod "http://127.0.0.1:5080/health"
```

3. Re-run:

```powershell
& "C:\Users\jesse\AppData\Local\Android\Sdk\platform-tools\adb.exe" -s RFGYA0RB5HY reverse tcp:5080 tcp:5080
```

4. Relaunch Flutter with the same `ROVER_API_BASE_URL`.

## Provider Smoke Tests

Mapbox routing and discovery:

```powershell
Invoke-RestMethod "http://127.0.0.1:5080/api/beta/mapbox-smoke-test?latitude=44.678&longitude=-76.395"
```

Local discovery options:

```powershell
Invoke-RestMethod "http://127.0.0.1:5080/api/beta/local-discovery-options?latitude=44.678&longitude=-76.395"
```

Location Intelligence:

```powershell
Invoke-RestMethod "http://127.0.0.1:5080/api/location-context?lat=44.678&lng=-76.395&radiusMeters=1500"
```

Story synthesis:

```powershell
Invoke-RestMethod -Method Post -Uri "http://127.0.0.1:5080/api/location-story" -ContentType "application/json" -Body '{
  "latitude": 44.678,
  "longitude": -76.395,
  "radiusMeters": 1500,
  "interests": ["history", "coffee"],
  "selectedPlaceIds": [],
  "narrationStyle": "short-spoken"
}'
```

ElevenLabs speech:

```powershell
Invoke-WebRequest -Method Post -Uri "http://127.0.0.1:5080/api/speech/render" -Headers @{ "X-Rover-Dev-User" = "voice-dev"; "Accept" = "audio/mpeg" } -ContentType "application/json" -Body '{"text":"Welcome to Rover premium voice.","purpose":"WalkIntroduction","locale":"en-US"}' -OutFile ".\work\voice-test.mp3"
```

Check provider headers:

```powershell
$response = Invoke-WebRequest -Method Post -Uri "http://127.0.0.1:5080/api/speech/render" -Headers @{ "X-Rover-Dev-User" = "voice-dev"; "Accept" = "audio/mpeg" } -ContentType "application/json" -Body '{"text":"Testing Rover premium voice.","purpose":"WalkIntroduction","locale":"en-US"}"
$response.Headers
```

Expected:

```text
X-Rover-Speech-Provider: ElevenLabs
X-Rover-Speech-Fallback: false
```

## Common Troubleshooting

### API Connection Issue In Flutter

Most common causes:

- Rover.Api was stopped.
- `adb reverse` was not set after reconnecting the phone.
- Flutter was launched with the wrong `ROVER_API_BASE_URL`.
- Windows firewall or local network state changed.

### Mapbox Basemap Blank

Check:

- Flutter launched with `--dart-define=MAPBOX_PUBLIC_TOKEN=$env:MAPBOX_PUBLIC_TOKEN`.
- Token begins with `pk.`.
- Android manifest includes Internet permission.
- API diagnostics showing `mapboxConfigured` only checks server-side Mapbox, not the Flutter basemap token.

### Mapbox Routing Error

If the app says Mapbox routing requires `MAPBOX_DIRECTIONS_TOKEN`, the server-side API environment is missing the routing token. Restart Rover.Api after fixing `.env.local`.

### ElevenLabs Falls Back To Device Voice

Check:

- `ElevenLabs__Enabled=true`
- `ElevenLabs__ApiKey` present
- `ElevenLabs__VoiceId` present
- API diagnostics show `elevenLabsEnabled=True` and `elevenLabsConfigured=True`
- `/api/speech/render` returns `X-Rover-Speech-Provider: ElevenLabs`

### Route Option Buttons Show Counts But Cannot Add

This was hardened in Phase 10. Counts should represent selectable samples. If a selected option still cannot be added, the API should return an unchanged proposal with a polite explanation rather than a hard failure.

### Flutter CLI Hangs

During the last Phase 10 pass, `dart format`, `flutter analyze`, focused `flutter test`, and `flutter build apk --debug` hung silently in the Codex local environment. Treat this as a local tooling issue until reproduced in a clean terminal or CI runner.

## Useful Field-Test Locations

Westport/Perth/Kingston, Ontario were used during field testing. Rural locations may produce sparse story results. City locations expose geofence overlap and route optimization issues more clearly.
