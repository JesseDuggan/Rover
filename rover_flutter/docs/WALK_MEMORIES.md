# Walk Memories

## Current device-local phase

- Live walk toolbar: Walk memories opens the gallery for the current route.
- Capture a photo or up to 60 seconds of video, preview it, add a caption and optionally select a place.
- Capture location uses one foreground GPS request only when permission is already granted. No simulated position or route-stop position is substituted. Missing permission, timeout, stale readings or accuracy worse than 100 metres leave location absent without blocking capture.
- Video location refers to the start of recording, not a recorded movement track.
- Route memories shows the planned route and selectable capture markers. Captures without a GPS fix remain in the gallery.
- Saved walk details opens Route memories. A persistent local alias connects newly restored preview session IDs to the original route ID, including previews of saved previews.
- Profile > Walk Memories > Adventure history groups memories by route. Walk history also links to this view. Multiple outings on the same saved route are currently grouped together, not separated into visits.
- Old unlinked captures remain available in All memories. No location or route is inferred retroactively.
- Media and versioned JSON sidecars stay under the backup-excluded walk_memories application directory. This is device-local storage, not account-specific cloud storage. Uninstalling the app can remove it.
- No media uploads, sharing or backend deployment are part of this phase.

## Agreed community direction

Users should eventually publish an adventure containing its route, stories, pictures and videos to either the signed-in Walkabout community or selected friends and family. Keep all memories private until explicit publishing. Signed-in membership is required for community reading and interaction; a shared URL must not bypass audience checks.

Before enabling sharing, implement server-side ownership and audience authorization, membership/invitations for selected recipients, revocation, location redaction (especially start/end locations), media validation and storage, deletion, reporting and blocking. Do not implement audience labels without enforceable access controls. Comments require moderation controls; AI moderation and video editing are later phases. Video length remains 60 seconds for the initial community release.

## Verification

Focused automated tests cover metadata persistence, caption updates, legacy captures, missing GPS, preview alias chains across restarts, history grouping and route filtering, alongside account library and active-walk regression tests.

On-device acceptance: capture from a live walk, save it, close and reopen the app, open the saved route's memories, tap its map marker, edit the caption/place, and repeat with location permission denied. Verify scanning and capture can be opened successively without camera contention. No automated test substitutes for these hardware checks.
