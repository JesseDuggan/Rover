# Ontario field testing setup

The pilot adds municipal heritage discovery for Waterdown, Toronto and Milton to the existing walking and story pipeline. The saved backend configuration now enables **all existing beta testers while in these regions**, as approved by the operator. Nothing in this change deploys the API or changes production variables, branding, navigation, narrator settings or voice IDs.

## Geographic profiles and activation

| Geographic profile ID | Region | Initial discovery radius | Centre (latitude, longitude) | Saved status |
| --- | --- | --- | --- | --- |
| `WALK-CA-ON-WAT-001` | Waterdown, Hamilton, Ontario, Canada | 8 km | 43.331, -79.8895 | Enabled |
| `WALK-CA-ON-TOR-001` | Toronto, Ontario, Canada | 10 km | 43.650, -79.365 | Enabled |
| `WALK-CA-ON-MIL-001` | Milton, Ontario, Canada | 8 km | 43.5135, -79.8815 | Enabled |

These persistent IDs are stored in `Rover.Api/appsettings.json`, not generated at startup and not personal profiles, credentials or authentication IDs. Do not put a `WALK-...` ID in a `profileId` GUID field. Startup validation rejects duplicate or invalid geographic IDs and invalid discovery radii. Keep IDs unchanged across deployments to preserve reporting continuity.

1. Deploy the updated API, preserving existing beta authorization, ordinary POI, story-generation and voice settings. This geographic-profile update requires no additional mobile UI or APK change.
2. Check Railway overrides: `Enabled=true`, `AllowAllBetaTesters=true`, and each market `Enabled=true`. Existing environment-variable overrides take precedence over the saved JSON. Restart/redeploy to apply changes.
3. Create a fresh walk inside a region. Its API response contains `geographicProfileId`; the personal `profileId` is unchanged. No personal tester-ID enrollment is required in all-beta mode.
4. Verify an out-of-region start still creates an ordinary walk. The profile is not a travel restriction. A tester visiting another region receives that region's discovery; overlapping regions choose the nearest configured centre. A journey keeps the geographic ID selected at creation for diagnostics and feedback, even after travel or rerouting.

Production activation has **not** been verified by this local implementation. Existing story-engine feature flags remain environment-controlled; this change does not enable or disable them globally.

All settings live under `Rover:OntarioFieldTesting` in `Rover.Api/appsettings.json`. Railway environment-variable names use double underscores:

| Variable | Value or purpose |
| --- | --- |
| `Rover__OntarioFieldTesting__Enabled` | Saved as `true`; global kill switch |
| `Rover__OntarioFieldTesting__AllowAllBetaTesters` | Saved as `true`; no personal allowlist required |
| `Rover__OntarioFieldTesting__Markets__waterdown__Enabled` | Independent Waterdown switch |
| `Rover__OntarioFieldTesting__Markets__toronto__Enabled` | Independent Toronto switch |
| `Rover__OntarioFieldTesting__Markets__milton__Enabled` | Independent Milton switch |
| `Rover__OntarioFieldTesting__Markets__waterdown__GeographicProfileId` | `WALK-CA-ON-WAT-001`; persistent geographic identity |
| `Rover__OntarioFieldTesting__Markets__waterdown__Region` | Display/reporting region name |
| `Rover__OntarioFieldTesting__Markets__waterdown__Center__Latitude` | `43.331` |
| `Rover__OntarioFieldTesting__Markets__waterdown__Center__Longitude` | `-79.8895` |
| `Rover__OntarioFieldTesting__Markets__waterdown__SearchRadiusMeters` | `8000`; Toronto `10000`, Milton `8000` |
| `Rover__OntarioFieldTesting__Markets__waterdown__MaximumStopDistanceMeters` | `2000`; keeps added walking stops local |
| `Rover__OntarioFieldTesting__ReportDirectory` | Use `/data/ontario-field-tests` on the existing Railway volume |
| `Rover__OntarioFieldTesting__RetentionDays` | Default 90, bounded to 1-90 days |

