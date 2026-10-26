# Memories usability update

## Entry points

- Main top bar: photo-library icon opens Memories.
- Memories: All memories / By walk tabs and a Share action on both tabs.
- Specific walk: Route memories remains available from saved-walk details.
- Active walking screen: camera-plus opens capture directly, linked to the current
  walk. The existing Camera view remains the place-identification experience.
- Saved memory viewer: Share memory selects that item in the sharing composer;
  Attach to saved walk opens the account's saved-walk picker.

## Behaviour

Standalone sharing uses the existing authenticated shared-walk API with an empty
route. It requires at least one selected memory. Locations default to off and only
explicitly selected files are uploaded after confirmation. Sharing from a specific
walk continues to support its route. No new backend deployment is required.

Attaching updates private local metadata only. Capture time, actual GPS position,
accuracy, caption and original media bytes are preserved. A previous place label
is cleared when changing walks. Session aliases are resolved to the original walk.
Attaching does not modify a previously published shared copy.

Android video thumbnails are extracted locally with MediaMetadataRetriever on a
single background worker. Files must be inside the app's private files/cache
directories. The gallery keeps at most 32 thumbnail futures in memory; no video
player or audio is started. Unsupported platforms and unreadable files retain a
play-icon fallback. This release targets Android; iOS thumbnail support is pending.

## Verification

- 51 focused account, friends, sharing, memories and active-walk tests passed.
- 35 UI/navigation/contrast and memories-usability tests passed (8 overlap the
  focused suite, giving 78 distinct tests).
- Targeted Dart analysis has no issues.
- Test standalone sharing on two accounts, both with locations off and on.
- Attach an existing photo to a saved walk, reopen Route memories, and confirm it
  appears there with its original capture location.
- During an active walk, use the camera-plus shortcut, capture and save a photo,
  then check that it is linked to the walk.
- On Android, scroll videos in both gallery and sharing composer; verify actual
  frames appear without sound and that corrupt videos retain a usable fallback.

Device acceptance checks are still required; automated tests mock camera/media
platform services and do not establish real-device thumbnail rendering.
