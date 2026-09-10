# ROVER Phase 13.3 Lens OCR Validation

## Purpose

Validate intentional Camera Explorer still capture and bundled on-device Latin
OCR on the Samsung Fold7. This package does not enable Gemini Nano Image
Description, start a model download, upload an image, or treat recognized text
as verified evidence.

## Build and run

```powershell
cd "C:\Users\jesse\Documents\Codex\2026-08-27\create-a-new-production-quality-asp\SRC\rover_flutter"
flutter analyze
flutter test
flutter build apk --debug --dart-define-from-file=.env.local
adb reverse tcp:5080 tcp:5080
flutter run -d RFGYA0RB5HY --dart-define-from-file=.env.local
```

Do not enable `ROVER_AI_LENS_DESCRIPTION` for this package. The Fold7 reported
that model as downloadable, and Phase 13.3 does not silently start downloads.

## Camera Explorer checks

1. Open or create a ROAM, then open Camera Explorer.
2. Point the rear camera at a clear storefront sign or plaque and stop moving.
3. Press the focus icon in the Camera Explorer top bar.
4. Confirm the icon shows bounded progress and duplicate taps are disabled.
5. Confirm a result sheet appears when readable text is found.
6. Confirm unmatched text is labeled `Text candidate` and is not narrated as a fact.
7. When the complete recognized name matches a nearby sourced place, confirm
   that place is selected and the sheet says it matched nearby sourced context.
8. Try an image with no readable text and confirm the app asks you to move
   closer and hold steady.
9. Background the app during recognition, resume it, and confirm there is no
   stale result or crash.
10. Fold and unfold before another capture and confirm the result remains
    scrollable without overlap.

## Privacy and lifecycle expectations

- Exactly one still is captured after the explicit focus-button action.
- OCR executes with bundled ML Kit Text Recognition v2 on the device.
- No image bytes or OCR text are sent to the ROVER API.
- The temporary image is deleted after native processing and before the result
  sheet is presented.
- Cancellation, backgrounding, disposal, capture failure, and stale results all
  run the same best-effort cleanup path.
- Diagnostics retain only operation status, duration, stable code, and whether
  a nearby verified match was found. They do not retain OCR text or image paths.

## Expected diagnostics

| Outcome | Stable code |
| --- | --- |
| Text returned | `lens_ocr_completed` |
| No text returned | `lens_ocr_no_text` |
| Invalid or non-app cache image | `lens_ocr_invalid_image` |
| ML Kit processing failure | `lens_ocr_failed` |
| Feature flags off | `phase13_disabled` or `operation_disabled` |
| Cancelled | `native_operation_cancelled` |

## Exit criteria

- Analyzer, Flutter tests, and debug APK build pass.
- Camera Explorer still captures only after the explicit action.
- Fold7 returns local OCR text or a useful no-text state.
- Full nearby place names can select an existing sourced candidate.
- Partial text does not claim a place match.
- No automatic model download or image upload occurs.
- Existing map overlays, hotel rates, narration, route, and geofence behavior
  remain unchanged.

## Preliminary Fold7 result - 2026-08-31

- Flutter analysis, tests, and debug build were reported successful.
- The Fold7 Camera Explorer read restaurant signs and business names from
  online reference images presented to the camera.
- Recognized text was returned through the intentional-capture flow.
- No Gemini Nano model download was required for bundled OCR.
- Live storefront testing in Westport and Kingston remains scheduled for the
  next field session. That session should focus on distance, glare, oblique
  angles, low contrast, adjacent businesses, and verified nearby-place matches.

## Bad-weather storefront result - 2026-09-01

- Bundled OCR continued to return useful visible content in poor weather.
- The local perception result could not resolve the observed business to a
  known address or retrieve additional sourced place information.
- This is the expected limit of the Phase 13.3 local-only slice: it can select
  only an already loaded nearby overlay whose complete normalized name appears
  in the OCR output.
- The next package is candidate-to-evidence resolution using OCR text and
  permitted location/heading context. It must send no image, return ranked
  sourced candidates, preserve ambiguity, and enable stories or commerce only
  after a verified place is selected.
