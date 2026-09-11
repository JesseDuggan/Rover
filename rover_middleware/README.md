# Rover Middleware

## Wireless private-LAN development

To run the API for a Samsung phone or watch on the same private Wi-Fi network:

```powershell
.\run-rover-api-lan.ps1
```

This Development-only launcher detects a private laptop IPv4 address, listens on `http://0.0.0.0:5080`, and prints the `/health` URL to open on the device. It does not modify Windows Firewall or router settings. For Windows Mobile Hotspot or a laptop with multiple active adapters, pass the address reported by `ipconfig`:

```powershell
.\run-rover-api-lan.ps1 -LanIp <LAPTOP_PRIVATE_IPV4>
```

Keep TCP 5080 restricted to the Windows Private firewall profile. Flutter setup and troubleshooting are documented in `..\rover_flutter\docs\WIRELESS_LAN_DEVELOPMENT.md`.

ASP.NET Core middleware for the Rover Flutter application.

## Railway Beta Deployment

The API startup project is `Rover.Api/Rover.Api.csproj` targeting `.NET 10` (`net10.0`). Railway builds the multi-stage `Dockerfile`, runs `dotnet Rover.Api.dll`, and the application binds to `http://0.0.0.0:$PORT` when Railway supplies `PORT`.

`GET /health` is public and returns only service status and version. All `/api/*` beta requests require `X-Rover-Beta-Key: <ROVER_BETA_API_KEY>` or `Authorization: Bearer <ROVER_BETA_API_KEY>`. Swagger is only mapped in Development.

Railway setup from GitHub:

1. Push this repository to GitHub.
2. In Railway, create a new project from the GitHub repository.
3. Set the service root directory to `rover_middleware`.
4. Confirm Railway detects `railway.toml` and the `Dockerfile`.
5. Add the required variables below. Do not paste values into source files.
6. Deploy, then confirm `https://<railway-domain>/health` returns `{"status":"Healthy","version":"..."}`.
7. Add the Railway HTTPS origin to Flutter beta build settings and to `Rover__Cors__AllowedOrigins` if a web client is used.

Required Railway variables:

```text
ASPNETCORE_ENVIRONMENT=Beta
ROVER_BETA_API_KEY
Rover__Cors__AllowedOrigins
GOOGLE_ROUTES_API_KEY
GOOGLE_PLACES_API_KEY
ElevenLabs__ApiKey
ElevenLabs__VoiceId
ElevenLabs__ModelId
ElevenLabs__Enabled=true
```

Provider and feature variables used when those modes are enabled:

```text
OPENAI_API_KEY
OPENAI_MODEL
OPENAI_ORGANIZATION
OPENAI_PROJECT
OPENAI_WEB_SEARCH_ENABLED
MAPBOX_DIRECTIONS_TOKEN
MAPBOX_SEARCH_TOKEN
MAPBOX_PUBLIC_TOKEN
OPENWEATHER_API_KEY
GOOGLE_WEATHER_API_KEY
TICKETMASTER_DISCOVERY_API_KEY
ROVER_ROUTING_MODE
ROVER_LOCAL_DISCOVERY_MODE
ROVER_DISCOVERY_MODE
ROVER_CONVERSATION_MODE
ROVER_LOCATION_STORY_OPENAI_ENABLED
ROVER_LOCATION_STORAGE_ENABLED
ROVER_LOCATION_STORAGE_DIRECTORY
ROVER_LOCATION_PROVIDER_MAPBOX_ENABLED
ROVER_LOCATION_PROVIDER_WIKIPEDIA_ENABLED
ROVER_LOCATION_PROVIDER_WIKIDATA_ENABLED
ROVER_LOCATION_PROVIDER_GOOGLEPLACES_ENABLED
ROVER_LOCATION_PROVIDER_OPENSTREETMAP_ENABLED
ROVER_LOCATION_PROVIDER_WEATHER_ENABLED
ROVER_PHASE15_ENABLED
ROVER_PHASE15_LIVE_WEATHER_ENABLED
ROVER_PHASE15_EVENTS_ENABLED
ROVER_PHASE15_CURRENT_INFO_ENABLED
ROVER_PHASE16_ENABLED
ROVER_AUDIO_CACHE_RETENTION_HOURS
```

