# Sin City Secrets draft test build

## Find it
Walk → Explore Tours → Show adults-only tours (21+) → confirm everyone listening is 21+ → Sin City Secrets.
The opt-in is session-only and starts off whenever this catalogue screen is opened.

Preview walking route calculates Google pedestrian directions. Use this walk opens the existing prepared-walk player: rehearse at home or use GPS on foot, pause, skip, ask a question, resume, take photos/videos, and open memories.

## Content and geography
Eight supplied chapter themes are grouped at four distinct triggers: Golden Gate, Binion’s, Block 16, Mob Museum. Binion’s comes before Block 16 to reduce backtracking. Arizona Club is part of the demolished Block 16 district, not a separate current entrance. Roxie’s and the burlesque chapter explicitly describe regional history. The core route does not send walkers to those sites.

The bundled path is only an anchor list and cannot be launched directly from the catalogue. A successful pedestrian route preview is required. Existing Golden Gate and Mob Museum coordinates/photos are reused; Block 16 uses the marker coordinates; Binion’s uses the directions linked from its official website. Field verification remains pending.

Railway route check, 2026-11-11: 858 m, 13 walking minutes, 8 visiting minutes, four stops and 57 route coordinates. Indoor visits are excluded. Do not advertise a 2–3 hour walking duration.

## Research and playback
Historical narration and sources are bundled in LV-05.json. Launching this tour does not call story research or approach-story discovery. Speech synthesis may still call the existing audio service. Follow-up questions remain an explicit research action. Existing tours retain their current preparation behaviour.

This first draft uses fixed narration; changing the interest selector does not rewrite these eight chapters. The shared preview still uses walking pace and time budget. Do not describe this draft as fully personalized narration.

## Review boundaries
Status remains draft. No automatic approval or public catalogue promotion is implied.
No current club recommendations, hours, prices or admission claims have been added. The separate nightlife excursions from the supplied brief need current venue checks and a separate UI before release. No archival photographs are embedded without reuse rights; existing credited tour photos are reused.

The app has no global family-mode flag in its preferences. This version keeps adult tours out of the default catalogue and requires confirmation that the entire listening group is 21+. It does not infer ages or modify general story safety settings.

## Checks
17 focused Flutter tests passed: adult opt-in/cancellation, draft data loading, existing Fremont personalisation, catalogue, capture, story interruption/resumption and questions.
Live existing Railway route endpoint returned all four stops successfully. No backend change or deployment is required for this app-only draft.

## Sources
- https://www.goldengatecasino.com/our-story/
- https://www.binions.com/history.php
- https://www.hmdb.org/m.asp?m=47859
- https://www.unlv.edu/news/article/my-nevada-5-prostitution-las-vegas
- https://burlesquehall.com/about/frequently-asked-questions-faq/
- https://themobmuseum.org/digital-archive/this-building-of-ours/
- https://themobmuseum.org/underground/
