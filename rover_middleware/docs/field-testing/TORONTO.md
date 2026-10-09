# Toronto field testing report

**2026-10-09. Status: geographic profile enabled in saved backend configuration for all existing beta testers; deployment pending.** Persistent profile `WALK-CA-ON-TOR-001` covers a 10 km discovery circle centred at 43.650, -79.365. Old Town, St. Lawrence Market and the Distillery District remain priority areas. This is a source-readiness report, not a completed walking trial.

## Discovery and evidence

| Measure | Observed result |
| --- | --- |
| Municipal records fetched across priority and regional queries | 1571; regional query truncated at record budget |
| Retained with identity, coordinates and register evidence | 1498 |
| Duplicate records removed | 73, including overlap between priority and regional queries |
| Invalid or unusable records excluded | 0 |
| Descriptive narrative evidence in nearest 100 municipal records | 99 |
| Wikipedia central-query results | 20 in area, all with introductory extracts |
| Wikidata | Timed out at 6.016 seconds; coverage unknown |
| Parks Canada | Successful query, 0 results within the pilot query |
| Finished historical stories | Not measured; source audit does not generate stories |

Municipal cold retrieval took **2650 ms** on the regional-profile audit. Wikipedia took 666 ms; Parks Canada took 243 ms. These are individual source timings, not journey performance. Companion queries use a 10 km radius around the configured centre and a maximum of 20 results. Do not add their counts to municipal totals as unique POIs. The municipal record-budget warning means wider coverage is incomplete. An earlier downtown-only baseline fetched 573 records and retained 546; it is not directly comparable with this larger discovery scope.

Municipal examples include **26 Berkeley Street** at latitude 43.65057724626272, longitude -79.36426056226334, and **223 Front Street East**. Wikipedia returned subjects including **Canadian Stage Company** and the **Toronto circus riot**. These are leads for appropriately sourced stories, not claims that their full content has already passed editorial or listener review.

## Source and reuse

The [official Toronto heritage register layer 56](https://gis.toronto.ca/arcgis/rest/services/cot_geospatial11/FeatureServer/56) is documented in the [Toronto open-data catalogue](https://open.toronto.ca/dataset/heritage-register/) and subject to the [Open Government Licence Toronto](https://open.toronto.ca/open-data-licence/). Attribution and record URLs accompany the evidence. The adapter requests WGS84 output rather than treating the service's default projected coordinates as latitude and longitude.

The `DETAILS` field can contain historical descriptions; 99 of the nearest 100 retained records passed the descriptive-text threshold. This is not 99 completed entertaining stories, and metadata length is not independent historical corroboration. `Listed`, `Part IV` and `Part V` status retain their municipal meaning; listed properties are not automatically described as designated. Duplicate filtering uses record identity or the same name/address within 15 metres; cross-provider identity resolution still applies downstream.

## Journeys and narration

Shared automated tests pass for 20/60/90-minute mock journeys, configured bounds, selected interests, sparse-source behavior, dedupe, enrichment and profile propagation. WGS84 coordinate handling is verified, but physical map-marker placement and accessible sidewalks have not been walked. **Live journey creation, story-generation latency, finished usable-story count and first-story delay remain unmeasured.**

No narrator voice ID, settings or audio-cache policy was changed. Existing ElevenLabs regression tests pass; no real Toronto audio or listening-quality results were produced. Test story interruption for POI arrival, resumed playback after the POI, and cache replay during field journeys.

## Missing information and feedback

Verify the mix of building history, people, market life, industrial history and neighbourhood change. Check historically sensitive events against cited sources and distinguish current events from durable history. Municipal photographs require separate rights checks; this integration does not grant blanket image reuse.

No tester feedback has been collected by this audit. After deployment, existing beta testers in the region need no new personal enrollment. Use the [pilot feedback workflow](../ONTARIO_FIELD_TESTING.md) for accuracy, relevance, voice and route ratings, associated with `WALK-CA-ON-TOR-001`. Recommended first trials: short Old Town loop, market-focused 60-minute walk, and 90-minute walk toward the Distillery District. Confirm that dense records do not produce repetitive stops, check wider coverage beyond the bounded municipal retrieval, and recheck Wikidata from Railway. The 10 km discovery scope does not force a long walk; added heritage stops retain the separate 2 km limit.
