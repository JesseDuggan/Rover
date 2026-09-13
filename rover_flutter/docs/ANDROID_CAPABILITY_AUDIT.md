# Android Capability Audit

Audit date: 2026-09-13. Scope: current checkout, not the installed APK or Railway deployment.

## Findings

- The AI provider factory selects Android rather than a Samsung model. Native
  capability detection queries ML Kit and Android APIs. Manufacturer/model are
  diagnostic metadata, not eligibility gates.
- The Android app declares minSdk 26. Compile/target SDK come from Flutter.
  This is a build configuration, not proof that every device or OS is validated.
  No SDK minimum or dependency upgrades were made in this audit.
- The native bridge executes bundled Latin OCR. Prompt, Image Description, and
  local speech operations currently return unavailable even if the device
  capability probe reports support. Model readiness and implemented app features
  must not be treated as equivalent.
- Scout/Curator are deterministic Dart services. Existing navigation, geofences,
  Railway research and ElevenLabs are not replaced with local GenAI.
- Guardian evaluates each requested capability independently. OCR can be allowed
  when Nano is unavailable. Permission, thermal and memory checks still apply.
- Native capability discovery currently probes Prompt and Image Description
  before returning the full snapshot. A stalled probe can therefore delay OCR
  eligibility. The coordinator now bounds discovery and execution within one
  request budget; independent native probes remain a follow-up improvement.

## Changes

- Bound capability discovery, including diagnostics refresh.
- Apply the remaining request budget to inference, rather than starting a fresh
  timeout after discovery.
- Reject inference after cancellation during discovery.
- Bound native cancellation and tolerate cancellation errors so fallback results
  still reach the caller.
- Add regression coverage for slow discovery, late results after cancellation,
  and OCR eligibility without Nano across model labels.

These are fallback safeguards, not an automatic cloud image-upload path. Existing
consent rules remain unchanged. No hardware-specific branches were added.

## Device Checklist

Install the same rebuilt APK on each device and record the actual OS version,
app version/build and API endpoint. Do not assume Android 16 or 17 availability
from the model name.

| Device | Android version | App build | OCR | Nano readiness | Core walk | Result |
| --- | --- | --- | --- | --- | --- | --- |
| Fold5 | Pending | Pending | Pending | Pending | Pending | Not tested |
| Fold7 | Pending | Pending | Pending | Pending | Pending | Not tested this audit |
| S24 | Pending | Pending | Pending | Pending | Pending | Not tested |
| S22 | Pending | Pending | Pending | Pending | Pending | Not tested |

For each device:

1. Refresh Profile > On-device AI and capture the capability/status screen.
2. Create a walk; verify device location, map interaction and Google directions.
3. Hear a between-stop story, then an arrival announcement; check for repetition.
4. Scan a clear sign and a sign that cannot be resolved. Confirm candidate versus
   verified wording, a recoverable result, and continued map use.
5. Deny camera permission and confirm ordinary walks still work.
6. Background/foreground the app during optional analysis; check recovery.
7. Test folded/unfolded layouts on both Folds.
8. With an eligible downloaded pack, test offline playback and truthful freshness
   labels. Online-only researched stories must not be promised offline.

Also distribute a test build with local GenAI disabled to verify the baseline
experience independently of model availability. Non-Samsung physical testing and
Android 16/17 emulator testing remain required; mock model labels are not hardware
validation. Release signing still uses the debug signing configuration in this
checkout and must be addressed before public distribution.

## Next Work

Separate hardware readiness from app-operation readiness in diagnostics; isolate
native capability probes so optional GenAI cannot delay bundled OCR; then implement
one bounded Lens enhancement with cancellation and permission tests. Do not raise
the minimum Android version or require Nano merely to enable the core experience.
