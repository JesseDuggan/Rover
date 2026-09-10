# ROVER Phase 13 Implementation Report

**Checkpoint:** Phase 13.0 repository integration inventory  
**Date:** 2026-08-31  
**Scope:** Android-first discovery and implementation plan only  
**Runtime changes in this checkpoint:** None

## Executive decision

Phase 13 is feasible in the current ROVER architecture if it is delivered one bounded work package at a time. The existing app and middleware already contain the important control points: camera ownership, location and heading, route and stop lifecycle, verified location evidence, narration arbitration, voice playback, preferences, diagnostics, and safe provider fallbacks.

The implementation must not create user-facing AI bots. ROVER remains the only assistant. Internal Scout, Lens, Listener, Guide, Curator, and Guardian responsibilities should be small services coordinated through typed requests and results.

The first implementation package will be 13.1 contracts, flags, no-op providers, Guardian, and a coordinator shell. It will add no AI dependency and will preserve current behavior with every Phase 13 flag off. Android AI libraries and the minimum-SDK change are deferred to the separately reviewable 13.2 package.

## Baseline verification

The following commands were run before any Phase 13 runtime code or dependency was introduced:

| Area | Command | Result |
| --- | --- | --- |
| Flutter static analysis | `flutter analyze` | Clean, no issues, 12.1 seconds |
| Flutter tests | `flutter test` | 73 passed |
| Middleware build | `dotnet build Rover.sln --no-restore` | Succeeded, 0 warnings, 0 errors |
| Middleware tests | `dotnet run --project Rover.Tests/Rover.Tests.csproj --no-restore` | 71 passed, 0 failed |

An APK build and physical-device AI capability validation were not part of this documentation-only checkpoint. They are mandatory gates for 13.2 and later packages.

## Existing integration inventory

### Flutter application

| Capability | Existing integration point | Phase 13 use |
| --- | --- | --- |
| Application state | `PreferencesController`, `AdventureRequestController`, `LocationController`, and `ActiveRoamController` exposed through `InheritedNotifier` scopes in `lib/src/app.dart` | Add one coordinator scope using the same pattern; do not add a second state framework |
| Camera ownership | `lib/src/camera_explorer/camera_explorer_screen.dart` owns a `CameraController`, rear-camera lifecycle, location subscription, heading smoothing, stale refresh protection, and verified POI overlays | Add an intentional still-capture path controlled by this screen; do not start continuous frame upload or a second camera controller |
| Camera recognition seam | `VisualRecognitionProvider` and `DisabledVisualRecognitionProvider` in `lib/src/camera_explorer/ar_capability.dart` | Evolve into a typed Lens provider while preserving the disabled fallback |
| Camera place candidates | `CameraPlaceCandidate`, `CameraOverlayCandidate`, and projection/ranking utilities in `camera_projection.dart` | Supply nearby verified candidate IDs and heading context to Lens and backend resolution |
| Location and heading | `RoverLocationProvider`, `GeolocatorLocationProvider`, `RoverLocationReading`, and `LocationController` | Scout input; keep navigation and geofence decisions deterministic |
| Route and stop lifecycle | `ActiveRoamController`, `RoamSession`, geofence scans, arrival state, route updates, and retry/deduplication state | Emit compact snapshots to the coordinator; do not replace arrival logic with AI |
| Journey narration client | `JourneyNarrationEvaluateRequest`, `JourneyNarrationDecision`, `WalkRepository.evaluateJourneyNarration`, and `RoverVoiceController` | Guide must reuse this arbitration and its fact IDs, priorities, cooldowns, and playback path |
| Location knowledge client | `LocationStoryContext`, `LocationPlaceSummary`, `LocationFactSummary`, `LocationSourceReference`, and `WalkRepository` location methods | Verified result and evidence boundary for candidate observations |
| Voice and audio | `RoverVoiceController`, `RoverAudioServices`, `RoverPremiumVoice`, plus Android speech/TTS handling | Listener returns typed commands; existing controller remains responsible for interruption, narration priority, and playback |
| Native bridge | `MethodChannel('ai.myrover.rover/voice')` in Dart and `MainActivity.kt` | Keep existing voice channel stable; add a separate typed AI boundary instead of expanding `MainActivity` |
| Preferences and privacy | `RoverPreferences`, `PreferencesRepository`, voice privacy acceptance, camera permission flow | Add explicit Phase 13 processing/upload policy settings; camera upload defaults to false |
| Diagnostics | `FieldDiagnostics`, `PerformanceDiagnostics`, beta diagnostics and problem-report queue | Add redacted operation/status/timing/provider/fallback fields only; never record images, OCR text, transcripts, prompts, or coordinates by default |
| Offline persistence | file/memory preferences, active ROAM persistence, speech cache, and `OfflineProblemReportQueue` | Reuse storage patterns, but add a purpose-built verified Story Pack cache rather than misusing the problem-report queue |
| Tests | unit/widget suites under `test/` and `integration_test/active_roam_flow_test.dart` | Add focused coordinator, policy, stale-result, camera flow, and bridge contract tests |

