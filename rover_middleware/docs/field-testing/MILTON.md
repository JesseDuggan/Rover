# Milton field testing report

**2026-10-09. Status: geographic profile enabled in saved backend configuration for all existing beta testers; deployment pending. Municipal feed remains disabled.** Persistent profile `WALK-CA-ON-MIL-001` covers an 8 km discovery circle centred at 43.5135, -79.8815. Historic downtown Milton and Main Street remain priority areas. This is a readiness report, not a completed walking trial.

## Discovery and evidence

| Measure | Observed result |
| --- | --- |
| Municipal records discovered | Unknown: official service did not complete within two 10-second checks |
| Reliable municipal records retained | Not measured |
| Municipal duplicates or exclusions | Not measured |
| Wikipedia central-query results | 20 returned within the configured circle, each with an extract |
| Wikidata central-query results | 20 returned rows in area; entity types are identity evidence, not narrative history |
| Parks Canada | Successful query, 0 results within the pilot query |
| Finished historical stories | Not measured; source audit does not generate stories |

The disabled municipal audit output contains zeros because no request is attempted; these must **not** be reported as an empty heritage register. The regional-profile audit did not reattempt this disabled municipal feed. Wikipedia took 998 ms, Wikidata 2201 ms and Parks Canada 513 ms. Companion queries use an 8 km radius around the configured centre, capped at 20 results. Provider rows may overlap or represent multiple types for one entity; these are not deduplicated town-wide POI totals. The earlier downtown-only baseline returned 7 Wikipedia results, 5 inside the old area; it is not directly comparable with this larger discovery scope.

Wikidata returned leads including **Charles Hotel** at latitude 43.5141649, longitude -79.881752 and **Milton Town Hall** at 43.5140175, -79.88251. Wikipedia also returned electoral-district articles, illustrating why geotag proximity alone is insufficient to qualify a historical walking story. Context must match the selected interests and be grounded before narration.

## Source and reuse

The [Town of Milton heritage register](https://www.milton.ca/business-development/planning-and-development/heritage-planning/heritage-register/) links to the official [Milton maps and open-data hub](https://discover-milton.hub.arcgis.com/). The official [Designated Heritage Properties item](https://www.arcgis.com/home/item.html?id=cfc1a480977543cfbab034728f0d4690), owned by Milton_Maps, identifies this endpoint:

`https://api.milton.ca/arcgis/rest/services/Datasets/HeritageProperties/MapServer/0`

Published item metadata exposes `ADDRESS_NUM`, `STREET_NAME`, `DESIGNATION`, `HISTORICAL_SIGNIFICANCE` and a designated-property filter. The adapter is configured from that metadata, but live schema, projection and geometry compatibility remain **unverified** until the endpoint responds.

The item links the [Milton disclaimer and terms of use](https://discover-milton.hub.arcgis.com/pages/disclaimer-and-terms-of-use), including the Open Government Licence Milton. The configured adapter preserves attribution and record-level source links. The [official heritage StoryMap](https://storymaps.arcgis.com/stories/18052a440fb9498cbd247ad5105b98f0) provides additional editorial leads, but is not scraped as a substitute geographic feed and its images are not assumed reusable.

## Journeys and narration

Automated tests confirm that disabled or sparse municipal data does not remove existing ordinary POIs, and that 20/60/90-minute mock plans continue to work through the shared architecture. After deployment, Wikimedia and existing ordinary discovery can operate for beta testers without the Milton municipal feed or new personal enrollment. Added heritage stops retain the separate 2 km limit. **Live journey quality, generation latency, finished story count and on-device marker placement remain unmeasured.**

The current ElevenLabs narrator and audio-cache behavior are unchanged. Existing regression tests pass, but no real Milton narration was generated or listened to. Field trials must verify voice quality and story continuity around POI entry and exit.

## Missing information and feedback

The immediate prerequisite is a successful service query from Railway with WGS84 point geometry and the configured fields. Keep `Markets__milton__Datasets__0__Enabled=false` until that passes. Do not fabricate coordinates or import unverified copies to fill the gap. Contact the municipal data publisher if the endpoint remains unavailable.

No tester feedback has been collected by this audit. Use the [pilot feedback workflow](../ONTARIO_FIELD_TESTING.md) for short and 60/90-minute Main Street journeys; feedback and journey diagnostics carry `WALK-CA-ON-MIL-001`. Verify heritage descriptions, local people and events with citations, check pedestrian entrances and private-property boundaries, and compare sparse-source route quality with the existing ordinary POI experience.
