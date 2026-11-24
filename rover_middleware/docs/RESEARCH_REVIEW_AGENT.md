# Journey research and review agent

The protected `/admin/research-review` page extends the existing journey inspector. Open a linked journey in `/admin/journeys`, then choose **Research and review this journey**. It uses the same administrator authentication as API usage.

This first milestone combines deterministic evidence review with the existing AI local researcher. It does not train a model, silently edit narration, change routes, deploy code, or run on a schedule. Recommendations require human review. A sourced proposal passing automated checks is not independently verified history.

## Context and operation

Supply the inspector's 16-character journey key, city, region, country, comparison interests and content depth (`quick`, `standard`, or `deep`). Context is explicitly supplied because the inspector does not preserve the complete original profile or coordinates. Do not describe a comparison profile as the user's recovered preferences.

Leave `Places` empty for a review with no research calls. To research, supply at most two confirmed places with `Name`, `Latitude`, and `Longitude`. When the recorded story title differs from the place name, provide `RecordedTitle` and verify the association. The agent checks the title exists in that journey and sends the supplied place identity and interests to `ILocalRouteResearcher`. It reuses `SelectedPlaceStoryGate` before returning the checked narration variant.

Example place entry:

```json
{"Name":"Perth Museum","Latitude":44.901041,"Longitude":-76.2505943,"RecordedTitle":"Matheson House cistern at Perth Museum"}
```

## Bounds and findings

- Latest 500 inspection records, at most 31 days, with truncation disclosed.
- Maximum two research passes, 55 seconds each, 120 seconds overall, cancellation propagated.
- Each pass can make multiple provider calls; this is not a hard monetary cap.
- One concurrent review per API process. Identical complete reviews with unchanged journey evidence are reused for 15 minutes. A multi-replica deployment would need a distributed lock before enabling unattended use.
- Research gets its own trace, separate from the original walk. The report links both, and shows priced model-receipt subtotals without claiming unpriced calls are free.
- Reports and cache references are stored under the usage directory and pruned after 31 days when a new review runs.

Flags include missing recorded narration, missing source links, short deep drafts, generic or failed-search language, overloaded sentences, possible heritage-listing prose, latest failed attempts, and repeated provider operations. Editorial flags are heuristics for listening/review, not automatic factual rejection. Repeated operations alone do not prove waste.

Research paragraphs may contain 15–600 words before the separate spoken edit. Paragraphs over 220 words require a supported spoken edit and cannot fall back to oversized raw narration. Citation-position, URL, geographic, qualification and identity checks remain unchanged. Extraction telemetry records the word bound, longest paragraph and extended-evidence count. This applies to every location, not only the Rat Pack plaque.

Legacy edit events are joined to a final draft only when the title maps to one story identity. Research failures retain diagnostic reasons (for example citation extraction rejecting a paragraph for length). No usable output is not evidence that a place lacks history.

GPS progress, actual listening, precise quiet-stretch lengths, original request-payload equivalence, current source truth, and image licensing are not independently evaluated by this milestone. Those require the relevant playback, routing, request or source evidence.

## Validation and comparison

Run `dotnet run --project Rover.Tests -- "Journey review" "Story inspector" "API usage" "Client journey"`.

The explicit `Rover.Tests --research-review-fixture` mode accepts a JSON fixture through stdin: local output directory, review request and inspection events. Credentials remain in environment variables. This is an opt-in research harness, not part of ordinary tests. Its output includes the report and provider/model receipt data. Mark imported historical artifacts with `EvidenceOrigin`; never present replay-derived records as live production telemetry.

The initial Perth and Vegas comparison used archived inspector/replay inputs and fresh research. The live seven-day inspector searches were empty. Original provider-call history was not imported, so no conclusion about historic API waste is justified.