### Android application

The Android app currently has one native integration class, `android/app/src/main/kotlin/ai/myrover/rover/MainActivity.kt`. It handles text-to-speech, speech recognition, audio playback, permissions, and the existing voice `MethodChannel`. It is already substantial and should not become the implementation home for device AI.

Current build baseline:

- Flutter 3.47.1 and Dart 3.13.1.
- Android compile SDK 36 and target SDK 36 through Flutter defaults.
- Android minimum SDK 24 through Flutter defaults.
- Android Gradle Plugin 8.13.1, Kotlin plugin 2.4.0, Gradle 8.14.
- Java and Kotlin JVM target 17.
- Existing camera, geolocation, Mapbox, and wakelock plugins build in this configuration.
- No ML Kit GenAI, Pigeon, KSP, AndroidX WindowManager, or device-AI dependency is present.

### Middleware and evidence services

| Capability | Existing integration point | Phase 13 use |
| --- | --- | --- |
| Evidence model | `LocationSource`, `LocationFact`, `LocationPlace`, `LocationStoryContext`, and `LocationStoryResult` | Preserve source, confidence, attribution, and fact IDs in every verified result |
| Provider aggregation | `ILocationContextProvider` implementations for Mapbox, Wikipedia, Wikidata, OpenStreetMap, and weather | Resolve local visual/OCR labels against backend evidence rather than narrating them directly |
| Candidate merging | `DeterministicLocationPlaceResolver` | Reuse place deduplication after providers return evidence-backed places; add a smaller observation-to-place matcher ahead of it |
| Ranking | `DeterministicLocationStoryRankingService` | Reuse for verified nearby results and initial Curator behavior |
| Story synthesis | `ILocationStorySynthesizer`, `OpenAILocationStorySynthesizer`, and `SafeFallbackLocationStorySynthesizer` | Continue enforcing supported fact IDs and safe fallback text |
| Journey arbitration | `IJourneyNarrationOrchestrator` and `JourneyNarrationOrchestrator` | Guide reuses current narration kind, priority, cooldown, already-narrated IDs, and quiet result |
| Caching | `ILocationContextCache` and `InMemoryLocationContextCache`, plus generated speech caches | Reuse server-side location cache; add explicit client cache contracts for approved verified Story Packs |
| Dependency injection | `Rover.Application.DependencyInjection` and `Rover.Infrastructure.DependencyInjection` | Register candidate resolution and later provider implementations using current scoped/singleton conventions |
| API surface | `GET /api/location-context`, `POST /api/location-story`, and `POST /api/walks/{walkSessionId}/journey-narration/evaluate` | Keep these endpoints; add one minimal candidate-resolution endpoint instead of overloading story creation |
| Tests | executable middleware suite in `Rover.Tests/Program.cs` | Extend current location intelligence and narration tests with observation resolution and evidence-denial cases |

## Gaps found

1. **Story Packs are conceptual, not a formal repository model.** The current evidence-backed `LocationStoryContext` and `LocationStoryResult` are the closest implemented capability. Phase 13 should initially wrap these verified artifacts in a small cache record rather than inventing a parallel story engine.
2. **There is no general feature-flag framework.** Existing environment configuration uses `String.fromEnvironment` and server configuration objects. Phase 13 needs a focused immutable `RoverPhase13Flags` object with all flags false by default.
3. **There is no typed Android AI bridge.** The existing raw voice channel is not an appropriate place for image and model operations. Pigeon is preferred for the new versioned host API.
4. **The camera preview does not currently capture a still for recognition.** The existing explicit action calls the disabled provider with nearby candidate names only. Phase 13 will add a user-initiated `takePicture()` flow, local temporary-file ownership, cancellation, and deletion.
5. **Movement mode is not a formal service.** Scout may expose `unknown`, `stationary`, `walking`, or `driving` as a derived, confidence-bearing observation, but must not use it for safety-critical route decisions.
6. **Connectivity, battery saver, thermal state, quota, and model download state do not have shared abstractions.** Guardian needs narrow provider interfaces and must return `unknown` when the platform cannot supply a value.
7. **No foldable/window posture integration exists.** Folded and unfolded layouts are field-test requirements, but posture APIs are not required for the first camera-to-story demonstration.
8. **No offline Story Pack/POI evidence cache exists in Flutter.** Offline mode requires a bounded, expiring store with deletion and freshness metadata.