Substitute `toronto` or `milton` for `waterdown` to configure each independently. To return to designated testers only, set `AllowAllBetaTesters=false` and configure actual personal GUIDs under `Markets__<market>__TesterProfileIds__0`, `__1`, etc. Enrollment in any enabled market allows travel to other enabled markets. With all-beta mode on, changing a personal allowlist does not restrict access. Disable a market or the global flag to stop new pilot discovery without erasing existing stories or interrupting a working journey. These flags are **not a replacement for authentication**; the endpoints retain existing beta API and account-access mechanisms.

Each market has its own centre, radius, stop-distance limit, `Areas`, `MaximumPlaces`, `IncludeExistingHeritageSources` and `Datasets`. No Canadian geography is hardcoded into Flutter. The 8/10/8 km circles are discovery scopes, not official municipal boundaries or required walk lengths. Added heritage stops stay within 2 km of the walk start; smaller route-context queries retain their requested radii. Existing planning and user-selected interests remain in control.

The downtown `Areas` (WGS84 `West`, `South`, `East`, `North`) are priority municipal query windows. They are queried before the broader regional circle so a record-budget limit does not displace initial downtown coverage. Records outside the circle are excluded. Wider municipal coverage is bounded and can be incomplete; warnings identify truncated retrievals. Legacy configurations without a centre can still use validated areas.

## Source compatibility

| Market | Initial scope | Municipal status |
| --- | --- | --- |
| Waterdown | Historic downtown, Mill Street, Smokey Hollow; -79.901/43.320 to -79.878/43.342 | Hamilton's official point layer verified |
| Toronto | Old Town, St. Lawrence Market, Distillery District; -79.380/43.645 to -79.350/43.655 | Official register layer 56 verified |
| Milton | Historic downtown and Main Street; -79.890/43.508 to -79.873/43.519 | Official endpoint discovered but timed out; municipal dataset disabled |

Milton's geographic profile is enabled and can use existing Wikimedia, Parks Canada and ordinary POI providers. Its municipal dataset is independently disabled. Do **not** enable `Markets__milton__Datasets__0__Enabled` until its service successfully returns WGS84 point features with the configured fields from the deployment environment. Dataset failure never requires synthetic historical markers.

The shared municipal adapter requests explicit `inSR=4326` and `outSR=4326`, validates point geometry and geographic bounds, paginates with record limits, and retains record URLs, attribution and licence references. Only reviewed endpoints can be fetched; an additional host requires code review. No new external API key is required.

Hamilton register membership is identity evidence, not a complete story. Toronto descriptive fields can support narration, but listed and designated status are not interchangeable. Missing construction dates, historical events, people or quotations must be researched with citations, not invented from a map marker. No blanket permission for municipal photographs is assumed; existing image-rights checks remain in place.

Existing Wikipedia, Wikidata and Parks Canada providers are reused locally without changing their global switches. Parks Canada supplies its own interest points, **not every Canadian heritage property**. Municipal history/architecture categories must match listener interests. Uncategorized Wikimedia subjects can seed the existing cited research/classification flow; they are not automatically labelled historical stories. Existing place matching merges shared identities, and matching municipal evidence enriches an existing POI without moving its routing coordinate.

## Caching and operational limits

- Municipal results share a cache across testers, keyed by the geographic profile, centre, radius, priority areas and dataset configuration. Concurrent requests coalesce and results expire within 24 hours. Failed retrievals have a 30-second negative cache. This cache is process-local; multiple replicas can each issue a fetch.
- Participation and geography are checked before cache access. Raw tester IDs are not municipal cache keys or upstream query parameters.
- Failed Wikimedia/federal companion calls enter a shared 30-second market cooldown, so different route sections do not repeatedly hit an unavailable source. Successful companion results use the existing provider cache.
- Existing story idempotency, deduplication, journey retention, audio cache and ElevenLabs settings remain in use. No new cross-user permission is granted to store restricted source content in the shared story library.
- Sparse or failed heritage sources preserve ordinary discovery. A working Google/other ordinary POI configuration is still necessary; this integration does not repair upstream authentication or quota errors.
- Provider discovery timings are not end-to-end journey or story-generation timings. Cold companion requests can add latency; measure production performance during beta testing.

