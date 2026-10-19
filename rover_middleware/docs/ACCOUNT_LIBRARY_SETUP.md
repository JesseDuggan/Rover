# Walkabout Accounts and Personal Library

## Release Status

Account sign-in is disabled by default. The code does not create an AWS user pool,
deploy the API, or enable sign-in for testers. Configure Cognito and complete the
device acceptance checks below before enabling this feature.

The current API source is `Rover-diagnostics/rover_middleware`. The current mobile
source is `Rover/rover_flutter`. Build and deploy both changes together.

## Cognito Setup

Use an Amazon Cognito **user pool** and its managed login/hosted UI. Configure:

- Email sign-in, self-service registration, required email verification and email
  account recovery. Configure email delivery and test it before inviting users.
- A public native-app client **without a client secret**.
- Authorization code grant with PKCE; enable `openid`, `email`, and `profile` scopes.
- Callback URL: `ai.myrover.rover://oauthredirect` (exact match, two slashes).
- A Cognito managed-login domain. Associate it with the public client.
- Appropriate password policy, abuse protection, refresh-token lifetime and MFA
  policy for your release. Do not enable implicit grant for this app.

Create account and password recovery happen in Cognito's browser flow. Walkabout
does not receive or store passwords. API requests use **access tokens**, not ID
tokens. The API verifies signature, issuer, expiration, token use, client ID and
the user-flow scope. An authenticated token never substitutes for the existing
beta-access key while the app is in beta.

## Railway Variables

Use ASP.NET double-underscore configuration names:

```text
Rover__Accounts__Enabled=false
Rover__Accounts__Issuer=https://cognito-idp.REGION.amazonaws.com/POOL_ID
Rover__Accounts__ClientId=PUBLIC_NATIVE_CLIENT_ID
Rover__Accounts__RedirectUri=ai.myrover.rover://oauthredirect
Rover__Accounts__DatabasePath=/data/accounts/library.db
Rover__Accounts__ProfileLimit=3
Rover__Accounts__WalkLimit=3
```

Replace REGION, POOL_ID and PUBLIC_NATIVE_CLIENT_ID using the actual user pool.
These identifiers are public configuration, not passwords. There is no AWS
administrator credential or Cognito client secret in the APK.

Ensure `/data` is the mounted persistent Railway volume. Only then set Enabled to
true and deploy. Invalid enabled settings fail startup. Disabled accounts leave
guest journeys unchanged. The app retrieves the public configuration from
`GET /api/account-library/config`; no Cognito identifiers need to be baked into
the APK.

## Data and Behavior

- Cognito owns login identities. The personal library keys each owner by a hash
  of the verified issuer and case-sensitive subject. Geographic pilot IDs and
  legacy guest profile IDs are never authentication identifiers.
- SQLite persists named walking profiles and saved route snapshots. Immediate
  write transactions enforce per-account caps. Revisions detect stale edits.
  The deployment must remain a single service instance using this volume;
  move the library to a shared database before scaling across independent volumes.
- Profiles save walking interests, pace, time, accessibility, content and audio
  preferences. They do not copy first name, onboarding state or API settings.
- The first profile is the default. A default is applied on sign-in. Selecting
  another profile changes future walking preferences, not the current journey.
- Guest preferences are retained securely before profile application and restored
  on sign-out. Guest journeys are not silently claimed or uploaded.
- Save current walk captures the route, stops, and story pack already available.
  It does not start research. A missing story pack does not prevent saving a route.
- Opening a saved route creates a **new** server session, route ID and stop IDs.
  Arrival and playback progress reset. Active/paused walks cannot be replaced.
  Saved story text is an archive; a replay uses the existing research/audio cache
  pipeline and does not inject archived client data into shared story caches.
- Saving is not an offline-map download. Source URLs, business details, access
  conditions and routes can become stale; verify them when walking again. Review
  provider-specific retention requirements before broad release.
- Mobile access/refresh tokens use platform secure storage. Android backup rules
  exclude that storage. Sign-out clears local credentials and hides library views;
  it does not globally revoke other devices or delete the Cognito identity.
- Existing legacy `/api/accounts` development scaffolding is not used by this
  personal-library feature. Account deletion/export across Cognito and legacy
  guest records is a separate lifecycle feature, not implied by deleting a saved item.

## Acceptance Checks Before Inviting Testers

1. Create an account on a real Android device, verify its email, sign out, sign
   back in, and recover a forgotten password through the hosted flow.
2. Test cancel/back from the browser and failed/offline login. Guest walks must
   remain usable. Confirm no password or token appears in application logs.
3. Save City, Food and Nature profiles. A fourth must be refused. Rename, update,
   select and delete profiles; confirm interests drive the next walk.
4. Sign in on a second device. Verify the library survives an API restart and
   the default profile is available. Test conflicting updates from both devices.
5. Save three walks. A fourth must be refused without deleting existing walks.
   Delete one, then save another. View archived stops and any available stories.
6. Preview a saved walk after an API restart. Confirm fresh lifecycle state,
   destination preservation, navigation, POI narration and story scheduling.
7. Sign out and sign into another account. Neither account can read or mutate
   the other's library. Check expired tokens, refresh and browser cancellation.
8. Back up the persistent database using SQLite's backup facilities or a
   consistent volume backup. Do not copy only the live `.db` file without its WAL.

No live Cognito pool or production credentials are required for automated tests.
The test suite uses local signing keys and temporary databases.

## Local Verification (2026-10-10)

- Release API/test build: succeeded with zero warnings and errors.
- API regression suite: 215 passed, zero failed.
- Flutter regression suite: 329 passed, one existing skipped test, zero failed.
- Static analysis of the account module, tests and modified navigation/controller:
  no issues found.
- Covered phone/tablet layouts, profile-field isolation, secure token restoration,
  late-login/sign-out races, JWT rejection, ownership, persistence, limits, stale
  edits, destination preservation and new-session replay.
- Not yet verified: a real Cognito sign-up/email/recovery flow, physical-device
  browser callback, release APK packaging, or production deployment.