Database decision: the current beta code stores walk sessions, accounts, feedback, diagnostics, and speech usage in memory. Story packs and generated audio can use local files under `work/`. The repository includes PostgreSQL/PostGIS schema scaffolding, but `PostgreSqlProfileRepository` is still a clear-fail placeholder until EF Core/Npgsql packages and migrations are implemented. For Railway beta, keep `ROVER_STORAGE_MODE=InMemory` unless a persistent Railway volume is mounted for `work/`; expect data loss on redeploy/restart. Before production, implement the PostgreSQL repository and set `ROVER_STORAGE_MODE=PostgreSql` plus `DATABASE_URL` or `ROVER_POSTGRES_CONNECTION_STRING`, then migrate existing local JSON/audio data without deleting it.

## Phase 2 Scope

Phase 2 adds a locally testable walking-tour session API backed by deterministic mock data. It supports creating a Union Square, San Francisco walk; starting it; visiting ordered stops; retrieving the next stop; completing or cancelling the walk; and viewing the lifecycle through Swagger.

No Flutter code is modified by this middleware project.

## Architecture

- `Rover.Api`: ASP.NET Core Web API endpoints, API request/response contracts, validation, ProblemDetails responses, and development Swagger/OpenAPI.
- `Rover.Application`: walk-session use cases, async service interfaces, planner/repository abstractions, and orchestration.
- `Rover.Domain`: walk aggregate, stop model, lifecycle rules, statuses, walking pace, accessibility, and content classification.
- `Rover.Infrastructure`: deterministic `MockWalkPlanner` and thread-safe in-memory walk-session repository.
- `Rover.Tests`: package-free executable test harness run through `dotnet test`.

## Prerequisites

- Stable .NET 10 SDK installed and available as `dotnet` in Windows PowerShell.

## Windows PowerShell Commands

Run these from the repository root:

```powershell
cd SRC\rover_middleware
dotnet restore .\Rover.sln
dotnet build .\Rover.sln --configuration Release
dotnet test .\Rover.sln --configuration Release --no-build
dotnet run --project .\Rover.Api\Rover.Api.csproj --launch-profile http --configuration Release
```

## Local Environment File

For local field testing, copy `.env.example` to `.env.local` and put your local-only tokens there. `.env.local` is ignored by git. The API loads `.env.local` automatically when started from the middleware folder, and the helper script also loads it before running the API. Do not leave placeholder token values in `.env.local`; Mapbox/OpenAI/ElevenLabs modes need real provider credentials.

Start the API with the local environment file:

```powershell
cd "C:\Users\jesse\Documents\Codex\2026-08-27\create-a-new-production-quality-asp\SRC\rover_middleware"
.\run_rover_api.ps1
```

Use a different URL if needed:

```powershell
.\run_rover_api.ps1 -Urls "http://127.0.0.1:5080"
```

Do not commit `.env.local`, `run_rover_api.local.ps1`, API keys, or provider tokens.

## Local URLs

- API: http://localhost:5207
- Swagger: http://localhost:5207/swagger
- OpenAPI JSON: http://localhost:5207/swagger/v1/swagger.json
- Health: http://localhost:5207/health

The `https` launch profile also configures `https://localhost:7207` for environments with a trusted ASP.NET Core development certificate.

## Phase 3 Flutter Connectivity

Use the HTTP development URL for local Flutter testing:

```powershell
cd ..\rover_flutter
flutter run --debug --dart-define=ROVER_API_BASE_URL=http://10.0.2.2:5207
```

- Android emulator: `http://10.0.2.2:5207`
- Windows desktop: `http://localhost:5207`
- Physical Android device: `http://<computer-LAN-IP>:5207`

## Endpoints