## Android API and dependency decision

### Confirmed constraints

- ML Kit Text Recognition v2 supports Android API 23+, so OCR does not force a change from the current API 24 floor.
- ML Kit GenAI Prompt API and Image Description API require Android API 26+ and runtime feature/model availability checks.
- Official ML Kit supported-device documentation lists Galaxy Z Fold7 for `nano-v2`, but support must still be queried at runtime. Region, OS, AICore state, downloaded model, foreground eligibility, quota, battery, and policy may change availability.
- ML Kit Speech Recognition Basic is an optional Android API 31+ path on supported devices. Advanced speech is not a Fold7 assumption and will not be required.
- Android AppFunctions is experimental and API 36 oriented. ROVER does not need it for internal services, so it is excluded from Phase 13.
- Samsung Neural SDK is not available to third-party developers according to Samsung's current official page. It is excluded from the initial implementation.

### Decision

Raise the Android app minimum SDK from 24 to 26 in Phase 13.2, immediately before adding ML Kit GenAI dependencies. This is a product compatibility decision and must be visible in that change. Phase 13.1 can remain on API 24 because it contains only Dart contracts, flags, policies, and no-op providers.

Dependency versions will be pinned from the official setup documentation during 13.2. Compatibility is conditionally approved at the platform level, but not considered complete until `flutter analyze`, all tests, `flutter build apk --debug`, and a Fold7 runtime capability query pass with the selected artifacts.

Official references:

- https://developers.google.com/ml-kit/genai
- https://developers.google.com/ml-kit/genai/image-description/android
- https://developers.google.com/ml-kit/genai/prompt/android
- https://developers.google.com/ml-kit/genai/speech-recognition/android
- https://developers.google.com/ml-kit/vision/text-recognition/v2/android
- https://developer.android.com/ai/gemini-nano
- https://developer.android.com/ai/appfunctions
- https://developer.samsung.com/neural/overview.html

## Target implementation shape

### Coordinator boundary

`RoverOnDeviceAiCoordinator` will accept a typed user intent or current-state snapshot, ask `RoverAiGuardian` for permitted routes, query `OnDeviceAiProvider` capabilities, execute at most a small fixed number of bounded operations, and return one structured result to the existing ROVER UI or voice path.

It will not become a general chat loop, own navigation state, play audio, or mutate a walk directly. Commands that can change a route or journey will map to existing typed controller actions and retain confirmation requirements.

### Candidate-to-evidence flow

1. Camera Explorer intentionally captures one still image after user action.
2. The image remains in app-controlled temporary storage.
3. Lens performs eligible OCR/image description locally and returns candidate observations.
4. Flutter adds the minimum needed time, location accuracy, heading accuracy, route, and nearby verified candidate IDs allowed by Guardian.
5. A new backend observation-resolution endpoint matches candidates against existing location providers and verified `LocationPlace` records.
6. Existing location story and journey narration services produce evidence-backed text with fact IDs and attribution.
7. Existing `RoverVoiceController` optionally renders/plays the result.
8. The temporary image is deleted after completion, cancellation, timeout, or error.

The default request sends no image to the backend. A future cloud-image fallback remains separately flagged, explicitly consented, and off by default.

### Result requirements

Every local operation result will carry correlation ID, status, provider, operation, device/backend processing location, candidate or verified state, confidence where meaningful, duration, fallback, policy decisions, and a privacy-safe diagnostic code. Stale frame, location, route revision, or journey results will be discarded before UI or narration.

## Feature flags

Create `RoverPhase13Flags` from Dart defines with these defaults:

