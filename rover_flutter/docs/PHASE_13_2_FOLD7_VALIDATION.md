# ROVER Phase 13.2 Fold7 Validation

## Purpose

Validate the typed Android bridge and runtime capability detection on the Samsung Galaxy Z Fold7. This package does not enable inference and must not change Camera Explorer, route, geofence, narration, or voice behavior.

## Completed build gate

The following commands passed locally on 2026-08-31:

```powershell
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
```

Pigeon output is committed. Regenerate it only after changing the schema:

```powershell
dart run pigeon --input pigeons/rover_on_device_ai_api.dart
```

## Baseline device run

1. Install and run the debug APK with the normal `.env.local` configuration and no Phase 13 Dart defines.
2. Confirm Home, Explore, My ROAMs, Profile, Active ROAM, voice, and Camera Explorer behave as before.
3. Confirm the app does not request a new permission or start an AI model download.
4. Fold and unfold the device, background and resume the app, and confirm there is no crash.

## Capability capture

In a debug build, open **Profile > On-device AI**. The screen queries the
typed native bridge when it opens and when the refresh icon is pressed. This
diagnostic query does not enable Phase 13 features, start inference, or request
a model download.

The runtime bridge must report:

- Android API level, Samsung manufacturer, and device model.
- Prompt state: `available`, `downloadable`, `downloading`, or `unavailable`.
- Image Description state: `available`, `downloadable`, `downloading`, or `unavailable`.
- Bundled Latin OCR: `available`.
- Android on-device speech: `available` or `unavailable`.
- Foreground eligibility, battery saver, thermal state, and memory pressure.
- Object detection, local curation, and offline intelligence as unavailable in this package.

`downloadable` is a valid result. Phase 13.2 must not start the download automatically. `unavailable` is also valid when AICore, region, model configuration, system state, or bootloader policy does not permit the feature.

## State checks

| Condition | Expected behavior |
| --- | --- |
| Normal foreground | Typed snapshot, no exception |
| App backgrounded | Foreground eligibility false or operation denied |
| Battery saver on | Battery saver true; no automatic work |
| Device warm | Thermal state reflects Android status; optional work remains guarded |
| Airplane mode | Existing local state remains stable; no automatic model download |
| Folded and unfolded | Same typed contract; no crash or duplicate registration |

## Fold7 result - 2026-08-31

The debug capability panel returned a typed snapshot on Samsung `SM-F966W`
running Android API 36 through bridge version `1.0`:

| Signal | Observed result |
| --- | --- |
| Prompt | `downloadable`; Gemini Nano supported, model not downloaded |
| Image Description | `downloadable`; Gemini Nano supported, model not downloaded |
| Bundled Latin OCR | `available` |
| Object detection | `unavailable`; intentionally not configured in Phase 13.2 |
| Android on-device speech | `available` |
| Local curation | `unavailable`; reserved for a later Phase 13 package |
| Offline intelligence | `unavailable`; reserved for a later Phase 13 package |
| Foreground eligible | `yes` |
| Battery saver | `no` |
| Thermal state | `nominal` |
| Memory pressure | `no` |
| Quota limited | `no` |

The app also created a ROAM and completed Tell Me Nearby without a regression.
No model download or inference was started by the capability query.

## Evidence to retain

Record only the capability states, API level, device model, bridge version, and stable diagnostic codes. Do not retain images, OCR text, prompts, transcripts, coordinates, or native stack traces.

## Exit criteria

- Local debug APK builds.
- Existing Flutter suite passes.
- App starts and resumes on Fold7 without a bridge error.
- Capability states are typed and plausible.
- No model download or inference starts.
- Existing camera, route, geofence, narration, and voice behavior is unchanged.

The physical-device capability-query gate is passed. Fold/unfold,
background/resume, battery-saver, and airplane-mode checks remain useful
field-hardening observations but do not block the Phase 13.3 implementation
package.
