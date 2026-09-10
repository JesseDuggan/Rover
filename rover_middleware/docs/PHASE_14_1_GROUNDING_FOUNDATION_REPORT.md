# ROVER Phase 14.1 - Location Knowledge Grounding Foundation

**Implemented:** 2026-09-01  
**Status:** Complete  
**Scope:** Provider-neutral identity, evidence, sentence grounding, Story Pack schema, strict validation, and deterministic fallback

## Decision

The Location Knowledge Engine is Phase 14. Phase 11 remains the existing Camera/AR phase, so its number is not reused.

Phase 14.1 extends the current location-intelligence pipeline rather than replacing it. Existing `GET /api/location-context`, `POST /api/location-observations/resolve`, and `POST /api/location-story` behavior remains available. The location-story response adds an optional `storyPack` object; existing Flutter parsing remains compatible.

## Operational pipeline

`Nearby providers -> resolved LocationPlace -> normalized evidence claims -> synthesized sentences -> Story Pack -> strict grounding validation -> API response or deterministic fallback`

The language model is used only as a storyteller. It now receives normalized evidence and must return structured sentences with evidence IDs. The middleware validates the result before returning it.

## Models added

- `CanonicalPlaceIdentity` with ROVER, GERS/Overture, Wikidata, Wikipedia, Google Places, OpenStreetMap, Mapbox, and additional provider identifiers.
- `EvidenceSourceReference` preserving provider, record ID, title, URL, attribution, license, retrieval time, expiry, and confidence.
- `EvidenceClaim` distinguishing fact, inference, and unavailable information.
- `GroundedStorySentence` with a stable sentence ID, content type, evidence IDs, and confidence.
- `GroundedStorySection` supporting Camera teaser, arrival, and deeper sections.
- `StoryPack` with schema version, identity, profile, sections, claims, sources, completeness, attribution, generation/expiry times, and validation.
- `GroundingValidationResult` and stable issue codes for rejected content.

## Grounding rules

`StrictStoryGroundingValidator` rejects a Story Pack when:

- A factual or inference sentence has no evidence reference.
- A sentence references an evidence ID that does not exist.
- Evidence references a source ID that does not exist.
- A factual sentence has no verified claim.
- A source, evidence, or sentence ID is duplicated.
- Evidence is expired.
- Numbers in narration are absent from cited evidence.
- Meaningful sentence terms do not have sufficient overlap with cited claims.

Unavailable statements are allowed without citations when they explicitly say the information could not be verified or is unavailable.

When synthesized narration fails validation, `LocationStoryContextService` discards it and generates the existing deterministic evidence summary. The response warning states that grounding validation caused fallback. The selected place ID is preserved, preventing unrelated broad-area facts from replacing the selected Camera/AR card.

## OpenAI structured output

The location-story prompt now requires:

- `sentenceId`
- `text`
- `contentType` (`fact`, `inference`, or `unavailable`)
- `evidenceIds`
- `confidence`

Nonexistent evidence IDs, missing citations, malformed content types, and empty sentence sets are rejected before Story Pack validation. Place identity and current relative location are supplied as explicit evidence claims, rather than being treated as uncited prompt context.

## API compatibility

The existing `LocationStoryResponse` fields are unchanged. `storyPack` is additive and contains normalized API response models with enum values serialized as descriptive strings. Existing `LocationSourceResponse` also gains optional `sourceTitle` and `expiresUtc` fields.

Flutter does not need to consume `storyPack` in Phase 14.1. Phase 14.5 will use it for Camera/AR and ROAM presentation.

## Configuration

The existing `Rover:LocationIntelligence` section now supports:

- `EvidenceFreshnessMinutes`, default `10080` (seven days).
- `SpatialEvidenceFreshnessMinutes`, default `5`.

Provider-supplied expiry values take precedence. Phase 14.4 will introduce separate persistent caches and more granular provider/content policies.

## Files added

- `Rover.Application/LocationIntelligence/GroundedStoryModels.cs`
- `Rover.Application/LocationIntelligence/GroundedStoryServices.cs`
- `docs/PHASE_14_1_GROUNDING_FOUNDATION_REPORT.md`

## Files extended

- `Rover.Application/LocationIntelligence/LocationIntelligenceModels.cs`
- `Rover.Application/LocationIntelligence/LocationIntelligenceInterfaces.cs`
- `Rover.Application/LocationIntelligence/LocationIntelligenceOptions.cs`
- `Rover.Application/LocationIntelligence/LocationStoryContextService.cs`
- `Rover.Application/DependencyInjection.cs`
- `Rover.Infrastructure/LocationIntelligence/OpenAILocationStorySynthesizer.cs`
- `Rover.Infrastructure/DependencyInjection.cs`
- `Rover.Api/Contracts/LocationIntelligenceContracts.cs`
- `Rover.Api/Mapping/LocationIntelligenceResponseMapper.cs`
- `Rover.Api/appsettings.Development.json`
- `Rover.Tests/Program.cs`
- `README.md`

## Automated verification

```powershell
cd "C:\Users\jesse\Documents\Codex\2026-08-27\create-a-new-production-quality-asp\SRC\rover_middleware"
dotnet build Rover.sln --no-restore
dotnet run --project Rover.Tests\Rover.Tests.csproj --no-build
```

Result:

- Middleware build: succeeded with 0 warnings and 0 errors.
- Middleware tests: 81 passed, 0 failed.
- New tests cover canonical identity and source serialization, sentence citations, nonexistent evidence, semantically unsupported wording, expired evidence, OpenAI structured sentence output, and deterministic fallback replacement.
- Existing journey, route, geofence, narration, Camera observation, provider outage, caching, and API integration tests remain green.

## Deliberately deferred

- Commercial POI provider expansion: Phase 14.3, implemented with Google Places API (New).
- Expanded Wikipedia Geosearch and Wikidata identity linking: Phase 14.3.
- Persistent evidence and Story Pack repositories: Phase 14.4.
- Full Camera teaser, one-minute arrival, and three-minute story population: Phase 14.2.
- Flutter Camera/AR and ROAM Story Pack consumption: Phase 14.5.
- Gemini Maps Grounding, Overture ingestion, and current-events adapters: Phase 14.6 or later and remain optional.

## Known limitations

- Phase 14.1 packages the evidence available from current providers; it does not add a new provider.
- Story Packs are returned but are not persisted independently yet.
- The current deterministic pack populates arrival and optional deeper sections. Rich section generation belongs to Phase 14.2.
- Lexical validation is intentionally conservative. Rejected narration falls back safely instead of attempting repeated model regeneration.

## Continuation

Phase 14.2 is complete. See `docs/PHASE_14_2_STORY_PACK_CONTENT_REPORT.md`
for multi-length Story Pack content, audience profiles, topic availability, and
the updated automated baseline.
