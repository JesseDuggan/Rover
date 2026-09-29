# Beta Speech and Story Catch-Up

## Changes

- `/api/speech/render` accepts the existing valid beta key when there is no
  resolved account. It does not create an account or change account/profile
  authorization. Missing/incorrect keys remain unauthorized, and development
  identity headers do not authenticate outside Development.
- Beta speech uses a fixed quota identity and serializes rendering for that
  identity, preventing concurrent requests from racing the daily usage check.
  `ElevenLabs__DailyCharacterLimitPerUser` is shared across beta clients (default
  12,000 characters/day). The existing usage store is process-local: restarts
  reset it and multiple replicas have separate counters. This is not a durable
  billing cap. Keep provider-side spending controls in place.
- The Flutter scheduler remembers stories encountered within their normal
  route-progress window. After navigation or audio delays, they can catch up
  within 150 route metres beyond that window. This allowance is additional to
  the existing history-window allowance, not an unlimited geographic radius.
  Navigation/arrival priority, expiry, skips, completion exclusions, and manual
  pause remain respected. Deferred candidates reset on route revision changes.
- Interrupted automatic stories must still be fresh, active, and within the
  bounded catch-up window before automatic sentence-boundary resume.
- The app reads and caches explicit backend playback outcomes. Labels separate
  Played, Skipped, Dismissed, Paused, Interrupted, and audio failure. Legacy
  exclusion IDs without completion evidence say Previously handled.
- Local story research, evidence checks, and online-only caching restrictions
  are unchanged.

## Rollout

1. Deploy the API changes first. Continue using the existing server beta key and
   matching Flutter beta key; do not send provider keys to the app.
2. Build/install the updated Flutter APK using the existing Railway build script
   and a new build number. No APK was produced or deployment performed by this
   change. Keep the Gradle upgrade separate.
3. Verify speech requests no longer return 401 with the valid beta key. Without
   a configured speech provider, the response requests device speech fallback;
   HTTP 200 alone is not evidence of premium audio.
4. Walk through a turn during a story, then clear the turn. Confirm automatic
   resume while still relevant, no replay after completion, no auto-resume after
   manual pause, and no late playback after leaving the catch-up window.
5. Check skipped stories say Skipped, completed stories say Played, and expired
   stories remain silent. Listen for the sourced local business/current stories
   as before; this patch does not broaden their factual claims.

## Verification

- Backend: 161 tests passed.
- Flutter: 206 tests passed.
- Release API build: zero warnings and zero errors.

Backend tests include beta-key authentication, bearer-key compatibility,
cross-client quota sharing, non-development authentication behavior, account
export isolation, and invalid speech-purpose rejection. Flutter tests cover
bounded catch-up, expiry, explicit skips, outcome labels, legacy state, and
offline outcome persistence, alongside the existing interruption/fallback suite.

Real GPS, installed beta credentials, provider audio, and background playback
still require the phone acceptance check. Route duration/backtracking issues
shown in field screenshots are separate from this patch.
