# ROVER Phase 13.4 Place Resolution Validation

## Build and run

```powershell
cd "C:\Users\jesse\Documents\Codex\2026-08-27\create-a-new-production-quality-asp\SRC\rover_flutter"
flutter analyze
flutter test
flutter build apk --debug --dart-define-from-file=.env.local
adb reverse tcp:5080 tcp:5080
flutter run -d RFGYA0RB5HY --dart-define-from-file=.env.local
```

Restart `Rover.Api` before testing because exact OCR business-name search is
implemented in the middleware.

Confirm `.env.local` contains:

```text
ROVER_PHASE13_ENABLED=true
ROVER_AI_LENS_OCR=true
```

## Field checks

1. Open Camera Explorer and confirm the bottom `Scan sign` button and top focus
   shortcut are enabled. The screen does not scan automatically.
2. Frame a clear known business sign, tap `Scan sign`, and confirm a result
   sheet appears.
3. For a strong sourced match, confirm the canonical name, address, description,
   opening status, accessibility details, facts, confidence, reasons, and source
   attribution are displayed when supplied by the provider.
4. For multiple plausible nearby matches, confirm no place is selected until
   the user chooses one.
5. For an unknown or unreadable sign, confirm the app remains explicitly
   unverified and offers a useful retry message.
6. Background and resume the app, then confirm the camera returns and scanning
   can be triggered again without using a stale capture.
7. Stop the middleware and repeat a scan. Confirm local OCR still completes and
   the app reports that sourced place verification is unavailable.
8. Enter one planned-stop geofence and let the arrival narration finish. Remain
   inside for at least 60 seconds and confirm it does not restart. Walk outside
   the displayed threshold and back inside; the same completed stop must still
   not repeat during that ROAM.

Only recognized text and permitted location context may cross the API boundary.
The captured image must remain local and be deleted after OCR.