## Verification

Run from `rover_middleware`:

```powershell
dotnet build Rover.Tests/Rover.Tests.csproj --configuration Release
dotnet run --project Rover.Tests/Rover.Tests.csproj --configuration Release --no-build
dotnet run --project Rover.Tests/Rover.Tests.csproj --configuration Release --no-build -- --ontario-source-audit
```

The audit only calls public municipal, Wikimedia and Parks Canada data services. It neither enables the production pilot nor calls OpenAI, Google Places or ElevenLabs. Its municipal sample is capped at 100 records; the municipal-discovery event reports counts of fetched records, not an exhaustive regional inventory. Companion counts come from one configured-centre query at the profile radius, capped at 20 results. Counts from different providers overlap and must not be added as unique POIs.

Local verification on 2026-10-09: API Release build passed with zero warnings/errors; **210 tests passed**. Coverage includes persisted IDs, saved all-beta activation, designated-only and disabled modes, regional travel, journey tagging, response/feedback association, larger discovery radii, local-stop limits, radius-sensitive caching, bounds, interests, pagination, failures, cache coalescing, POI enrichment, sparse journeys, 20/60/90-minute mock plans and existing voice/cache regressions. The latest public audit completed for all three profiles; see separate reports for counts and limitations. This profile update changes no Flutter files. Device and live playback verification remain pending; the earlier integration's Flutter test attempt was blocked by SDK bootstrap access.

For each market, test a 20-30 minute walk and both 60- and 90-minute walks. Verify actual map markers and sidewalk access; do not assume a heritage building admits the public. Check history-only, architecture-only, mixed and non-history interests; refresh twice and reroute once to check duplicates and story retention. Listen before a POI, through entry/arrival narration, and after exit. Confirm pause/resume, no duplicate arrival narration, familiar voice and cache replay. Check travel between regions, an out-of-area start, and disabled mode as controls. Test unenrolled profiles only in designated-only mode.

## Structured feedback and reports

An operator can submit tester feedback to `POST /api/walks/{walkSessionId}/field-test-feedback` using the existing beta authorization header. The personal profile GUID must match that walk and remain eligible for the pilot. The server associates the submission with the journey's stored geographic ID; the client cannot choose another geographic profile in the feedback body. Body:

```json
{
  "profileId": "<actual-personal-profile-guid-for-this-walk>",
  "storyAccuracy": 4,
  "storyRelevance": 4,
  "voiceQuality": 5,
  "routeQuality": 4,
  "narrationResult": "played",
  "comments": "Identify the story title, source concern or route problem; omit personal details."
}
```

Ratings are integers 1-5. `voiceQuality` may be null with `narrationResult: "not-tested"`. Other narration outcomes: `failed`, `interrupted`, `device-fallback`. Comments are limited to 1000 characters. This is operator/API collection; no new feedback screen was added.

Daily per-market JSONL journals capture municipal counts, context counts, successful journey timings, story-generation status/timings and feedback. Every pilot event includes `GeographicProfileId`. They omit raw personal profile IDs and tracks, hash walk IDs and apply existing secret redaction to comments. The optional `geographicProfileId` walk response field exposes the selected region without changing navigation or screens. Legacy untagged walks use their start location for reporting; newly tagged journeys retain their original region. Restrict access to the report directory; hashes remain linkable within a walk. Files are capped at about 5 MB per market/day and older journals expire at the configured retention. Writes are best-effort and failures appear in API warnings; HTTP 202 is not a durable reporting guarantee. Failed journey attempts still require normal API diagnostics.

Do not sum repeated discovery events as unique POIs, or repeated pack sizes as newly generated stories. Compare source counts per completed cold retrieval and keep the latest pack result per hashed walk. Record cache hits and errors separately when measuring latency. Audio regression tests do not establish actual listening quality; only tester feedback and live playback can do that.

Separate initial reports: [Waterdown](field-testing/WATERDOWN.md), [Toronto](field-testing/TORONTO.md), [Milton](field-testing/MILTON.md).
