# ROVER Phase 14.5 - Google Places Rollout

**Implemented:** 2026-09-02  
**Status:** Code and automated gates complete; server key configured; final hardening regression remains  

## Delivered

- Initial walk discovery can use Google Places API (New).
- Live route-option discovery uses the selected local provider instead of a Mapbox-specific path.
- Google Place ID, Google Maps URL, provider name, and all required attribution travel with each walk stop.
- Active ROAM current-stop, next-stop, route-edit, and itinerary surfaces display the source attribution.
- Camera OCR place resolution continues to display provider and returned attribution.
- Google-derived Story Packs remain excluded from persistent middleware and device caches. Place IDs may remain as identifiers.
- Google Routes supplies pedestrian route geometry and maneuvers. Google Maps is the Flutter map renderer.

## Middleware configuration

Use a server-side key restricted to Places API (New) and to the middleware deployment environment. Do not reuse the Android-restricted Maps SDK key.

```dotenv
ROVER_ROUTING_MODE=Google
ROVER_LOCAL_DISCOVERY_MODE=GooglePlaces
ROVER_DISCOVERY_MODE=GooglePlaces
ROVER_LOCATION_PROVIDER_MAPBOX_ENABLED=false
ROVER_LOCATION_PROVIDER_GOOGLEPLACES_ENABLED=true
GOOGLE_PLACES_API_KEY=replace-with-server-google-places-key
```

Restart the middleware after changing `.env.local`. No Google Places secret belongs in Flutter or in a `--dart-define` file.

## Verification

```powershell
cd "C:\Users\jesse\Documents\Codex\2026-08-27\create-a-new-production-quality-asp\SRC\rover_middleware"
dotnet build Rover.sln --no-restore
dotnet run --project Rover.Tests\Rover.Tests.csproj --no-build

cd "..\rover_flutter"
flutter analyze
flutter test
```

Automated result on 2026-09-02:

- Middleware build: 0 warnings, 0 errors.
- Middleware: 100 passed, 0 failed.
- Flutter analysis: no issues.
- Flutter: 123 passed, 0 failed.

## Field gate

1. Create a new ROAM in Westport with coffee, history, or interesting-site interests.
2. Confirm generated stop IDs begin with `google-` in the middleware smoke response and that stops are real nearby businesses or landmarks.
3. Confirm active ROAM shows `Source: Google Maps` for Google-derived stops.
4. Open Camera Explorer, scan a business sign, and confirm the selected business name, narration, and source agree.
5. Add a live nearby route option and confirm its source remains visible after accepting it.
6. Restart with networking disabled and confirm Google content is not presented as a cached Story Pack.

The server-side Google Places key is configured and the initial Westport field gate passed for real-place discovery and attribution. Camera latency, off-route maneuver refresh, and arrival-audio issues found during that pass received targeted fixes on 2026-09-03 and require one rebuilt-device regression. See `PHASE_14_STATUS.md`.
