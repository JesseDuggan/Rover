# Camera photo identification

## Preserved experience

Camera Explorer retains nearby business/site overlays, compass/GPS updates,
place selection, map links, adding places to a walk, and Hear story.
The existing local OCR flow remains available as **Read a sign**. Its photos
stay on device; only recognized text and location are sent for sourced matching.

**What am I looking at? > Identify an object** captures one photo. The user
reviews it and explicitly chooses **Send and identify**. Nothing is uploaded
before that choice. A returned candidate must be confirmed before it becomes
the selected camera place. Hear story then uses the existing sourced narration
path; model-generated identity guesses are never narrated as facts.

## Railway configuration

Deploy the updated API and set these server-side variables:

```text
ROVER_PHOTO_IDENTIFICATION_ENABLED=true
ROVER_VISION_MODEL=gpt-4.1-mini
```

Keep the existing `OPENAI_API_KEY` and `ROVER_BETA_API_KEY` in Railway only.
No additional keys or photo feature flags belong in the APK. Build and install
the updated Flutter release after deploying the API. This does not change the
story-generation model or any routing configuration.

The suggested initial vision model supports image input, Responses, and
structured outputs according to [OpenAI Docs](https://developers.openai.com/api/docs/models/gpt-4.1-mini).
Account access and recognition quality have not been live-tested. The model is
explicitly configured rather than silently inherited from the narration model.
Set `ROVER_PHOTO_IDENTIFICATION_ENABLED=false` to disable remote identification;
camera overlays and local sign scanning remain available.

## Bounds and privacy

- Endpoint: `POST /api/location-observations/identify-photo`, protected by the
  existing beta API authentication. Account/profile authorization is unchanged.
- Dedicated shared limit: 60 requests per hour per API process, no queue. This
  resets on restart and is not a distributed account-level spend limit.
- Flutter resizes to at most 1024 pixels on the longest side, re-encodes PNG
  pixels to remove metadata, caps the result at 2 MiB, and deletes the temporary
  camera file after preparation and again during cleanup.
- API bounds streamed request bodies to 2,850,000 bytes and validates PNG header,
  dimensions (maximum 1280 each side), base64 length and coordinates. Provider
  decoding rejects corrupt images beyond these basic checks.
- ROVER does not persist or log photos. OpenAI receives a data URL with
  `store:false` and coordinates rounded to two decimal places. This is not a
  zero-retention promise; provider policies still apply.
- The 25-second identification/matching budget does not retry paid vision calls.
  Failure, refusal, incomplete output, or uncertain identity produces no match.
- Public objects only, not people. Nearby sourced matching is limited to 1500 m.
  Unlisted statues may have no match even when visually recognizable. A readable
  plaque is often the best follow-up. There is no continuous camera upload.

## Verification and field test

Automated coverage includes PNG bounds, invalid coordinates, privacy payload,
forced confirmation, distant/unsourced candidate rejection, provider errors,
cancellation, disabled/authenticated endpoint behavior, consent-before-upload,
sheet dismissal, candidate rejection, quota errors and image downscaling.

No live paid recognition request or Android camera test was performed here.
In Munich, test one named statue with its plaque and one building. Confirm
nearby labels remain visible before/after closing the photo result. Reject an
incorrect candidate, cancel before upload, try poor connectivity, and background
the app during checking. Then confirm the correct place and tap Hear story.
Repeat with an unfamiliar statue in Frankfurt to measure identification quality.
