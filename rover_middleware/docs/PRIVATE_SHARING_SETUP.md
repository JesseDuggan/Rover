# Private walk sharing

Friends is accessible from the main app bar. Open a saved walk or its route
memories and choose Share, select accepted friends and individual memories,
then confirm. Nothing uploads before confirmation. Shared copies are available
from Friends > Shared walks, with separate received and sent tabs.

## Privacy

- Requires a signed-in account and Friends profile. There are no public links.
- Route and media locations are omitted by default, enforced server-side.
- Explicitly including locations shares the route geometry and selected media
  coordinates. Review the map before sharing, particularly routes near home.
- Files are re-encoded with FFmpeg to remove embedded metadata. Visible faces,
  addresses, identifying scenery and recorded speech are not redacted.
- Only selected accepted friends can access published shares. Drafts are private.
- Every media request checks authorization. Removing or blocking a friend revokes
  access; becoming friends again does not restore the old share.
- Viewers periodically revalidate access and pause on app backgrounding. Already
  downloaded bytes, screenshots or external recordings cannot be recalled.
- Sender deletion removes the server copy, not the original local memories.

## Operations

The existing account SQLite database stores grants and metadata. Media lives in
`shared-media` beside that database, under the existing persistent Railway volume.
Deploy one replica using the existing volume; do not use ephemeral storage.
The Docker runtime installs FFmpeg/ffprobe. Both must be on PATH for local hosting.

Limits: 10 selected memories, 20 recipients, 20 shares/drafts per owner, 12 MiB
photo input, 64 MiB video input, 60-second videos, 128 MiB stored media per owner.
Global processed media storage defaults to 512 MiB, configurable with
`Rover__Sharing__StorageLimitBytes`. Allow additional space for temporary uploads,
the database, and other existing assets. Upload processing is serialized.
Expired drafts (24 hours) and orphan files are cleaned at startup and on upload.
Users can remove unfinished drafts from Sent. No public community publishing or
automated moderation is introduced by this feature.

## Acceptance test

1. Sign in on two devices/accounts, create Friends profiles and accept a request.
2. Share a saved walk with one photo and one short video. Leave locations off.
3. On the recipient, open Friends > Shared walks, refresh and open the share.
   Confirm both media play and no map/location is displayed.
4. Repeat with locations enabled and verify the route and capture pins.
5. Remove the share, or block/remove the friend. Refresh recipient access and
   confirm it is unavailable, including the media viewer after revalidation.
6. Re-add the friend and confirm old shares remain inaccessible.
7. Confirm an unrelated third account cannot access the share or its media.

Backend tests exercise authorization, consent, quota enforcement, revocation and
real FFmpeg metadata stripping. Set TEST_FFMPEG and TEST_FFPROBE to executable
paths when these tools are not on PATH. Device testing remains necessary for
real upload speed, video playback and two-account interaction.
