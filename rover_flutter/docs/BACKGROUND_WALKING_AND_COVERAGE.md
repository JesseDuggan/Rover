# Android background walking and area coverage

## Android walking

Planned walks and Just walking opt into Geolocator's location foreground service.
The service displays an ongoing Active walks notification and holds a CPU wake
lock, not a screen wake lock, while the location stream is subscribed. Existing
screen-awake behavior is separate. Start the walk with the app visible and grant
location permission. Android 13+ notification permission is requested so the
notification can be shown; denial does not prevent the foreground service.

Just walking no longer pauses on Android screen lock or app switching. Explicit
Pause, leaving Just walking, and disposal still cancel its GPS stream, research,
and audio. Planned story polling continues on Android without relying on rendered
frames and synchronizes navigation and arrival narration from the current session.
Ending or pausing a planned walk retains its existing location/audio cleanup.

This does not restart a force-stopped app, survive every manufacturer battery
restriction, or record indefinitely after the walk ends. Camera and microphone
features have not been enabled in the background. No always-on background location
permission or automatic boot restart is requested. Native audio remains tied to
the existing app engine. iOS background narration and media-session lock-screen
buttons are not implemented by this change.

## Story and POI audio handoff

Planned walks check arrival and navigation audio every two seconds independently
of story playback, including when no screen frames are rendered. A verified POI
entry interrupts the current story, announces arrival, and plays the POI's
narration once. The interrupted story then resumes automatically when navigation
allows it. Only the interrupted sentence is repeated, not the whole story.

Automatic starts require room for the next sentence plus the navigation buffer,
not the entire story. If the server cannot select a full-length variant, the app
can select a sourced, unexpired story from the current pack within its playback
window. An already-started story can finish beyond that window. Quiet mode,
explicit user pauses, sensitive-content consent, skipped/heard exclusions, and
verified arrival checks remain in force. POI information is not used as filler
between stops. These playback changes require an APK rebuild, not an API deploy.

Phone acceptance: start a story while approaching a POI, enter its geofence,
listen for arrival and POI narration, then verify automatic sentence-level
resumption. Repeat with the screen locked, repeated GPS readings, and a manually
paused story (which must remain paused after the POI narration).

## Sparse area research

Just walking starts at 1000 metres. A successful batch with fewer than two new
stories queues a 5000 metre search, then at most a 20000 metre search. There is a
minimum 20-second interval between expansion requests, and no parallel expansion
while narration or research is active. Provider errors do not trigger widening.
After the bounded expansion, normal refresh cooldowns apply. Movement of at least
1000 metres from the coverage origin resets the scope to local research.

The UI explains sparse verified coverage without asserting that local history
does not exist. Collection metadata carries searchRadiusMeters. Each collected
story retains its own coverage radius for playback eligibility and a local,
surrounding-area, or regional-context label. Regional narration has a spoken
context introduction. Story anchors stay at their real locations and citations
and expiry checks remain mandatory.

POST /api/area-stories accepts optional searchRadiusMeters: 1000, 5000, or 20000.
The default remains 1000 for old clients. Other values are rejected. Responses
include the accepted radius. The research prompt and server distance validation
use that radius only for area-first research; planned route packs keep their
existing local radius. This is sparse-coverage handling, not a rural classifier.
Deploy the API and rebuild the APK together.

## Acceptance checks on a real Android phone

1. Start each walking mode while visible; confirm the ongoing notification.
2. Lock for at least ten minutes, crossing a story and POI boundary. Verify GPS,
   narration completion, subsequent stories, and planned arrival guidance.
3. Switch apps, interrupt with a call, and repeat with weak network access.
4. Unlock, pause or end, and confirm the notification and GPS stop. Start another
   walk without reinstalling. Repeat after denying notification permission.
5. In a sparsely documented location, check local then wider coverage messages,
   region labels, spoken context, real anchors, and no unsupported nearby claims.
6. Move into a different local area; verify local scope is restored. Simulate a
   provider failure and confirm it is not described as a lack of local history.

Automated checks cover the platform settings, sparse expansion limits, failure
behavior, explicit API bounds, retained coordinates, narration context, and the
existing pause/disposal/late-result tests. They do not establish physical Android
background behavior or live source quality.