- `GET /health`
- `POST /api/walks`
- `GET /api/walks/{walkSessionId}`
- `GET /api/walks/{walkSessionId}/stops`
- `GET /api/walks/{walkSessionId}/next-stop`
- `POST /api/walks/{walkSessionId}/start`
- `POST /api/walks/{walkSessionId}/stops/{stopId}/arrive`
- `POST /api/walks/{walkSessionId}/location`
- `POST /api/walks/{walkSessionId}/ask`
- `GET /api/location-context`
- `POST /api/location-story`
- `POST /api/walks/{walkSessionId}/adaptations/evaluate`
- `GET /api/walks/{walkSessionId}/adaptations/{adaptationId}`
- `POST /api/walks/{walkSessionId}/adaptations/{adaptationId}/accept`
- `POST /api/walks/{walkSessionId}/adaptations/{adaptationId}/reject`
- `POST /api/walks/{walkSessionId}/complete`
- `POST /api/walks/{walkSessionId}/cancel`

## Phase 4 Routing And Location

Phase 4 adds route metadata and foreground location-update handling while preserving the Phase 3 walk contract. `POST /api/walks` now includes a `route` object with ordered coordinates, GeoJSON `LineString`, bounds, route provider, generation timestamp, version, distance and duration. Route coordinates are documented and emitted in longitude/latitude order for GeoJSON and as explicit `longitude`/`latitude` fields for DTO consumers.

Routing mode is explicit:

```powershell
$env:ROVER_ROUTING_MODE = "Mock"
dotnet run --project .\Rover.Api\Rover.Api.csproj --urls http://localhost:5207
```

Mock mode is deterministic and uses the Union Square fixture. Mapbox mode uses the Mapbox Directions API walking profile and never falls back to mock mode:

```powershell
$env:ROVER_ROUTING_MODE = "Mapbox"
$env:MAPBOX_DIRECTIONS_TOKEN = "<server-side-token>"
dotnet run --project .\Rover.Api\Rover.Api.csproj --urls http://localhost:5207
```

Do not place Mapbox routing credentials in `appsettings.json` or source control. You may also use .NET user secrets for `Rover:Routing:Mapbox:AccessToken`.

Location updates are accepted only for `InProgress` walks:

```powershell
Invoke-RestMethod -Method Post -Uri "http://localhost:5207/api/walks/$($walk.walkSessionId)/location" -ContentType application/json -Body '{
  "latitude": 37.7880,
  "longitude": -122.4075,
  "accuracyMeters": 8,
  "headingDegrees": 90,
  "speedMetersPerSecond": 1.2,
  "recordedAtUtc": "2026-08-27T15:00:00Z"
}'
```

The response includes `distanceToNextStopMeters`, `routeProgressPercentage`, `estimatedMinutesRemaining`, `isOffRoute`, `distanceFromRouteMeters`, `arrivalCandidate` and `confirmedArrival`.

## Phase 6 Adaptive Routing And Discovery

Phase 6 adds confirmation-first adaptive route proposals. Supported types are `SkipStop`, `ShortenWalk`, `ExtendWalk`, `AddDiscovery`, `RejoinRoute`, `ReturnToStart`, and `ContinueUnchanged`.

Evaluation never changes the active route. Accepting a proposal requires the current `routeRevision`; stale, expired, completed, and cancelled walks return ProblemDetails. Accepted proposals preserve visited stops, update remaining stops, recalculate route geometry with the configured route provider, increment `routeRevision`, and record route revision history.

Evaluate a nearby discovery proposal:

```powershell
$proposal = Invoke-RestMethod -Method Post -Uri "http://localhost:5207/api/walks/$($walk.walkSessionId)/adaptations/evaluate" -ContentType application/json -Body '{
  "latitude": 37.7880,
  "longitude": -122.4075,
  "routeRevision": 1,
  "requestedType": "AddDiscovery",
  "interest": "coffee",
  "userRequest": "Find me coffee nearby",
  "dismissedDiscoveryIds": []
}'
```

Accept it:

```powershell
Invoke-RestMethod -Method Post -Uri "http://localhost:5207/api/walks/$($walk.walkSessionId)/adaptations/$($proposal.adaptationId)/accept" -ContentType application/json -Body (@{
  routeRevision = $walk.routeRevision
} | ConvertTo-Json)
```