| Flag | Default |
| --- | --- |
| `ROVER_PHASE13_ENABLED` | `false` |
| `ROVER_AI_ON_DEVICE_PROMPT` | `false` |
| `ROVER_AI_LENS_OCR` | `false` |
| `ROVER_AI_LENS_DESCRIPTION` | `false` |
| `ROVER_AI_LISTENER_LOCAL_SPEECH` | `false` |
| `ROVER_AI_CURATOR_LOCAL` | `false` |
| `ROVER_AI_OFFLINE` | `false` |
| `ROVER_AI_CLOUD_FALLBACK` | `false` |
| `ROVER_AI_CAMERA_UPLOAD` | `false` |

The master flag gates every operation. Capability flags are independently controllable. No flag may imply hardware availability or consent.

## Exact proposed file changes

Names below are proposed repository-native files. Generated Pigeon files will be committed only if that matches the selected Pigeon workflow.

### 13.1 contracts, flags, Guardian, and coordinator shell

Add:

- `lib/src/on_device_ai/rover_ai_models.dart`
- `lib/src/on_device_ai/rover_ai_provider.dart`
- `lib/src/on_device_ai/disabled_rover_ai_provider.dart`
- `lib/src/on_device_ai/rover_ai_guardian.dart`
- `lib/src/on_device_ai/rover_on_device_ai_coordinator.dart`
- `lib/src/on_device_ai/rover_phase13_flags.dart`
- `lib/src/on_device_ai/rover_on_device_ai_scope.dart`
- `test/on_device_ai_models_test.dart`
- `test/rover_ai_guardian_test.dart`
- `test/rover_on_device_ai_coordinator_test.dart`

Extend:

- `lib/src/app.dart` to construct and expose one coordinator using existing scope patterns.
- `lib/src/diagnostics/field_diagnostics.dart` to redact any new correlation/model diagnostic fields.
- `lib/src/preferences/rover_preferences.dart` only when explicit local-AI/upload controls are exposed to users.

### 13.2 Android typed bridge

Add:

- `pigeons/rover_on_device_ai_api.dart`
- `lib/src/on_device_ai/android_rover_ai_provider.dart`
- `android/app/src/main/kotlin/ai/myrover/rover/ai/RoverOnDeviceAiHostApi.kt`
- `android/app/src/main/kotlin/ai/myrover/rover/ai/DeviceCapabilityService.kt`
- `android/app/src/main/kotlin/ai/myrover/rover/ai/OnDevicePromptProvider.kt`
- `android/app/src/main/kotlin/ai/myrover/rover/ai/OnDeviceLensProvider.kt`
- `android/app/src/main/kotlin/ai/myrover/rover/ai/UnsupportedOnDeviceAiProvider.kt`
- Android unit/instrumentation tests under matching `src/test` and `src/androidTest` packages.

Extend:

- `pubspec.yaml` with Pigeon tooling if selected.
- `android/app/build.gradle.kts` to set `minSdk = 26` and add pinned Android AI dependencies.
- `android/app/src/main/kotlin/ai/myrover/rover/MainActivity.kt` only to register the generated host API and delegate to the new package.
- `android/app/src/main/AndroidManifest.xml` only for SDK-required declarations; add no network or storage permission merely for local AI.

### 13.3 Lens and backend candidate resolution

Add:

- `lib/src/on_device_ai/rover_lens_service.dart`
- `Rover.Application/LocationIntelligence/CandidateObservationModels.cs`
- `Rover.Application/LocationIntelligence/ICandidateObservationResolutionService.cs`
- `Rover.Application/LocationIntelligence/CandidateObservationResolutionService.cs`
- `Rover.Api/Contracts/CandidateObservationContracts.cs`
- `Rover.Api/Mapping/CandidateObservationResponseMapper.cs`

Extend:

- `lib/src/camera_explorer/camera_explorer_screen.dart` for explicit capture, progress states, cancellation, stale-result checks, and cleanup.
- `lib/src/camera_explorer/ar_capability.dart` by migrating the current seam to the typed Lens provider without breaking the disabled path.
- `lib/src/api/rover_api_client.dart` and `lib/src/api/walk_repository.dart` with `POST /api/location-observations/resolve`.
- `Rover.Api/Program.cs` with the minimal endpoint.
- Existing application/infrastructure DI files with the resolver registration.
- Flutter camera tests and middleware location-intelligence tests.

### 13.4 through 13.7

Later packages should add small services under `lib/src/on_device_ai/` for Listener command mapping, Scout snapshots, deterministic Curator ranking, and verified offline Story Pack storage. Existing `RoverVoiceController`, `ActiveRoamController`, `JourneyNarrationOrchestrator`, and location evidence services should receive narrow extensions only where an existing typed action or event is missing.

