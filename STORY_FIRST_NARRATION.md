# Story-first narration

## Behavior

- In adaptive story mode, routine arrivals remain visual and do not interrupt stories. Manual stop narration remains available. Legacy arrival narration is unchanged when adaptive stories are disabled.
- Navigation retains priority, including near stops. Story eligibility uses time until navigation rather than time until routine arrival.
- The speech API now accepts the `AdaptiveRouteStory` purpose already sent by Flutter. Authentication and quota enforcement remain in place.
- Online, active, on-route walks can replenish a thin story queue without blocking selection or playback. Quiet mode prevents automatic replenishment.
- A refill is eligible below 180 seconds of fresh, unhandled narration in the next 800 metres, estimated using each story's longest variant. The first attempt waits three minutes; later attempts require another three minutes and 150 metres of progress. There are at most six automatic attempts per walk.
- Collection refreshes research the remaining route, include existing topics in the research brief, and merge fresh stories instead of replacing the queue. Packs are capped at 120 stories. Existing expiry, geographic and evidence checks remain enforced.
- Responses for a previous walk or route revision are discarded. Research failures retain the current queue.

## Deployment and field checks

Deploy the API changes before rebuilding and installing the Flutter APK. Neither deployment nor an APK build is performed by these source changes.

On a Munich test walk, confirm that routine arrivals do not cut off a story, turn instructions still interrupt and allow narration to resume, and quiet mode remains quiet. Check speech requests for authorization or purpose-validation failures. Replenishment diagnostics begin with `replenish`; confirm the story count grows when fresh relevant research is available.

Automated coverage includes arrival/navigation priority, quiet mode, stale refill responses, refill request limits, additive remaining-route research, retained expiry and the speech-purpose contract. Real-device audio and live research still require field verification.

## Scope

This is the first reliability and coverage increment, not a guarantee of continuous narration or every requested category. No model migration, model training, camera identification, quizzes or narration-density UI is included. Current-event coverage still depends on finding fresh, locally relevant evidence.
