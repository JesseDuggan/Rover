# ROVER Phase 13.5 Scout and Curator Validation

## Build and run

```powershell
cd "C:\Users\jesse\Documents\Codex\2026-08-27\create-a-new-production-quality-asp\SRC\rover_flutter"
flutter analyze
flutter test
flutter build apk --debug --dart-define-from-file=.env.local
adb reverse tcp:5080 tcp:5080
flutter run -d RFGYA0RB5HY --dart-define-from-file=.env.local
```

Confirm `.env.local` contains:

```text
ROVER_PHASE13_ENABLED=true
ROVER_AI_CURATOR_LOCAL=true
```

## Field checks

1. Start a fresh ROAM and open `Profile > On-device AI`.
2. Confirm `Deterministic curation` is `yes` and `Autonomous speech` is
   `disabled`.
3. While stationary away from a stop, confirm Scout reports `stationary`,
   `onRoute`, and an appropriate attention state. Scout and Curator rows update
   live and do not require the refresh button.
4. Walk normally and confirm travel mode changes to `walking` without leaving
   the diagnostics screen.
5. Approach and enter a planned stop. Confirm geofence state progresses through
   `approaching` and `inside`, with attention `blocked` while arrival work is
   pending or playing. Once settled and arrival audio is finished, attention may
   become `open` while geofence state remains `inside`.
6. Leave the stop and confirm Scout can report `leaving` before returning to
   `approaching` or `outside`.
7. Open Camera Explorer near sourced POIs and allow the place refresh to finish.
   Return to On-device AI. Confirm Curator shows an eligible count
   or a clear suppression code and non-sensitive top-ranking reasons.
8. Go off route or enter a stop while a Curator candidate is available. Confirm
   the result is `navigation_urgent` and no optional story begins speaking.
9. Confirm neither ElevenLabs nor Android TTS begins solely because Curator
   selected a candidate.

Connectivity and offline cache may report `unknown` until Phase 13.6 adds the
offline repository and connectivity-backed cache state.

The refresh button rechecks native device capabilities. While the request is
running it shows a progress indicator, and `Screen refreshed` changes when it
finishes. The native `Checked` timestamp should also advance. Native model
curation is separate from the deterministic Flutter Curator shown below it.

If `Thermal` reports `serious` or `critical`, Camera Explorer may report that
the device is busy or warm and defer OCR or image-description work. Let the
device cool, press refresh, and confirm the thermal state improves before
retesting camera AI.
