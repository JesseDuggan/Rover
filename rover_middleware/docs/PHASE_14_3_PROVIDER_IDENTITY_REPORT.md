# ROVER Phase 14.3 - Google Places and Place Identity

**Implemented:** 2026-09-01  
**Provider migration:** 2026-09-02  
**Status:** Complete; Flutter attribution rollout completed in Phase 14.5  
**Scope:** Google Places API (New), OCR business search, expanded Wikipedia evidence, Wikidata linking, deterministic identity metadata, and collision safeguards

## Decision

OpenTripMap was removed at the product team's request. Its provider class, configuration, environment variables, provider identifiers, tests, and operational documentation have been replaced with Google Places API (New).

The replacement preserves the provider-neutral `ILocationContextProvider` and `ICandidateObservationSearchProvider` boundaries. No Flutter request contract was removed. The additive canonical provider identifier is now `googlePlaceId`.

## Google Places adapter

`GooglePlacesLocationContextProvider` performs two bounded operations:

- Nearby Search (`POST /v1/places:searchNearby`) supplies nearby POI identity, coordinates, address, type, operating status, opening state, and accessibility evidence.
- Text Search (`POST /v1/places:searchText`) resolves business names recognized by Camera Explorer OCR.

The adapter:

- Sends the key in `X-Goog-Api-Key`, never in the URL.
- Uses an explicit `X-Goog-FieldMask` to limit returned fields and cost.
- Preserves `Google Maps` attribution and third-party provider attributions returned by Google.
- Stores the Google Place ID in provider identity as `google_places`.
- Does not request photos, reviews, generative summaries, or hotel rates.
- Returns warnings rather than failing API startup when the key is missing or a request fails.

Official API references:

- `https://developers.google.com/maps/documentation/places/web-service/nearby-search`
- `https://developers.google.com/maps/documentation/places/web-service/text-search`
- `https://developers.google.com/maps/documentation/places/web-service/choose-fields`
- `https://developers.google.com/maps/documentation/places/web-service/place-id`

## Google policy safeguards

Google Places content is not cached by the provider. When the provider is enabled, aggregate location-context caching is also bypassed so a mixed response cannot indirectly cache Google content. Place IDs may be retained as canonical identifiers.

The ROVER map surface now uses Google Maps. Phase 14.5 carries Google Places identity and attribution into walk stops, route options, Camera details, and active-ROAM itinerary surfaces.

The base development profile keeps Google Places disabled until a server-side key is supplied. Beta and staging discovery defaults now select Google Places because the Phase 14.5 display gate is complete.

Official policy reference:

- `https://developers.google.com/maps/documentation/places/web-service/policies`

## Configuration

Development configuration:

```json
"GooglePlaces": {
  "Enabled": false,
  "Endpoint": "https://places.googleapis.com/v1",
  "MaximumResults": 8,
  "TimeoutSeconds": 10,
  "CacheMinutes": 0
}
```

Configure the middleware with:

```powershell
$env:GOOGLE_PLACES_API_KEY = "<key>"
$env:ROVER_LOCATION_PROVIDER_GOOGLEPLACES_ENABLED = "true"
```

`GOOGLE_MAPS_API_KEY` is accepted as a fallback secret name, but the Android-restricted Maps SDK key must not be reused for server-side Places calls. Settings are overridable under `Rover:LocationIntelligence:Providers:GooglePlaces`. Secrets remain middleware-only and are not included in Flutter.

## Identity policy

Identity resolution remains deterministic and uses this order:

1. A shared provider identifier or Wikidata QID is a verified merge.
2. Name-and-geography matching is provisional and requires a maximum 25-metre separation, very high name similarity, a shared non-empty category, and strong address evidence.
3. Missing-address records may merge only for exact-name, non-business landmarks with matching categories.
4. Common business categories such as cafes, restaurants, hotels, shops, and stores never merge on name and proximity alone.
5. Unmatched records remain separate and retain their provider-native candidate identity.

This deliberately favors duplicates over a false merge that could make Camera Explorer narrate facts about the wrong business.

## Wikipedia and Wikidata

Wikipedia continues to combine geosearch with a bounded page query for canonical URLs, introductory extracts, thumbnails, and Wikidata QIDs. A detail-query failure retains the geosearch result with a warning.

Wikidata remains the structured geospatial source. Explicit QIDs from Wikipedia, OpenStreetMap, and Wikidata entities can resolve through the same verified identifier.

## Automated verification

```powershell
cd "C:\Users\jesse\Documents\Codex\2026-08-27\create-a-new-production-quality-asp\SRC\rover_middleware"
dotnet build Rover.sln --no-restore
dotnet run --project Rover.Tests\Rover.Tests.csproj --no-build
```

Result on 2026-09-02:

- Build succeeded with 0 warnings and 0 errors.
- 94 middleware tests passed; 0 failed.
- Google tests cover Nearby Search parsing, OCR Text Search, API-key handling, attribution preservation, missing-key behavior, provider-cache bypass, and aggregate-cache bypass.
- Existing journey, geofence, Camera observation, narration, Story Pack, identity collision, and API integration tests remain green.

## Rollout checklist

Before enabling Google Places outside middleware tests:

1. Add visible Google Maps attribution to every Flutter list or detail surface that consumes Google-derived content.
2. Preserve and display returned third-party attribution where present.
3. Filter Google-derived POIs out of all Mapbox map markers, labels, and overlays.
4. Confirm logs and persistence retain Place IDs only, not Google place content.
5. Restrict the Google API key to the required Places API and the middleware deployment environment.
6. Run a Westport field test for nearby discovery, Camera OCR business resolution, correct selected-place narration, attribution, and duplicate suppression.

## Deferred

- Persistent non-Google evidence and Story Pack repositories: Phase 14.4.
- Flutter Camera/AR and active ROAM attribution: completed in Phase 14.5.
- Phase 13.6 offline intelligence after Phase 14.4 persistence.
- Google hotel rates require a separate approved commercial data source; Places identity does not itself provide best-rate shopping.

## Known limitations

- Google coverage and available fields vary by place and region.
- Conservative matching can leave duplicates when providers lack shared identifiers or sufficiently strong address evidence.
- Google Places requires a separately restricted server-side API key; the Android Maps SDK key is not suitable for middleware requests.
