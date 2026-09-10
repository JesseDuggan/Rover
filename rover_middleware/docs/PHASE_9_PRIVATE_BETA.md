# Phase 9 Private Beta Hardening

Phase 9 adds beta-safe configuration, privacy-safe diagnostics, problem reporting, post-walk feedback, and stricter arrival/location guardrails.

## Environments

- Development: local debugging, development auth header allowed, simulation controls allowed in debug builds.
- Testing: automated tests, no paid provider calls.
- Beta: HTTPS endpoints, durable storage, server-side provider secrets, Mapbox routing/discovery configuration, ElevenLabs server configuration.
- Production: placeholder until launch approval.

## Beta API Endpoints

- `GET /api/beta/configuration`
- `GET /api/beta/diagnostics`
- `POST /api/beta/problem-reports`
- `POST /api/beta/crash-breadcrumbs`
- `POST /api/walks/{walkSessionId}/feedback`
- `GET /api/walks/{walkSessionId}/feedback/status`

Diagnostics and reports redact emails, provider keys, Mapbox tokens, and high-precision coordinates.

## Local Beta API Example

```powershell
cd "C:\Users\jesse\Documents\Codex\2026-08-27\create-a-new-production-quality-asp\SRC\rover_middleware"
$env:ASPNETCORE_ENVIRONMENT = "Development"
$env:ROVER_STORAGE_MODE = "InMemory"
$env:ElevenLabs__Enabled = "false"
dotnet run --project ".\Rover.Api\Rover.Api.csproj" --urls http://127.0.0.1:5080
```

## Beta Configuration Notes

For real private beta, use `ASPNETCORE_ENVIRONMENT=Beta` and provide required settings through environment variables or an approved secret store. Do not commit secrets.

Required beta settings include durable storage, Cognito authority/audience, allowed CORS origins, Mapbox directions token, and ElevenLabs API key/voice/model.

## Field-Test Route

Union Square/San Francisco deterministic demo content remains available for repeatable testing. Local outdoor testing can use the tester's selected starting area with Mapbox Search local discovery and Mapbox walking Directions when configured. If reliable live local content is unavailable, Rover falls back to the deterministic local field-test route and records the limitation in field-test notes.

For Perth, Ontario field testing, start the API with live discovery and road-snapped walking routes:

```powershell
cd "C:\Users\jesse\Documents\Codex\2026-08-27\create-a-new-production-quality-asp\SRC\rover_middleware"
$env:ROVER_STORAGE_MODE = "InMemory"
$env:ROVER_ROUTING_MODE = "Mapbox"
$env:ROVER_LOCAL_DISCOVERY_MODE = "Mapbox"
$env:MAPBOX_DIRECTIONS_TOKEN = "REPLACE_WITH_SERVER_SIDE_MAPBOX_TOKEN"
$env:MAPBOX_SEARCH_TOKEN = "REPLACE_WITH_SERVER_SIDE_MAPBOX_TOKEN"
$env:ElevenLabs__Enabled = "true"
$env:ElevenLabs__ApiKey = "REPLACE_WITH_LOCAL_SECRET"
$env:ElevenLabs__VoiceId = "REPLACE_WITH_VOICE_ID"
$env:ElevenLabs__ModelId = "eleven_multilingual_v2"
dotnet run --project ".\Rover.Api\Rover.Api.csproj" --urls http://127.0.0.1:5080
```

The Mapbox token remains server-side for middleware routing/search. Flutter still uses only `MAPBOX_PUBLIC_TOKEN` for rendering the basemap.
