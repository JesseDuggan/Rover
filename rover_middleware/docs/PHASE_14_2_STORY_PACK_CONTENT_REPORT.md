# ROVER Phase 14.2 - Grounded Story Pack Content

**Implemented:** 2026-09-01  
**Status:** Complete  
**Scope:** Multi-length grounded narration, audience profiles, topic availability, sparse-evidence behavior, and structured OpenAI sections

## Outcome

Phase 14.2 upgrades the Phase 14.1 Story Pack from a grounding envelope to a usable multi-length narration package. Every successful `POST /api/location-story` response now carries Story Pack schema `1.1` with exactly one:

- `CameraTeaser`, targeting about 12 seconds.
- `Arrival`, targeting about 60 seconds.
- `Deeper`, targeting about 180 seconds.

These are evidence ceilings, not padding requirements. When retrieved evidence cannot support the target length, ROVER returns a shorter grounded section and explicitly marks unavailable deeper content.

Existing Flutter behavior is unchanged because the app continues to use the legacy `shortSpokenNarration` field until Phase 14.5 consumes Story Pack sections.

## Deterministic composition

`DeterministicStoryPackFactory` composes sections from normalized evidence claims:

- Camera teaser uses canonical identity plus the strongest profile-relevant verified claim.
- Arrival preserves the validated short narration and adds additional verified claims within its word budget.
- Deeper narration uses all suitable verified claims within its word budget.
- Sparse deeper content includes `ROVER could not verify a fuller story for this place yet.` rather than invented detail.
- Every factual sentence cites its precise evidence ID.
- Inferred relative-location sentences remain explicitly typed as inference.

Section metadata includes target duration, estimated spoken duration, completeness, and availability. Story Pack metadata now includes last verification time plus supported and unsupported topic lists.

## Audience profiles

Phase 14.2 supports:

- `GeneralTraveller`
- `HistoryEnthusiast`
- `ArchitectureEnthusiast`
- `FamilyWithChildren`
- `LocalResident`
- `BusinessTraveller`
- `OutdoorAdventurer`
- `AccessibilityFocused`

The profile is resolved from `narrationStyle` and request interests. Personalization changes only claim selection and ordering. Tests prove that profile variants retain the same underlying evidence set.

Full stored-profile preference lookup remains deferred. The existing `profileId` contract is preserved for that later integration.

## Evidence topics

Normalized evidence claims now retain their source fact category. This supports profile ranking and topic availability for:

- Accessibility
- Architecture
- History
- Media
- People
- Practical information
- Surprising detail

A topic is advertised as available only when verified evidence supports it. Missing topics are returned in `unavailableTopics`; they are not generated speculatively.

## OpenAI contract

OpenAI location synthesis now requests structured `sections`, each containing grounded sentence objects:

```text
sectionType -> sentences[] -> sentenceId, text, contentType, evidenceIds, confidence
```

The prompt enforces Camera, arrival, and deeper word limits and forbids padding. The parser remains compatible with the Phase 14.1 single-arrival structure during rollout. Missing IDs, unsupported IDs, malformed content types, duplicated sections, excessive lengths, and ungrounded wording all lead to deterministic fallback.

An `unavailable` label cannot be used to bypass grounding: unavailable text must explicitly state that information is unavailable or unverified.

## API additions

The additive `storyPack` response now includes:

- Section duration, completeness, and availability metadata.
- Evidence claim category.
- Last verified timestamp.
- Available and unavailable topic lists.
- Canonical identity, sources, claims, citations, expiry, and validation from Phase 14.1.

No existing response property was removed or renamed.

## Automated verification

```powershell
cd "C:\Users\jesse\Documents\Codex\2026-08-27\create-a-new-production-quality-asp\SRC\rover_middleware"
dotnet build Rover.sln --no-restore
dotnet run --project Rover.Tests\Rover.Tests.csproj --no-build
```

Result:

- Build succeeded with 0 warnings and 0 errors.
- 87 middleware tests passed; 0 failed.
- New coverage verifies three required sections, duration metadata, profile ordering, unchanged evidence across profiles, sparse evidence, multi-section OpenAI parsing, serialized topic metadata, section word limits, and unavailable-label abuse.
- Existing journey, geofence, route, provider, Camera resolution, narration, and API integration tests remain green.

## Manual API inspection

Restart the middleware, then request a story and inspect `storyPack`:

```powershell
$body = @{
  latitude = 44.678
  longitude = -76.395
  radiusMeters = 1500
  interests = @("history")
  selectedPlaceIds = @()
  narrationStyle = "history enthusiast"
} | ConvertTo-Json

$story = Invoke-RestMethod -Method Post `
  -Uri "http://127.0.0.1:5080/api/location-story" `
  -ContentType "application/json" `
  -Body $body

$story.storyPack | ConvertTo-Json -Depth 12
```

## Deferred

- New travel-focused and expanded evidence providers: Phase 14.3.
- Persistent evidence and Story Pack cache: Phase 14.4.
- Flutter Camera/AR and ROAM section consumption: Phase 14.5.
- Phase 13.6 offline intelligence will consume the persistent Story Pack format after Phase 14.4.
- Gemini Maps Grounding, Overture ingestion, and current events remain optional later adapters.

## Known limitations

- Current providers often return only one or two claims, so deeper stories will correctly remain short in sparse areas.
- Topic classification is deterministic and category/keyword based.
- Stored profile preferences are not loaded by the Story Pack composer yet.
- No Story Pack persistence or Flutter presentation is included in this package.