## Test plan

### Flutter

- Flag combinations and master-disable behavior.
- No-op provider results on unsupported platforms.
- Guardian permission, consent, foreground, timeout, and camera-upload denial policies.
- Coordinator cancellation, operation budget, timeout, deduplication, and stale-result rejection.
- Structured result serialization without private diagnostic payloads.
- Camera explicit-capture UI states, cancellation, temporary-file deletion, and app lifecycle cleanup.
- Existing route, geofence, narration priority, and stop lifecycle regression tests.
- Offline cache freshness, expiry, size limit, and deletion.

### Android

- Capability mapping for available, downloadable, downloading, unavailable, busy, quota-limited, background-blocked, and error states.
- Stable mapping from native exceptions to typed Dart status codes.
- Cancellation and timeout cleanup.
- OCR with no text, multiple regions, rotation, and low-confidence output.
- Image description result remains a candidate.
- No prompt/image/transcript/location logging.
- Unsupported emulator/provider fallback.

### Middleware

- Observation resolution by coordinates, heading, OCR text, and nearby verified IDs.
- Multiple plausible places and low-confidence/no-match results.
- No factual narration when evidence requirements are not met.
- Unsupported local labels cannot become fact IDs.
- Provenance and attribution survive candidate resolution and story creation.
- Current/expiring data cannot be presented as fresh after expiry.
- Request contracts reject image bytes and unnecessary personal context in the default flow.

### Fold7 field validation

- Capability snapshot folded and unfolded.
- Supported and missing/downloadable model states.
- Walking, driving, stationary, poor GPS, and changing heading.
- Signs and plaques in bright daylight and low light.
- Similar adjacent storefronts and ambiguous candidates.
- Airplane mode and cached-story behavior.
- Battery saver, thermal pressure, repeated requests, background/foreground, and cancellation.
- Navigation prompt interrupting optional camera narration.

## Risks and required fallbacks

| Risk | Required behavior |
| --- | --- |
| GenAI feature unavailable by region, model state, quota, or policy | Return typed unavailable state and continue current Camera Explorer location/heading behavior |
| API 26 minimum removes Android 7.0/7.1 support | Make the product decision explicit in 13.2 release notes and CI |
| Beta Android APIs or dependency incompatibility | Pin versions, isolate providers, retain no-op implementation, and prove APK build before merging |
| Slow model initialization or inference | Foreground check, strict timeout, cancellable work, visible local/checking states, no navigation blocking |
| Local candidate is wrong | Phrase as uncertain before verification; backend evidence match required for factual narration |
| Camera privacy or retention failure | Default no upload, app-controlled temporary file, deletion in every terminal path, no diagnostic content |
| Stale location/frame/route state | Correlation and revision tokens; silently discard stale results |
| Audio conflict | Existing deterministic voice controller and journey priority win; optional output may be suppressed |
| Missing formal Story Pack store | Wrap verified existing story/evidence records first; do not create a second fact system |
| Battery/thermal status unavailable | Guardian reports unknown and uses conservative operation limits |

## Phase 13.0 exit assessment

- Existing architecture and reusable components are documented.
- Repository gaps and platform constraints are explicit.
- No implementation duplication is proposed.
- Android API 26 is identified as the 13.2 compatibility gate.
- Phase 13 default behavior and camera upload are off.
- Flutter and middleware baselines are clean.
- No runtime code, dependency, permission, minimum-SDK, API, or user behavior changed in this checkpoint.

**Decision:** Phase 13.0 is complete. Phase 13.1 may begin with contracts, flags, Guardian, coordinator shell, no-op providers, diagnostics, and tests only.

## Phase 13.1 implementation status

**Completed:** 2026-08-31

Phase 13.1 is implemented as a dependency-free, disabled-by-default Flutter shell. No Android AI library, permission, camera capture behavior, API contract, minimum SDK, route logic, geofence logic, narration behavior, or voice behavior changed.

### Added

- `lib/src/on_device_ai/rover_ai_models.dart`
  - Typed operations, result statuses, processing locations, verification states, device capability states, privacy policy, request context, candidate observations, payloads, and result envelopes.
- `lib/src/on_device_ai/rover_phase13_flags.dart`
  - Master and independently controlled Dart-define flags. Every flag defaults to false.
