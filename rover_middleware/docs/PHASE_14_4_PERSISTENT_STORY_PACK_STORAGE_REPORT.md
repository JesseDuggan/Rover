# ROVER Phase 14.4 - Persistent Story Pack Storage

**Implemented:** 2026-09-02  
**Status:** Complete  
**Scope:** Durable Story Pack and evidence repositories, validation on write/read, expiry, bounded retention, privacy-safe keys, and Google Places storage safeguards

## Outcome

Phase 14.4 adds separate persistent repositories for grounded Story Packs and normalized evidence. The default local implementation writes atomic JSON files beneath `work/location-intelligence` and survives middleware restarts.

`LocationStoryContextService` now follows this path:

`live context -> persistent Story Pack lookup -> synthesize on miss -> ground -> validate -> persistence policy -> Story Pack and evidence writes`

A storage failure never prevents live story generation. Invalid, expired, or malformed files are ignored and removed when read.

## Repository boundaries

- `IStoryPackRepository` stores the backward-compatible `LocationStoryResult` with its complete Story Pack.
- `IEvidenceRepository` stores normalized claims and sources independently for later Phase 13.6 offline use.
- `IStoryPackPersistencePolicy` owns content eligibility and preparation rather than hiding provider rules inside the file system adapter.
- `FileLocationIntelligenceRepository` implements both repositories with asynchronous reads/writes, atomic replacement, and bounded file retention.

Story keys are SHA-256 hashes over schema, canonical place ID, profile ID, narration style, and normalized interests. Raw user coordinates and readable profile data are not used in filenames.

## Freshness and grounding

Every Story Pack is revalidated before write and after read. Repository expiry is the earliest durable evidence/source expiry or `GeneratedStoryCacheMinutes`, whichever occurs first.

User-relative distance and direction evidence is intentionally ephemeral. Claims categorized as `relative_location`, and sentences that depend on them, are removed before persistence. The remaining sections are revalidated and legacy narration fields are rebuilt from the persisted sections, preventing stale statements such as “40 metres ahead” from being replayed after a restart.

Evidence reads prune expired claims and sources. Empty evidence sets and expired Story Packs are deleted.

## Google Places policy

Google-derived names, addresses, categories, facts, attribution, and other place content are not persisted. A pack containing a Google source or Google Maps attribution is rejected by both repositories.

A Google Place ID may remain in `CanonicalPlaceIdentity.ProviderIdentifiers` only when the persisted Story Pack is supported entirely by eligible non-Google evidence. This preserves identity linking without retaining prohibited Google content.

## Configuration

Settings under `Rover:LocationIntelligence`:

- `PersistentStorageEnabled`, default `true`.
- `PersistentStorageDirectory`, default `work/location-intelligence`.
- `MaximumStoredStoryPacks`, default `500`.
- `MaximumStoredEvidenceSets`, default `1000`.

Environment overrides:

- `ROVER_LOCATION_STORAGE_ENABLED`
- `ROVER_LOCATION_STORAGE_DIRECTORY`

The storage directory is ignored by source control.

## Automated verification

```powershell
cd "C:\Users\jesse\Documents\Codex\2026-08-27\create-a-new-production-quality-asp\SRC\rover_middleware"
dotnet build Rover.Tests\Rover.Tests.csproj --no-restore -p:BaseOutputPath=C:/Users/jesse/AppData/Local/Temp/rover-phase-14-4-bin/
dotnet C:/Users/jesse/AppData/Local/Temp/rover-phase-14-4-bin/Debug/net10.0/Rover.Tests.dll
```

Result:

- Isolated middleware build succeeded with 0 warnings and 0 errors.
- 98 middleware tests passed; 0 failed.
- New tests verify restart reuse without a second synthesis, separate durable evidence, transient spatial-claim removal, Google content refusal, expiry, and malformed-file cleanup.
- Existing geofence, journey narration, Camera observation, provider, grounding, route, speech, and API integration tests remain green.

The normal solution output directory could not be overwritten during verification because the developer's running `Rover.Api` process correctly held its loaded DLLs. The isolated output built the same projects without interrupting that server.

## Deferred

- Phase 13.6 will consume `IEvidenceRepository` and Story Packs when connectivity is unavailable.
- Phase 14.5 will present Story Pack sections and source attribution in Flutter Camera/AR and active ROAM surfaces.
- Multi-instance or cloud deployment may replace the file adapter behind the same repository contracts with shared object/database storage.
- Persistent provider-response caching remains separate from Story Pack/evidence persistence.
