# Just walking: area-first research

Just walking is a route-free listening session, with Android foreground-service
support for screen-locked walking. It uses
POST /api/area-stories with current GPS, saved interests and previously collected
titles. No walk ID, route geometry, saved walk or selected business is required.
The server adapts the location into a research anchor internally; it never
creates an itinerary or reads a previous walk.

## Research and playback

- First accurate GPS reading starts research immediately.
- The researcher establishes the local area from cited sources, then looks for
  neighbourhood history, development, people, culture and dated local happenings.
- Municipal, tourism, community and local BIA/BID-equivalent sources are requested.
  Their availability is not guaranteed. Events and news retain existing date checks.
- Up to three detailed, sourced stories per batch, initially within one kilometre.
  Automatic research requests progressively broader context: neighbourhood,
  city/town, municipality/county, region/province, then country. This is a research
  policy within the existing bounded provider request, not an exhaustive search
  of every level or polygon-based administrative boundary verification.
  Broader stories require a cited local connection, a scope label and a spoken
  context introduction. Actual subject coordinates are retained separately from
  the local relevance origin used for playback and cache reuse.
  Explicit questions keep their selected scope; POI arrivals are unchanged.
  Missing citations are research failures, not evidence of sparse local history.
  Sparse successful batches can still widen the client search radius to five
  and then twenty kilometres. See
  BACKGROUND_WALKING_AND_COVERAGE.md for bounds and acceptance checks.
- After moving 350 metres, another batch can run, at least two minutes apart.
  When stories run out, another search can run after five minutes.
- Story IDs and normalized titles suppress repeats within this screen session;
  known titles also go to the researcher. This is not semantic deduplication.
- Playback uses prepared narration, not another place lookup. Tapping a row opens
  full narration and clickable sources.
- Only completed audio marks a story heard. Failed audio gets a five-minute
  automatic retry cooldown. Automatic stories have a twenty-second interval.
- Explicit pause and exit invalidate pending results. Android screen lock and
  app switching continue the active walk; other platforms still pause when
  backgrounded. When paused, the screen closes its
  research HTTP client and stops audio. Resume requires the user's action.
- GPS accuracy must be at most 40 metres and readings no older than two minutes.
  A timer advances playback even between fresh GPS updates.
- Research has a 95-second server deadline and a 105-second client response timeout.
  Empty evidence and provider failure are separate states.

## Deployment and field test

Both the API and APK need updating. Existing local-research configuration and
shared-library rights rules still apply; no new variable is required. Newly
researched third-party content does not gain blanket reuse or offline rights.

Start in a new city with no saved walks. Open Just walking and Start listening.
Confirm area stories arrive without generating a route or selecting a business.
Read a story and open its source. Move into a new area and verify new subjects
appear, with already-heard stories suppressed. Pause or exit during research:
late results must not start audio. End a planned walk and start Just walking.

Tests use research fixtures; live model quality and latency require field testing.
No vendor-tour ingestion or durable route-free walk history is added. Android
background behavior requires physical-device verification. Camera behavior is unchanged.

## Editorial Stories (October 2026)

Research now asks for a warm Walk About guide voice, supported detail, a varied
mix of history, people, culture, sports, nature, social change and place-name
origins. Category targets are evidence-dependent, not quotas. No POI listing
description is used as story evidence.

Story records retain audience suitability, an optional sensitivity notice,
grounded uncertainty notes and evergreen/time-sensitive classification.
Only reviewed family stories without a notice autoplay. Sensitive, mature and
unreviewed excerpts remain available by explicit request. Notices are spoken
before the story. Old device-cache entries without these fields do not autoplay.
The shared library and route-generation policy versions have been advanced.

Web research provides Quick, Short, Standard and Deep versions from complete
sentences of the same cited passage. Disputed accounts and legends retain the
full context in every version; some versions can therefore be identical.
Deep playback is request-only. Planned walks use Tell Me More; area-story
details offer a length selector for reading. No extra research/model call was
added, and source reuse/offline rights checks are unchanged.

Tests use 52.2946778, 4.7108732 as a fresh location without a saved route. This is
a fixture, not a production default or a claim about the location's neighbourhood.
Device testing should cover a family story autoplaying, sensitive stories
waiting for Play, the notice preceding audio, interruption by POI arrival, and
offline selection rejecting legacy/unreviewed stories. Live narrative quality,
GPS and locked-screen playback still need physical-device testing.

## Story pictures

Story details, the currently narrated Just walking story, and planned-walk story
selections load pictures independently via POST /api/story-images. Tap a picture
to open a full-screen, pinch-to-zoom view. Creator credits, license and source
links remain visible. Picture failures never stop narration.

The first version resolves lead images from cited Wikipedia articles and P18
images from cited Wikidata entities. It does not search arbitrary websites or
infer that a generic area picture depicts a specific historical event. Images
are labelled source illustrations. Commons file metadata must supply credit,
a supported Creative Commons license (BY, BY-SA, CC0 or public-domain mark),
and trusted HTTPS thumbnail and file-page URLs. Unsupported or missing metadata
produces an empty result. Story reuse permissions are unchanged.

Lookup is limited to six source URLs, three pictures, a twelve-second deadline,
and 256 cached metadata results (six hours positive, ten minutes empty). No API
key or new Railway variable is needed. The API and APK both need deployment.
Actual image coverage depends on story citations; archive searching, automatic
historical comparisons and image offline storage are not included yet.

Provider schema and attribution references:
- https://www.mediawiki.org/wiki/API:Pageimages
- https://www.mediawiki.org/wiki/API:Imageinfo