- `lib/src/on_device_ai/rover_ai_provider.dart`
  - Provider boundary plus `DisabledRoverAiProvider` fallback.
- `lib/src/on_device_ai/rover_ai_guardian.dart`
  - Deterministic feature, permission, foreground, precise-location, camera-upload, cloud-fallback, quota, memory, thermal, and capability checks.
- `lib/src/on_device_ai/rover_on_device_ai_coordinator.dart`
  - One-operation request execution, preflight policy, runtime capability policy, timeout, provider cancellation, duplicate-correlation rejection, concurrency limit, typed failures, and privacy-safe diagnostics.
- `lib/src/on_device_ai/rover_on_device_ai_scope.dart`
  - Existing-app-pattern `InheritedWidget` access to the coordinator.
- `test/on_device_ai_models_test.dart`
- `test/rover_ai_guardian_test.dart`
- `test/rover_on_device_ai_coordinator_test.dart`

### Extended

- `lib/src/app.dart`
  - Constructs the coordinator with `RoverPhase13Flags.fromEnvironment()` and `DisabledRoverAiProvider` in production.
  - Exposes the coordinator through `RoverOnDeviceAiScope`.
  - Supports optional provider and flag injection in production and test app shells.
  - Cancels in-flight coordinator work during app disposal.

### Safety behavior proven

- The disabled master flag prevents capability queries and provider execution.
- Individually enabled operations remain disabled when the master flag is off.
- Local perception payloads remain explicitly `candidate`, with no evidence IDs implied.
- Camera and microphone work require their permissions.
- Precise location requires explicit policy permission.
- Camera upload requires both its feature flag and runtime policy consent.
- Cloud fallback requires both its feature flag and runtime policy consent.
- Background-ineligible, quota-limited, critical thermal, memory-pressure, and unavailable-capability states fail closed.
- Requests are time-bounded and provider cancellation is invoked after timeout.
- Explicit cancellation completes promptly.
- Duplicate correlation identifiers and excess concurrent operations return typed `busy` results.
- Diagnostics contain operation, provider, duration, fallback, and stable code only. They do not include prompt text, image paths/content, transcripts, coordinates, user intent, or correlation IDs.

### Phase 13.1 verification

| Area | Result |
| --- | --- |
| `dart format` | All Phase 13.1 and changed app files formatted |
| `flutter analyze` | No issues |
| Focused Phase 13.1 tests | 16 passed |
| Full Flutter suite | 89 passed |
| Middleware build | Succeeded, 0 warnings, 0 errors |
| Middleware suite | 71 passed, 0 failed |
| Debug APK packaging in Codex sandbox | Not revalidated: Microsoft JDK 21 and Gradle 8.14 were confirmed, but the sandbox Gradle daemon exited during its cache/daemon shutdown handshake and produced no new APK. Run the normal local build command before device deployment. |

**Decision:** Phase 13.1 is complete. Phase 13.2 may begin as a separate Android change with the API 26 decision, typed native bridge generation, capability detection, no-op/unsupported mapping, and pinned Android dependencies.

## Phase 13.2 implementation status

**Completed:** 2026-08-31

Phase 13.2 adds the typed Android boundary and runtime capability detector. It does not execute prompts, OCR, image description, local speech, curation, or offline intelligence. Every Phase 13 feature flag remains false by default, no model download is started, and Camera Explorer, route, geofence, narration, and voice behavior remain unchanged.

### Platform decision and pinned tooling

- Android `minSdk` is now 26, as required by ML Kit Prompt and Image Description.
- Pigeon is pinned to `28.0.0` and generates both Dart and Kotlin from `pigeons/rover_on_device_ai_api.dart`.
- ML Kit Prompt is pinned to `com.google.mlkit:genai-prompt:1.0.0-beta2`.
- ML Kit Image Description is pinned to `com.google.mlkit:genai-image-description:1.0.0-beta1`.
- Bundled Latin OCR is pinned to `com.google.mlkit:text-recognition:16.0.1`.
- Structured Output and KSP are intentionally excluded.

### Added boundary

- `pigeons/rover_on_device_ai_api.dart`
  - Versioned host API for bridge version, capability query, bounded operation request, and cancellation.
  - Typed availability, thermal, operation, request, result, and diagnostic models.
