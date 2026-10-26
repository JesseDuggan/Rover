# Friends foundation

Friends uses the existing Cognito access-token authentication and the same persistent
SQLite database configured by `Rover:Accounts:DatabasePath`. No new API keys or
Cognito client are required. Tables are created additively at startup.

## Included

- Opt-in member profile with unique, case-insensitive username and editable display name.
- Exact username lookup; no email search or public member directory.
- Mutual friend requests, accept/decline/cancel, remove, block/unblock and reports.
- Revocable, rotating invitations valid for seven days. Only a SHA-256 digest of
  the invitation code is stored. Resolving a link never sends a request or grants access.
- A public `/invite#code` landing page that displays no member information and opens
  the app through `ai.myrover.rover.friends://friends/invite?code=...`.
- Durable per-account rate limits: 90 calls/minute, 20 requests/day, 10 invitations/day,
  10 reports/day; at most 200 active connections including pending requests.
- A 24-hour cooldown after a declined, cancelled, removed or blocked connection.

## Boundaries

Friendship does not share any walk, location, picture or video yet. Memories remain
on the device. Selected-friend sharing and community publishing are subsequent work.
Usernames cannot currently be changed. There are no notifications, direct messages,
comments, AI moderation, or administrator moderation UI in this release.

Reports are persisted in `member_reports` with pending status. Operators must review
them through a controlled administrative process; submission does not guarantee a
response or automatically restrict another account. Do not expose the database or
reporter identities to members. Before wider public rollout, add a moderation queue,
community rules, account deletion/export, and an abuse-response owner.

## Two-account acceptance test

1. Install the new APK without uninstalling the old app (to preserve local memories).
2. Open Profile > Friends. Sign in and claim a username/display name on both accounts.
3. Find the other exact username, send a request, then refresh Requests as the recipient.
4. Accept it. Refresh Friends on both devices and confirm the relationship appears.
5. Create an invitation and copy its link or scan its QR with the phone camera. Review
   the sender in Walkabout. Verify no new request is sent until Add friend is tapped.
6. Revoke the invitation; opening it must no longer resolve the sender.
7. Block the friend. Refresh both devices: the friendship disappears, lookup fails,
   and new requests cannot be sent. Unblocking must not restore friendship.
8. Sign out: no previous profile, request, invite QR or friend list remains visible.

The invitation URL scheme is separate from Cognito's callback. iOS scheme registration
is included but requires an iOS device build/test. Android QR/deep-link delivery also
requires device verification; widget tests do not prove OS link dispatch.

## Verification

`dotnet build Rover.Tests/Rover.Tests.csproj -c Release -m:1`

`dotnet Rover.Tests/bin/Release/net10.0/Rover.Tests.dll Friends`

The Personal library authentication test also covers friends endpoints and rejects
anonymous, expired, malformed, wrong-issuer, wrong-client and ID tokens.

Flutter: `flutter test test/friends_test.dart`.
