# Waterdown field testing report

**2026-10-09. Status: geographic profile enabled in saved backend configuration for all existing beta testers; deployment pending.** Persistent profile `WALK-CA-ON-WAT-001` covers an 8 km discovery circle centred at 43.331, -79.8895. Historic downtown Waterdown, Mill Street and Smokey Hollow remain priority areas. This is a source-readiness report, not a completed walking trial.

## Discovery and evidence

| Measure | Observed result |
| --- | --- |
| Municipal records fetched across priority and regional queries | 1391; regional query truncated at record budget |
| Retained with identity, coordinates and register evidence | 979 |
| Duplicate records removed | 412, including overlap between priority and regional queries |
| Invalid or unusable records excluded | 0 in this retrieval |
| Descriptive narrative evidence in nearest 100 municipal records | 0 |
| Wikipedia central-query results | 20 in area, with introductory extracts |
| Wikidata | 20 returned rows in area; identity evidence, not narrative history |
| Parks Canada | Successful query, 0 results within the pilot query |
| Finished historical stories | Not measured; source audit does not generate stories |

Municipal cold retrieval took **2651 ms** on the regional-profile audit. Wikipedia took 872 ms, Wikidata 1434 ms and Parks Canada 244 ms. These are individual source timings, not journey performance. Companion queries use an 8 km radius around the configured centre and a maximum of 20 results; their counts are not an exhaustive inventory and may overlap municipal records. The municipal record-budget warning also means wider coverage is incomplete. An earlier downtown-only baseline fetched 391 records and retained 390; it is not directly comparable with this larger discovery scope.

The official record for **Sealey Park; Scout Hall; Old Waterdown Public and High School** returned latitude 43.331101153646564, longitude -79.88945149952578. Coordinates were checked as WGS84 points inside the configured area. On-device marker placement, entrance access and pedestrian routing still require a field walk.

## Source and reuse

The [City of Hamilton heritage properties dataset](https://open.hamilton.ca/datasets/8a9013bfc00f4502b02a404da1d1e1f9_0/about) is served by the official [Hamilton ArcGIS layer](https://services.arcgis.com/rYz782eMbySr2srL/arcgis/rest/services/Heritage_Properties/FeatureServer/0). Its name, address, status and heritage district fields identify sites; they do not by themselves establish a detailed history. Waterdown records can have `COMMUNITY=Flamborough`, so geographic bounds are used rather than a literal Waterdown community filter.

Reuse carries the [City of Hamilton Open Data Licence](https://www.hamilton.ca/city-council/data-maps/open-data/open-data-licence-terms-and-conditions) and required attribution. Unofficial student copies are not used. Plaque and historic-neighbourhood sources still need an independently verified, licensed geographic feed; the discovered public-art service exposed a table rather than a usable point layer.

## Journeys and narration

Shared automated tests pass for short 20-minute and 60/90-minute mock plans, sparse heritage, interest filtering, duplicate suppression, existing-POI enrichment and automatic story profile inheritance. **Live route creation, story-generation latency, first-story delay and finished usable-story count remain unmeasured.**

No narrator voice ID, settings or audio-cache policy was changed. Existing ElevenLabs regression tests pass; no real Waterdown audio was generated or evaluated in this audit. Test the familiar narrator before a stop, during POI interruption and after leaving it, including cached replay.

## Missing information and feedback

Municipal data needs cited enrichment for Mill Street industry, Smokey Hollow, notable residents, local events and neighbourhood change. Register and designation dates must not be substituted for construction dates. Private properties need sidewalk viewing and access checks.

No tester feedback has been collected by this audit. After deployment, existing beta testers in the region need no new personal enrollment. Run 20-30/60/90-minute journeys with different interests, and record story accuracy, relevance, voice quality, route quality and any evidence disputes through the [pilot feedback workflow](../ONTARIO_FIELD_TESTING.md). Feedback and journey diagnostics carry `WALK-CA-ON-WAT-001`. Prefer a small set of well-supported varied stories over narrating hundreds of register entries. Recheck source latency and regional coverage from Railway; added heritage stops remain within the separate 2 km walking-stop limit.