- `lib/src/on_device_ai/generated/rover_on_device_ai_api.g.dart`
- `android/app/src/main/kotlin/ai/myrover/rover/ai/generated/RoverOnDeviceAiApi.g.kt`
- `lib/src/on_device_ai/android_rover_ai_provider.dart`
  - Maps generated native types into the Phase 13.1 contracts.
  - Keeps native exceptions out of diagnostics and maps them to `native_bridge_error`.
  - Keeps local labels as candidate observations and never implies verification.
- `lib/src/on_device_ai/rover_ai_provider_factory*.dart`
  - Selects the Android provider only on Android and retains the disabled provider elsewhere.
- `android/app/src/main/kotlin/ai/myrover/rover/ai/DeviceCapabilityService.kt`
  - Queries Prompt and Image Description feature state without starting downloads.
  - Reports bundled OCR, Android on-device speech availability, foreground eligibility, battery saver, thermal state, and memory pressure.
  - Converts initialization and status-query failures to stable unavailable capability records.
- `android/app/src/main/kotlin/ai/myrover/rover/ai/RoverOnDeviceAiHostApi.kt`
  - Returns explicit Phase 13.2 unsupported operation results.
  - Supports bounded cancellation markers and foreground denial.

`MainActivity.kt` only registers and unregisters the generated AI host API and supplies foreground state. Its existing voice channel and implementation are unchanged.

### Safety behavior

- Capability checks never auto-download a model.
- Capability failures do not cross the bridge as native stack traces.
- Unsupported operations return `native_operation_not_enabled_phase13_2`.
- Background-ineligible calls return `native_background_ineligible`.
- Cancelled calls return `native_operation_cancelled`.
- Generated result payloads carry no prompt text, image bytes, transcripts, coordinates, or native exception text.
- Android provider selection does not bypass the Phase 13 master flag or individual flags.

### Phase 13.2 verification

| Area | Result |
| --- | --- |
| Pigeon generation | Completed with Pigeon 28.0.0 for Dart and Kotlin |
| `flutter pub get` | Passed locally |
| `flutter analyze` | No issues |
| Focused Phase 13 tests | 21 passed, including 5 Android provider mapping tests |
| Full Flutter suite | Passed locally |
| Android unit test source | Added for all known and unknown ML Kit feature statuses |
| `flutter build apk --debug` | Passed locally; debug APK produced |
| Fold7 capability query | Passed on Samsung SM-F966W, Android API 36, bridge 1.0. Prompt and Image Description reported `downloadable`; OCR and on-device speech reported `available`; device state was foreground eligible, battery saver off, thermal nominal, with no memory pressure or quota limit. |

**Decision:** Phase 13.2 is complete and its physical-device capability gate
has passed. Phase 13.3 may connect a deliberately captured Camera Explorer
still to local OCR and image description behind independent flags, while
preserving candidate-only results and the existing backend evidence boundary.

## Phase 13.3 Lens OCR implementation status

**Implemented:** 2026-08-31  
**Physical-device build gate:** Passed  
**Live storefront field gate:** Pending

Phase 13.3 begins with bundled Latin OCR because the Fold7 capability snapshot
reported it as immediately available. Gemini Nano Prompt and Image Description
remain `downloadable`; this package does not enable them or start a model
download.

### Added

- `android/app/src/main/kotlin/ai/myrover/rover/ai/OnDeviceLensProvider.kt`
  - Validates an app-cache image path and 20 MB size limit.
  - Runs bundled ML Kit Text Recognition v2 locally.
  - Bounds returned text to 2,000 characters.
  - Returns typed success, no-text, invalid-image, failure, and cancellation
    diagnostics without logging recognized content.
- `lib/src/on_device_ai/rover_lens_service.dart`
  - Creates bounded OCR requests through the existing Guardian/coordinator.
  - Keeps camera upload and cloud fallback disabled.
  - Conservatively matches only a complete normalized nearby place name.
- `test/rover_lens_service_test.dart`
- `android/app/src/test/kotlin/ai/myrover/rover/ai/OcrTextNormalizerTest.kt`
- `docs/PHASE_13_3_LENS_VALIDATION.md`

### Extended

- Native bridge version is now `1.1`.
- `RoverOnDeviceAiHostApiImpl` executes only `lensOcr`; all other native
  operations remain unavailable.
- `AndroidRoverAiProvider` marks returned OCR text as an unverified candidate.
- Camera Explorer exposes an always-available focus action, captures one still,
  suppresses duplicate actions, cancels stale/background work, deletes the
  temporary image before presenting results, and displays long OCR output in a
  bounded scrollable sheet.