Reject it:

```powershell
Invoke-RestMethod -Method Post -Uri "http://localhost:5207/api/walks/$($walk.walkSessionId)/adaptations/$($proposal.adaptationId)/reject"
```

The deterministic mock discovery catalog includes coffee, architecture, local history, public art, movie/pop-culture, scenic viewpoint, short local experience, and one sponsored walking-shop recommendation. Sponsored recommendations are labelled, disclosed, and never auto-applied.

## Location Intelligence Foundation

Location Intelligence gathers nearby facts in the Rover API, normalizes them, merges likely duplicate places, ranks story-worthy discoveries and produces safe narration from verified facts. Flutter does not call external location providers directly.

Endpoints:

- `GET /api/location-context?lat={lat}&lng={lng}&radiusMeters={radius}&routeId={optional}&profileId={optional}`
- `POST /api/location-story`

Providers are individually configurable:

- Mapbox Search for POIs and categories.
- Wikipedia Geosearch for nearby geotagged articles, canonical URLs, extracts, thumbnails and Wikidata identifiers.
- Wikidata geospatial SPARQL for structured entities.
- Google Places API (New) for nearby POI identity and OCR-assisted business lookup when an API key is configured.
- OpenStreetMap/Overpass for amenities, tourism, parks and historic tags.
- Weather/time context through OpenWeather when configured, otherwise local time context only.

Environment variables:

```powershell
$env:MAPBOX_SEARCH_TOKEN = "<mapbox-search-token>"
$env:GOOGLE_PLACES_API_KEY = "<google-places-key>"
$env:OPENWEATHER_API_KEY = "<openweather-key>"
$env:ROVER_LOCATION_STORY_OPENAI_ENABLED = "true"
$env:ROVER_LOCATION_STORAGE_ENABLED = "true"
$env:ROVER_LOCATION_STORAGE_DIRECTORY = "work/location-intelligence"
$env:OPENAI_API_KEY = "<openai-key>"
$env:OPENAI_MODEL = "gpt-5.4-mini"
```

Provider enable flags:

```powershell
$env:ROVER_LOCATION_PROVIDER_MAPBOX_ENABLED = "true"
$env:ROVER_LOCATION_PROVIDER_WIKIPEDIA_ENABLED = "true"
$env:ROVER_LOCATION_PROVIDER_WIKIDATA_ENABLED = "true"
$env:ROVER_LOCATION_PROVIDER_GOOGLEPLACES_ENABLED = "true"
$env:ROVER_LOCATION_PROVIDER_OPENSTREETMAP_ENABLED = "true"
$env:ROVER_LOCATION_PROVIDER_WEATHER_ENABLED = "true"
```

Configuration keys live under `Rover:LocationIntelligence`:

- `DefaultRadiusMeters`
- `MaxRadiusMeters`
- `MaximumReturnedPlaces`
- `ProviderTimeoutSeconds`
- `HistoricalCacheMinutes`
- `PoiCacheMinutes`
- `WeatherCacheMinutes`
- `GeneratedStoryCacheMinutes`
- `EvidenceFreshnessMinutes`
- `SpatialEvidenceFreshnessMinutes`
- `PersistentStorageEnabled`
- `PersistentStorageDirectory`
- `MaximumStoredStoryPacks`
- `MaximumStoredEvidenceSets`
- `MergeDistanceMeters`
- `RouteNearDistanceMeters`
- `Providers:{ProviderName}:Enabled`
- `Providers:{ProviderName}:Endpoint`
- `Providers:{ProviderName}:TimeoutSeconds`
- `Providers:{ProviderName}:CacheMinutes`
- `Providers:{ProviderName}:MaximumResults`

Example context request:

```powershell
Invoke-RestMethod "http://127.0.0.1:5080/api/location-context?lat=44.678&lng=-76.395&radiusMeters=1500"
```

Example story request:

```powershell
Invoke-RestMethod -Method Post -Uri "http://127.0.0.1:5080/api/location-story" -ContentType application/json -Body '{
  "latitude": 44.678,
  "longitude": -76.395,
  "radiusMeters": 1500,
  "interests": ["history", "coffee"],
  "selectedPlaceIds": [],
  "narrationStyle": "short-spoken"
}'
```

The response includes a backward-compatible `storyPack` with grounded
`CameraTeaser`, `Arrival`, and `Deeper` sections. Each factual sentence carries
evidence IDs internally. Sections include target and estimated duration,
completeness, availability, required attribution, freshness, and validation.
Supported audience styles include history, architecture, family, local,
business, outdoor, accessibility, and general traveller profiles. Profiles
change evidence emphasis and order only; unsupported topics remain explicitly
unavailable.

Attribution and licensing:

- Preserve and display provider attribution returned in `requiredAttribution` and source references.
- Mapbox content is subject to Mapbox service terms.
- OpenStreetMap data requires OpenStreetMap contributor attribution and ODbL awareness.
- Wikipedia content requires Wikipedia contributor attribution and CC BY-SA awareness.
- Wikidata facts are CC0, but Rover still preserves contributor attribution.
- Google Places records require Google Maps attribution plus any third-party attribution returned with the result.
- Google Places content is never placed in the provider or aggregate context cache. Only Google Place IDs may be persisted indefinitely.
- Google-derived POIs must not be rendered on the existing Mapbox map. Off-map Google content requires visible Google Maps attribution.
- Do not permanently store or redistribute provider content beyond each provider's terms.

Cache behavior:

- Business/POI context: several hours.
- Historical/Wikipedia/Wikidata/OSM context: one to several days.
- Weather context: about 20 minutes.
- Validated non-Google Story Packs and normalized evidence persist as bounded atomic JSON files under `work/location-intelligence` by default.
- Persistent keys separate place, profile, narration style, and interests without storing user coordinates in filenames.
- Short-lived user-relative distance and direction claims remain in memory and are removed from persisted packs.
- Expired, malformed, or grounding-invalid files are ignored and removed on read.
- Google Places content is never written to either persistent repository; a Google Place ID may remain on an otherwise non-Google canonical identity.

Resilience:

- Each provider has its own timeout and enabled flag.
- One provider failure returns a warning and does not fail the whole request.
- Google Places uses bounded Nearby Search and Text Search requests with explicit field masks and no content cache.
- Story Pack persistence failures do not interrupt live story generation.
- Overpass requests are cached and serialized per API host to avoid hammering public Overpass servers.
- Distance, route distance, detour estimate, direction, identity resolution and ranking are deterministic code, not AI.
- Shared provider IDs, especially Wikidata QIDs, are verified identity links. Similar names alone never merge common businesses.

Railway deployment:

- Set provider tokens and enable flags as Railway environment variables.
- Google Places remains disabled by default. Enable it only after the consuming Flutter surface displays required Google Maps attribution and excludes Google-derived content from Mapbox maps.
- Keep `ROVER_LOCATION_PROVIDER_OPENSTREETMAP_ENABLED` conservative in production unless caching is backed by persistent or distributed storage.
- Set a clear `Rover:LocationIntelligence:UserAgent` value with contact information before using public OSM/Overpass at scale.

Known limitations:

- Google Places photos, reviews, generative summaries and hotel-rate integrations are not requested by the current adapter.
- Provider data can be sparse in rural areas.
- Opening hours, accessibility, menus and weather are only returned when reliable provider fields exist.
- OpenAI story synthesis is optional and disabled by default; safe deterministic fallback narration is returned when disabled.
- Provider response caches remain process-local; validated non-Google Story Packs and evidence survive API restarts.

To add another provider later, implement `ILocationContextProvider`, normalize output to `LocationPlace` and `LocationFact`, preserve attribution/licensing, register it in DI, and add mocked tests for success, failure and attribution.

Configurable defaults:

- `Rover:Location:OffRouteDistanceMeters`: `65`
- `Rover:Location:ArrivalAccuracyPaddingMeters`: `8`
- `Rover:Location:RequiredArrivalReadings`: `2`
- `Rover:Location:RequiredOffRouteReadings`: `2`
- `Rover:Location:StaleReadingSeconds`: `120`
- `Rover:Location:MaximumAccuracyMeters`: `100`

Mapbox walking routes are not guaranteed to be wheelchair accessible and may not fully represent stairs, hills, temporary closures or restricted paths. Rover preserves accessibility preferences in the domain state but does not claim verified accessible routing without provider support.

## Phase 7 Profiles, History And Persistence

Phase 7 adds privacy-conscious guest profile APIs, user preferences, saved discoveries and controlled learning. The default storage mode remains explicit in-memory storage for local demos and tests. PostgreSQL/PostGIS scaffolding is included for persistent storage, but the compiled EF Core/Npgsql repository requires NuGet package restore before enabling PostgreSQL mode.

Profile endpoints:

- `POST /api/profiles/guest`
- `GET /api/profiles/{profileId}`
- `PATCH /api/profiles/{profileId}/preferences`
- `POST /api/profiles/{profileId}/saved-discoveries`
- `DELETE /api/profiles/{profileId}/saved-discoveries/{discoveryId}`
- `POST /api/profiles/{profileId}/preference-signals`
- `DELETE /api/profiles/{profileId}/learned-preferences/{topic}`
- `POST /api/profiles/{profileId}/learned-preferences/reset`
- `DELETE /api/profiles/{profileId}`

Run the API with in-memory Phase 7 storage:

```powershell
$env:ROVER_STORAGE_MODE = "InMemory"
dotnet run --project .\Rover.Api\Rover.Api.csproj --urls http://127.0.0.1:5080
```

Start the local PostgreSQL/PostGIS container:

```powershell
$env:ROVER_POSTGRES_PASSWORD = "choose-a-local-password"
docker compose up -d
```

Install EF Core/Npgsql packages once NuGet connectivity is working:

```powershell
dotnet add .\Rover.Infrastructure\Rover.Infrastructure.csproj package Microsoft.EntityFrameworkCore
dotnet add .\Rover.Infrastructure\Rover.Infrastructure.csproj package Microsoft.EntityFrameworkCore.Design
dotnet add .\Rover.Infrastructure\Rover.Infrastructure.csproj package Npgsql.EntityFrameworkCore.PostgreSQL
dotnet add .\Rover.Infrastructure\Rover.Infrastructure.csproj package Npgsql.EntityFrameworkCore.PostgreSQL.NetTopologySuite
```

PostgreSQL mode is intentionally not a silent fallback. If `ROVER_STORAGE_MODE` is set to `PostgreSql` before EF/Npgsql support is restored, startup/profile access fails clearly instead of losing data in memory.

## Phase 8 Private Beta Readiness

Phase 8 adds the local foundations for secure accounts, ownership checks, audit events, account export/deletion controls, Cognito staging configuration, Terraform staging infrastructure, container build support and CI preparation. Cognito remains the staging identity target; local development uses an explicit Development-only identity header so tests can exercise authorization without live AWS services.

Run Rover locally with Development authentication:

```powershell
cd "C:\Users\jesse\Documents\Codex\2026-08-27\create-a-new-production-quality-asp\SRC\rover_middleware"
```

```powershell
$env:ROVER_STORAGE_MODE = "InMemory"
```

```powershell
dotnet run --project ".\Rover.Api\Rover.Api.csproj" --urls http://127.0.0.1:5080
```

Create a Development account:

```powershell
Invoke-RestMethod -Method Post -Uri "http://127.0.0.1:5080/api/auth/development/session" -ContentType "application/json" -Body '{"subject":"jesse-dev","email":"jesse@example.test"}'
```

Use the Development identity header:

```powershell
Invoke-RestMethod -Method Get -Uri "http://127.0.0.1:5080/api/accounts/me" -Headers @{ "X-Rover-Dev-User" = "jesse-dev" }
```

Samsung testing:

