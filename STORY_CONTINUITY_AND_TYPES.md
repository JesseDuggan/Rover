# Story continuity and curation

## Munich field findings

The September 29 screenshots show four stories on revision 1 followed by an empty generating pack on revision 5. A separate revision 4 pack has no accepted research. They also show playback held while on-route with a zero-metre navigation instruction. The screenshots establish these symptoms, not the exact instruction type or every reason for the route changes.

## Changes

- On a new collection revision, the API looks back through up to 20 previous revisions for the latest pack. It carries fresh cited stories within 225 metres of the new route and recalculates their segment windows. It preserves expiry and listening/saved history. Carried stories are published while research runs and retained if research finds nothing new.
- This is geographic revalidation, not blind reuse of old distance windows. Expired stories and subjects away from the new route are excluded. A brief empty state can still appear before the new route plan is ready.
- Off-route autoplay uses existing pack stories near the user's actual position, within 225 metres and with reported GPS accuracy of 40 metres or better. Expired, handled and uncited stories are excluded. Quiet mode still applies. It does not yet research a completely new off-route neighbourhood.
- Departure, straight-ahead and the initial unspecified instruction do not reserve story time as if they were turns. Real turns remain protected; a genuine zero-distance turn still blocks narration.
- Curation explicitly seeks an opening chapter near the first remaining section and a varied mix. Tool/call budgets and citation/location validation are unchanged. More categories do not guarantee evidence for every category.

## Story types

The research/classification vocabulary now supports current events and dated recent news, place history, fun facts, people, then-and-now, architecture, art/music/culture, food/drink, attributed legends, nature, hidden gems, everyday local life, film/books/pop culture, and sourced visible details (look closer).

Recent news requires a publication date present in the evidence, no more than seven days old, and receives a short expiry. Scheduled events retain venue/date checks. Legends must be presented as attributed folklore rather than historical fact.

Camera-triggered look-closer interactions and connected interactive adventures remain separate implementation work. This change does not claim image recognition or create fictional clues in factual narration. The research prompt structure follows the [OpenAI prompting guidance](https://developers.openai.com/api/docs/guides/prompt-engineering); output still passes application evidence checks.

## Verification and rollout

Regression coverage includes reroute retention during generation, empty research, expiry/location rejection, listening history, off-route GPS selection, rejoining, departure instructions, category acceptance and stale/undated news rejection. Model calls in tests are fixtures, not live research.

Deploy the API and rebuild/install Flutter together. Neither deployment nor APK packaging is automatic. Field-test a short detour, rejoin, route change and quiet mode; check whether fresh nearby chapters survive regeneration. Continuous coverage, every source's accuracy and real-device audio still require field testing.