- A complete OCR name match selects only an already sourced nearby overlay.
  Unmatched text remains explicitly unverified and is not narrated as fact.

### Verification to date

| Area | Result |
| --- | --- |
| Dart formatting | Clean |
| Dart analysis of `lib` and `test` | No issues |
| Flutter tests | Reported passed locally |
| Kotlin/JVM tests | Reported passed as part of the local test/build gate |
| Debug APK | Built and deployed successfully |
| Fold7 OCR reference-image test | Passed for restaurant signs and business names shown from online images |
| Bad-weather storefront OCR | Passed local perception; address and sourced-place resolution unavailable as expected in the local-only slice |
| Candidate-to-evidence resolution | Next implementation package |

## Phase 13.4 - Camera Place Resolution

**Implemented:** 2026-09-01  
**Automated validation:** Passed  
**Live storefront field gate:** Pending

Phase 13.4 connects intentional on-device OCR to sourced nearby location
evidence. The temporary camera image stays on the device and is deleted before
the middleware receives recognized text, location accuracy, heading, route
context, and nearby place identifiers.

The middleware returns one of three explicit states:

- `verified`: one sourced place is strong enough to select automatically.
- `ambiguous`: several plausible places are shown for user selection.
- `unresolved`: OCR text is preserved without claiming a place match.

Camera Explorer now provides a prominent manual `Scan sign` control in addition
to the top focus shortcut. Scanning is intentionally not automatic. Phase 13
and Lens OCR are enabled in `.env.local`; both `flutter run` and APK builds must
use `--dart-define-from-file=.env.local` because these are compile-time flags.

OCR text is now also submitted to a bounded, exact-name Mapbox POI search in
parallel with the existing nearby category context. Results still pass through
the same deterministic `verified`, `ambiguous`, or `unresolved` evidence gate.
The result UI preserves and displays sourced address, description, opening
status, accessibility information, facts, confidence, match reasons, and source
attribution when those fields are available.

Arrival narration was hardened during the same field-validation cycle. A stop
is claimed atomically before asynchronous speech work starts, so overlapping
location updates cannot restart the same narration. Device geofence detection
now tracks actual outside-to-inside transitions instead of allowing a timed
retry while the device remains inside the radius.

Verification completed with clean Dart analysis, all 105 Flutter tests passing,
a zero-warning middleware build, and all 75 middleware tests passing. The debug
APK must be rebuilt in the normal developer terminal because the Codex sandbox
cannot complete this workspace's Gradle daemon handoff.

## Phase 13.5 - Scout and Curator

**Implemented:** 2026-09-01  
**Automated validation:** Passed  
**Autonomous narration:** Disabled by design  
**Fold7 field gate:** Pending

Scout now derives a compact situation snapshot from existing deterministic
ROVER state. It classifies stationary, walking, driving, or unknown movement;
on-route, off-route, or inactive journey state; outside, approaching, inside,
or leaving geofence state; and an open, brief, or blocked attention opportunity.
The snapshot also carries counts/identifiers for nearby verified POIs plus
explicit connectivity and offline-cache states. Standard diagnostics record
only the enums and counts, deduplicate unchanged snapshots, and do not record
coordinates.

Curator ranks only candidates that contain verified evidence IDs. Initial
ranking is deterministic and considers configured interests and exclusions,
remaining time, travel mode, route and nearby-place relevance, previously
narrated story/fact IDs, freshness/expiry, accessibility metadata, preferred
narration length, confidence, and existing story-worthiness score. Unverified,
repeated, excluded, stale, mode-incompatible, and over-budget candidates are
removed before ranking. Equal scores use a stable story-ID tie-break.

Off-route, approach, geofence-entry, and leaving states suppress optional story
selection. Camera Explorer feeds the Curator only sourced places containing
narration-suitable fact IDs. The coordinator exposes the latest Scout and
Curator result on the existing debug On-device AI screen. It does not send a
selection to ElevenLabs, Android TTS, or any other playback path in this package.

`ROVER_AI_CURATOR_LOCAL=true` is enabled in `.env.local` for field validation.
Verification completed with clean Dart analysis and all 111 Flutter tests
passing.

## Continuation checkpoint

The current cross-package status, completed field evidence, deferred defects,
and exact resume order are maintained in
`docs/PHASE_13_CONTINUATION_CHECKPOINT.md`. That checkpoint should be updated
before any future Phase 13 package changes status.