```powershell
adb -s RFGYA0RB5HY reverse tcp:5080 tcp:5080
```

Terraform staging plan:

```powershell
cd "C:\Users\jesse\Documents\Codex\2026-08-27\create-a-new-production-quality-asp\SRC\rover_middleware\infra\terraform"
```

```powershell
terraform init
terraform plan -var='allowed_origins=["https://staging.myrover.ai"]' -var='container_image=replace-with-ecr-uri'
```

Container build:

```powershell
cd "C:\Users\jesse\Documents\Codex\2026-08-27\create-a-new-production-quality-asp\SRC\rover_middleware"
```

```powershell
docker build -t rover-api:phase8 .
```

Android App Bundle:

```powershell
cd "C:\Users\jesse\Documents\Codex\2026-08-27\create-a-new-production-quality-asp\SRC\rover_flutter"
```

```powershell
flutter build appbundle --release --dart-define=ROVER_API_BASE_URL=https://staging-api.example.com --dart-define=MAPBOX_PUBLIC_TOKEN=$env:MAPBOX_PUBLIC_TOKEN
```

See `docs\PHASE_8_PRIVATE_BETA.md` and `..\rover_flutter\docs\ANDROID_PRIVATE_BETA.md` for Cognito, staging, rollback, signing and beta-testing details.

## Phase 8.5 ElevenLabs Premium Rover Voice

Phase 8.5 adds server-side premium speech generation behind `IRoverSpeechService`, `ITextToSpeechProvider`, `IGeneratedAudioCache`, and `ISpeechUsageService`. ElevenLabs credentials stay only in middleware environment variables or approved AWS secret storage. Flutter receives rendered audio bytes and never receives the API key.

Render speech:

```powershell
Invoke-WebRequest -Method Post -Uri "http://127.0.0.1:5080/api/speech/render" -Headers @{ "X-Rover-Dev-User" = "voice-dev"; "Accept" = "audio/mpeg" } -ContentType "application/json" -Body '{"text":"Welcome to Rover premium voice.","purpose":"WalkIntroduction","locale":"en-US"}' -OutFile ".\work\voice-test.mp3"
```

Configure ElevenLabs locally:

```powershell
$env:ElevenLabs__Enabled = "true"
```

```powershell
$env:ElevenLabs__ApiKey = "REPLACE_WITH_LOCAL_SECRET"
```

```powershell
$env:ElevenLabs__VoiceId = "REPLACE_WITH_VOICE_ID"
```

```powershell
$env:ElevenLabs__ModelId = "REPLACE_WITH_MODEL_ID"
```

See `docs\PHASE_8_5_ELEVENLABS_VOICE.md` for key rotation, usage limits, fallback testing and Samsung voice test steps.

## Lifecycle Rules

- A successfully planned walk becomes `Ready`.
- Only a `Ready` walk can be started.
- Stop arrival is allowed only while `InProgress`.
- Stops must be arrived at in sequence.
- `next-stop` returns the next unvisited stop, or `null` when all stops are visited.
- Completing a walk requires `InProgress` status and all stops visited.
- `Completed` and `Cancelled` walks cannot be restarted.
- Invalid transitions return ProblemDetails with HTTP `409`.
- Unknown walks and stops return HTTP `404`.

## Example Requests

Create a Union Square walk:

```powershell
$walk = Invoke-RestMethod -Method Post -Uri http://localhost:5207/api/walks -ContentType application/json -Body '{
  "latitude": 37.7880,
  "longitude": -122.4075,
  "availableMinutes": 60,
  "interests": ["architecture", "history", "coffee"],
  "walkingPace": "Standard",
  "accessibilityPreferences": ["AvoidStairs"]
}'

$walk.walkSessionId
```

Start the walk:

```powershell
Invoke-RestMethod -Method Post -Uri "http://localhost:5207/api/walks/$($walk.walkSessionId)/start"
```

Get the next stop:

```powershell
Invoke-RestMethod -Method Get -Uri "http://localhost:5207/api/walks/$($walk.walkSessionId)/next-stop"
```

Arrive at each stop in sequence:

