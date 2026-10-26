# Story sharing and local GPS trails

## First increment

- Current story: Share story with friends opens the existing private-sharing composer.
- Text, HTTPS source references, sensitivity notices and uncertainty notes are copied,
  not regenerated. Recipients can read the story or use device read-aloud with Stop.
- Coordinates are omitted unless location sharing is selected. Story text itself
  can name places regardless of the coordinate setting.
- Drafts are private until explicit confirmation and publication. Existing friendship
  grants, blocking, deletion and account-switch protection apply to stories too.
- The client checks that the backend retained stories before publishing, preventing
  silent loss when used with an older backend.
- Read-aloud stops on leaving/backgrounding the viewer, sign-out or failed access
  refresh. The viewer rechecks authorization before playback and every 20 seconds.
- Shared read-aloud requires the current walk to be paused. This version uses device
  speech, not exported MP3/MP4 or a copy of the original generated audio.

## GPS trail foundation

- Record GPS trail is off by default. It uses the existing live GPS stream, not an
  additional location subscription. Enable it on the walk screen.
- View recorded GPS trail shows the current session's actual fixes. Gaps are separate
  selectable segments and are not joined by invented routes. Local trails can be deleted.
- Records include UTC time, accuracy, coordinates, segment and canonical saved-walk ID.
- Ignore mocked, stale, invalid, poor-accuracy and implausible-jump fixes.
- Record at most once every five seconds, suppress stationary jitter, batch disk writes
  every 20 seconds and flush on stop/pause. A force-close may lose the final batch.
- At most 24,000 fixes per session. No trail upload or automatic sharing.
- Recording is not automatically re-enabled after an app restart; enabling again
  appends a new segment. Location permission and OS background limits still apply.
- Files live in application support / walk_trails. Existing planned route geometry
  is not used as a substitute for missing GPS history.

## Next increments

Full-walk replay, synchronized story/video events, trail-sharing consent,
MP3/MP4 export and friends-only chat are not included in this increment.
Historical-session browsing will connect the local trail files to saved walks;
the current view opens the active session's file only.

## Two-phone acceptance test

1. Install the new APK on both phones and sign in to accepted-friend accounts.
2. Open a walk story, tap Share, choose the friend and confirm. Leave locations off.
3. On the receiving phone, open Shared walks and expand the story. Verify sources,
   text, Read story aloud and Stop. Background the app and verify narration stops.
4. Remove the share on the sending phone; verify access disappears on refresh.
5. Start a walk, enable Record GPS trail and walk outdoors for a minute. Open the
   timeline icon. Verify actual fixes, then pause/resume and check segment separation.
6. Delete the local trail; verify recording switches off and media remains intact.
