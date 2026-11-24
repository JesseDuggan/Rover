# Shared story research and review

Regular walking packs use `AdaptiveRouteStoryEngine`; area chapters use `AreaStoryService`. Journey Lab selected POIs use `/api/drive-stop-story`. Prepared tours and custom walks use `/api/place-story`. Both selected-place endpoints use `DriveStopStoryService` and `NearbyStoryResearch`. These paths share `ILocalRouteResearcher`, the story library and the OpenAI evidence/classification pipeline. This does not replace route selection, Google routing, speech generation or playback.

## Geographic context

For live area research and collections requesting neighbourhood chapters, `OpenAILocalRouteResearcher` performs one bounded Google reverse-geocoding lookup before its research/recovery attempts. It supplies street, neighbourhood (when actually present), district, locality, region and country as context. A district is not relabelled as a neighbourhood. Historical or colloquial names still require cited evidence. Lookup failure is observable and does not establish absence of local history. The explicit area radius still applies to each subject's own coordinates, including cached stories.

Configuration uses `Rover:ResearchGeography:ApiKey`, then `GOOGLE_GEOCODING_API_KEY`, `GOOGLE_MAPS_SERVER_API_KEY`, `GOOGLE_PLACES_API_KEY`, or `GOOGLE_MAPS_API_KEY`. The selected key must permit Google's Geocoding API. The client records the purpose `Resolve research neighbourhood`. It stores neither the key nor request URL in usage events. Calls are bounded to six seconds, do not run on each GPS update, and are not repeated by the research retry. Location metadata is context, not historical evidence. Google address data is not persisted as a new geographic database.

## Narration

`StoryPreparationPolicy.NarrationFocus` is supplied to both research and spoken editing. It asks for a supported local episode or visible detail rather than address/licence verification, chain-wide directory facts or research-process commentary. It permits a short answer when evidence is thin and does not invent an episode to satisfy deep length. The reviewer flags process language for human assessment; automated review is not historical verification.

## Story value and bounded recovery

Automatic OpenAI preparation for selected places, area chapters and regular walking research requires a story-value assessment. The classifier identifies a local episode, meaningful visible detail, natural process or community connection and selects a numbered supporting sentence, which the server resolves to exact cited text. Directory-only and insufficient material stays out of automatic narration. This is an automated editorial assessment with a substring evidence check, not independent historical verification. Explicit factual questions remain exempt so a visitor can ask about practical details.

An empty selected-place result gets one targeted recovery within its existing total time budget. A failed recovery returns no narration, rather than the rejected generic version. Short accepted stories do not trigger another search just to reach a word count. Automatic area research also retains its single bounded recovery. Existing deterministic factual/live-event composers and curated narration retain their own evidence policies; this does not retroactively rewrite saved stories. The map and route remain unchanged. Legacy cached research without the new assessment is not reused for requests requiring it.

The inspector records story-value eligibility, map-only outcomes and precise geographic rejection codes. Geographic connections must still appear in the cited passage; whitespace normalization is allowed, invented neighbourhood names or paraphrased connection evidence are not. Town and street context may be used when no named neighbourhood exists. Selected-place delivery is recorded only after recovery chooses the final response.

## Directory prose and complementary chapters

The shared classifier identifies subject scale (area or individual place) and chapter role (overview, episode, tradition, landscape or biography). Neighbourhood-only research rejects individual-place chapters and enforces at most one accepted overview; further chapters need another role. This classification is automated and is not proof of semantic uniqueness. An existing, bounded spoken-edit call is reused; no extra routine model call was introduced. Before automatic narration variants are assembled, directory-administration claims are removed (for example, records confirming an active food premises). Historic licensing disputes are not classified as administrative filler. If at least half the claims are administrative, or removal could strip a disputed-history qualification or folklore context, the candidate is rejected instead of narrating hollow fragments or silently changing its meaning. Evidence remains on the source card; spoken variants reference the retained claims.

A conservative lexical overlap check suppresses heavily repeated chapters within a collection and across reused/fresh research, even if titles differ. It applies within one kilometre and excludes time-sensitive stories. Merely sharing a street or topic is insufficient; the existing classifier is responsible for semantic variety. This heuristic does not prove all semantic repetition has been removed. Inspector events explain trims and suppressed chapters, and review findings expose overlap decisions. The versioned automatic cache requires the current editorial policy, so previously accepted research cannot bypass these changes. Saved phone narration and curated scripts are not retroactively rewritten.

## Review interpretation

Automatic narration requires a supported spoken edit with a purpose label for every sentence: story, source administration or directory. Administrative sentences are excluded before assembling narration variants. The existing bounded sentence repair preserves the purpose label; failed edits do not fall back to raw research prose for automatic requests. Explicit factual questions retain their existing evidence-answer behaviour. These labels are model assessments with deterministic checks, not independent semantic or historical verification.

`Delivery contract` identifies requests using explicit final-output telemetry, including empty responses. `Delivered story` records accepted selected-place narration, returned area stories, or stories in a successfully stored route pack. This means API-returned/prepared, not played or heard.

When explicit delivery telemetry exists, editorial counts and checks use the latest returned narration per story ID. Intermediate story groups and rejected events appear separately. Legacy traces without delivery markers retain draft checks and are clearly labelled as such. Mixed/partial retention windows cannot establish whole-journey coverage. Different story IDs from separate regenerations are still distinct recorded stories; the review does not reconstruct the phone's current saved pack.

The review remains proposals-only. It does not change routes, rewrite saved stories or autonomously deploy improvements. Provider-call counts flag investigation; they do not by themselves prove waste. Playback and quiet stretches require GPS/audio events and are not inferred from research success.