```powershell
$stops = Invoke-RestMethod -Method Get -Uri "http://localhost:5207/api/walks/$($walk.walkSessionId)/stops"
foreach ($stop in $stops) {
  $body = @{
    latitude = $stop.location.latitude
    longitude = $stop.location.longitude
  } | ConvertTo-Json
  Invoke-RestMethod -Method Post -Uri "http://localhost:5207/api/walks/$($walk.walkSessionId)/stops/$($stop.stopId)/arrive" -ContentType application/json -Body $body
}
```

Complete the walk:

```powershell
Invoke-RestMethod -Method Post -Uri "http://localhost:5207/api/walks/$($walk.walkSessionId)/complete"
```

Cancel a walk:

```powershell
Invoke-RestMethod -Method Post -Uri "http://localhost:5207/api/walks/$($walk.walkSessionId)/cancel"
```

## Swagger Walkthrough

1. Run the API with the `http` launch profile.
2. Open `http://localhost:5207/swagger`.
3. Use `POST /api/walks` with the example request.
4. Copy the returned `walkSessionId`.
5. Call `POST /api/walks/{walkSessionId}/start`.
6. Call `GET /api/walks/{walkSessionId}/next-stop`.
7. Call `POST /api/walks/{walkSessionId}/stops/{stopId}/arrive` for each stop in sequence.
8. Call `POST /api/walks/{walkSessionId}/complete`.
9. Try starting the completed walk again to see the expected ProblemDetails `409` response.

## Mock Content

The Phase 2 mock planner always returns the same Union Square route with seven stops. Stops distinguish:

- `RoverEditorial`: Rover-authored editorial content.
- `LocalRecommendation`: non-sponsored local recommendation content.
- `Sponsored`: paid placement with an explicit `sponsoredDisclosure` field.

Sponsored content is not treated as Rover editorial content.

## In-Memory Storage

Walk sessions and profile data are stored in thread-safe in-memory repositories by default. Data resets every time the API restarts unless PostgreSQL storage is explicitly configured.

## Phase 9 Private Beta

Phase 9 adds beta hardening for real-world field testing:

- `appsettings.Beta.json` for a clearly identified private-beta API environment.
- Runtime audio cache exclusion from the API project build.
- Privacy-safe beta diagnostics at `GET /api/beta/diagnostics`.
- Beta configuration status at `GET /api/beta/configuration`.
- Problem reporting at `POST /api/beta/problem-reports`.
- Crash breadcrumb abstraction at `POST /api/beta/crash-breadcrumbs`.
- Post-walk feedback at `POST /api/walks/{walkSessionId}/feedback`.
- Manual "I'm Here" arrival guarded by server-side distance checks.
- Stale GPS and short-window impossible-jump rejection.

Run the local debug API for Samsung testing:

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

Run the Flutter app on Samsung:

```powershell
cd "C:\Users\jesse\Documents\Codex\2026-08-27\create-a-new-production-quality-asp\SRC\rover_flutter"
& "C:\Users\jesse\AppData\Local\Android\Sdk\platform-tools\adb.exe" reverse tcp:5080 tcp:5080
flutter run -d RFGYA0RB5HY --dart-define=ROVER_API_BASE_URL=http://127.0.0.1:5080 --dart-define=ROVER_DEV_USER=voice-dev --dart-define=MAPBOX_PUBLIC_TOKEN=$env:MAPBOX_PUBLIC_TOKEN
```

For actual private beta, use `ASPNETCORE_ENVIRONMENT=Beta`, HTTPS middleware endpoints, durable storage, configured Cognito, restricted Mapbox settings, and server-only ElevenLabs credentials. Do not commit tokens, API keys, signing keys, keystores, or tester personal data.

See `docs/PHASE_9_PRIVATE_BETA.md` and `docs/PHASE_9_FIELD_TEST_PLAN.md`.

## Deferred

Do not begin Phase 10 from this foundation. AR, camera recognition, payments, advertising, social sharing, white-label features, production publishing, and new major platform capabilities remain out of scope until explicitly authorized.
