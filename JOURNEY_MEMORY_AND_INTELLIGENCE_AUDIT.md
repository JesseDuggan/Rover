# ROVER Journey Memory and Intelligence Audit

Date: 2026-09-23. Source baseline: `928808bd07391657e5a3ecb0be08a0408988e08a`, plus the five pre-existing staged Flutter narration/controller/test changes. This is a source audit, not verification of the deployed API, Railway storage, installed APK, credentials, or live provider behavior. No production source was changed for this audit.

This report uses a descriptive name because Phase 15 already appears in existing location-intelligence code and tests. The delivery milestones below are independent of those existing phase labels.

## 1. Executive Conclusion

Proceed, but extend the existing walk lifecycle and narration services rather than build a second journey engine. ROVER has meaningful context, evidence, narration, and preference components. It does not yet have a production-ready, owner-protected, durable journey archive or private diary platform.

The immediate blockers are:

1. Production identity and ownership enforcement are incomplete. A shared beta key is not a user identity.
2. Runtime walk sessions and accounts are in memory. The PostgreSQL profile repository throws rather than implementing persistence. SQL definitions alone do not provide durability.
3. Story availability and playback history cannot yet support an accurate diary: an adaptive pack's `HeardStoryIds` includes completed, skipped, and dismissed stories.
4. Narration reliability still needs field verification, and route duration can exceed the requested budget. Expanding into social features will not repair these problems.

Recommended first delivery: repair and verify narration separately, then implement one owner-protected, durable completed-journey vertical slice. Add editable private diaries next. Defer public sharing and community until access control, deletion, sanitization, and moderation are implemented.

## 2. Capability Inventory

Status definitions: **Implemented** means a concrete source implementation exists, not that production is verified. **Partial** means important behavior is present but incomplete. **Foundation** means contracts, schemas, or placeholders exist. **Missing** means not found in the audited paths. **Uncertain** means deployment or field evidence is needed.

Paths below are relative to this repository. API source prefixes are `rover_middleware/`; Flutter source prefixes are `rover_flutter/`.

| Capability | Status | Evidence and limits |
|---|---|---|
| Active journey lifecycle | Implemented | `Rover.Domain/Walks/WalkSession.cs`: start, ordered stop arrival, completion, cancellation, latest location, revisions, arrival candidate. It has no account owner and is not a historical event stream. |
| Route creation and duration | Partial | `Rover.Infrastructure/Walks/MockWalkPlanner.cs` uses injected providers despite its name. It performs a bounded over-budget reroute for story-led selection, but can still return an over-budget route. The non-story duration path can cap the reported estimate. |
| Route diagnostics | Implemented | `Rover.Application/Walks/RouteQualityDiagnostics.cs` computes utilization and warnings; warnings are not enforced planning constraints. |
| Lifecycle consistency | Implemented | `Rover.Application/Walks/StopLifecycleConsistency.cs` inspects ordering, IDs, next stop, geometry, and revisions and repairs recoverable state. Reuse this authority. |
| Route and stop restoration | Partial | `lib/src/active_roam/route_persistence.dart` serializes route geometry, stops, narration, source metadata, and maneuvers. `active_roam_repository.dart` stores a single session in a system-temp file, with memory fallback on web. This is not durable multi-walk history. |
| Saved walks and history | Foundation | `lib/src/ui/placeholder_screens.dart`, `SavedRoamsScreen` and `WalkHistoryScreen`: history reads the current session and planned-distance summary, not a durable collection of past journeys. |
| Saved discoveries | Partial | `Rover.Domain/Profiles/ProfileModels.cs`, `Rover.Application/Profiles/ProfileService.cs`, and profile saved-discovery endpoints exist. Runtime profile storage limits apply. A saved discovery is not a journey template. |
| Geofence and movement context | Partial | `WalkSession.RecordLocation`, arrival-candidate/arrival methods, and Flutter `active_roam_session.dart` maintain operational state. A complete append-only arrival/departure/off-route timeline is absent. Latest location is not travelled route geometry. |
| Journey narration decisions | Implemented | `Rover.Application/Journeys/JourneyNarrationOrchestrator.cs`: evaluates grounded context, reserves upcoming stops for arrival, and returns ranked decisions. `Rover.Api/Contracts/JourneyNarrationContracts.cs` defines request/response contracts. Decisions are not durably journaled. |
| Adaptive stories | Implemented | `Rover.Application/Journeys/AdaptiveRouteStoryEngine.cs`, `NarrativeScheduler.cs`, `RouteStoryPlanning.cs`, `JourneyCollection.cs`, and `JourneyNarrativeArc.cs` supply reusable story selection and route organization. Coverage and field timing remain uncertain. |
| Playback outcomes | Partial | `AdaptiveRouteStoryEngine.RecordPlaybackAsync` supports several playback kinds, but completed, skipped, and dismissed all enter `HeardStoryIds`; pack state retains only limited event state. Do not equate this set with listened-to stories. |
| Audio delivery | Implemented / uncertain in deployment | `Rover.Application/Speech/RoverSpeechService.cs`, `Rover.Infrastructure/Speech/ElevenLabsTextToSpeechProvider.cs`, `lib/src/voice/rover_voice_controller.dart`. Earlier screenshots showed speech HTTP 401; passing mocked tests does not establish live authorization or audio success. |
| Local research and current information | Partial | `Rover.Infrastructure/Journeys/OpenAILocalRouteResearcher.cs` searches cited evidence then classifies and validates cards. `LiveContext/OpenAICurrentInformationProvider.cs` and `LocationIntelligence/OpenAILocationStorySynthesizer.cs` provide existing adapters. Sparse/rejected evidence, freshness, and stage timeouts affect availability. |
| Other OpenAI integrations | Implemented | `Rover.Infrastructure/Conversation/OpenAIRoverConversationProvider.cs` and `Walks/OpenAIStoryLedStopSelector.cs`. Reuse provider boundaries, not conversational text as authoritative journey history. No model migration is required for this milestone. |
| Camera Explorer and AR | Partial | `lib/src/camera_explorer/camera_explorer_screen.dart` captures for on-device analysis and deletes temporary images; camera projection/heading and AR capability helpers support the experience. This is not a diary media-authoring pipeline. |
| Photos, videos, attachments | Missing for diary | No journey-media upload, gallery, private-object ownership, or video-diary workflow was found. `Rover.Infrastructure/Speech/S3GeneratedAudioCache.cs` throws; it is not an implemented general-purpose object store. |
| Preferences and learning | Implemented / partial persistence | `Rover.Domain/Profiles/ProfileModels.cs`: saved discoveries, preferences, weighted signals, deduplicated story interactions, consent checks and pruning. `SaveWalkHistory`, `ImproveRecommendations`, and location retention already exist; preserve their separate meanings. |
| Adaptation outcomes | Partial | `Rover.Application/Adaptations/WalkAdaptationService.cs` and accept/reject endpoints exist; `InMemoryWalkAdaptationRepository` is not a durable outcome ledger. |
| Accounts and identity | Foundation | `Rover.Application/Accounts/AccountService.cs` supports account linking/export/deletion abstractions. `Program.ResolveUserAsync` currently resolves development-header users only and otherwise returns null. Flutter `lib/src/auth/rover_auth.dart` contains interfaces and an in-memory token store, not a completed secure login integration. |
| Authorization | Partial / release blocker | `Rover.Api/Program.cs`: beta request guard is separate from user identity; profile access helper permits unresolved users. Walk endpoints do not establish owner-scoped access. Speech requires a resolved user. Existing behavior needs deliberate compatibility handling. |
| Database storage | Foundation | `database/init/001_phase7_initial.sql`, `002_phase8_accounts.sql`, and `Rover.Domain/Persistence/Phase7PersistenceModels.cs` define substantial structures. `PostgreSqlProfileRepository` throws for CRUD. DI still registers in-memory walks, accounts, adaptations, feedback, and diagnostics. |
| Story/evidence/audio caches | Implemented | `FileAdaptiveRouteStoryPackRepository`, `FileLocationIntelligenceRepository`, and `FileGeneratedAudioCache` exist. Expiry and permitted-content rules make caches unsuitable as permanent diaries. Hosting-volume durability is unverified. |
| Offline and retry | Partial | Flutter `adaptive_route_story_device_cache.dart` queues playback events and expires pack state; `offline_problem_report_queue.dart` supports reports. `TransientRetryHandler` and Google quota cooldown exist. These are not a general idempotent journey synchronization protocol. |
| Sharing, social, public deep links | Missing | No `PublishedAdventure`, follow/comment/moderation domain, or secure public-adventure resolution was found. `lib/src/routing/rover_router.dart` is internal navigation, not publication authorization. |
| Diagnostics and privacy | Partial | Flutter `diagnostics/field_diagnostics.dart` and API `RedactionService` redact selected data. `NoOpCrashReportingService` is registered. Diagnostic logs are not authoritative diary events; redaction is not a complete deletion/export policy. |

Primary composition evidence: [DependencyInjection.cs](rover_middleware/Rover.Infrastructure/DependencyInjection.cs) and [Program.cs](rover_middleware/Rover.Api/Program.cs).

## 3. Reusable Components

- Keep `WalkSession` as the journey-occurrence lifecycle authority. Extend its persistence and ownership instead of adding a competing `JourneySession` state machine.
- Reuse route revisions, stop snapshots, lifecycle checks, and route-quality diagnostics. Distinguish planned geometry from actually recorded movement.
- Retain `JourneyNarrationOrchestrator`, adaptive story selection, navigation priorities, and the existing Flutter audio controller. Do not introduce a second playback queue.
- Reuse evidence provenance, citation validation, freshness, and content-storage eligibility. A diary may retain a permitted reference when the source content itself cannot be archived.
- Reuse user preferences and explicit story interactions. Operational history and personalization must remain independently consented.
- Extend existing account export/deletion orchestration; do not add unrelated diary-only account handling.

## 4. Missing Capabilities and Duplication Risks

The major missing pieces are durable ownership, event journaling, multi-journey history, private diary editing, media storage, general synchronization, publication snapshots, and moderation.

Avoid these conflations:

- A route template is a reusable plan; a session is what actually happened.
- A restored active session is not a completed-history archive.
- A story offered, skipped, or dismissed is not a completed listening experience.
- A diagnostic message is not a trusted event, and a client claim is not automatically a verified arrival.
- A private diary is user-editable; the underlying factual timeline should not be silently rewritten by an AI recap.
- A published adventure is a separate sanitized snapshot, never a public flag on a private session.
- A cache expiry policy does not establish permission for indefinite provider-content retention.

## 5. Proposed Domain and Architecture

All additions below are proposals, not existing capabilities.

| Concept | Recommendation |
|---|---|
| ContextObservation | Normalize selected existing GPS-quality, route, arrival, playback, explicit-feedback, and camera-resolution signals. Include observation ID, owner/session scope, source, occurred/received times, accuracy/confidence, payload schema version, and retention class. Do not persist every GPS tick by default. |
| JourneyContextSnapshot | A derived, replaceable view of current session/revision, next stop, arrival state, audio state, consent, and usable evidence. Rebuild from authoritative state; do not create another lifecycle authority. |
| JourneyDecision | Record only useful decision summaries: decision ID, session/revision, action, reason code, evidence references, rules/model version, and expiration. Avoid storing full prompts and private context indiscriminately. |
| JourneyOutcome | Link accepted/rejected adaptations and explicit playback/feedback outcomes to decisions. Preserve interrupted, skipped, failed, started, and completed as distinct values. |
| JourneySession | Extend persisted `WalkSession` with owner, version, retention policy, and timestamps. Keep public API compatibility where safe, but never preserve anonymous access to newly private records. |
| JourneyEvent | Append-only operational journal with stable client event ID, server ID, session/revision, event kind, versioned payload, occurred/received times, and origin. Use corrections rather than overwriting trusted historical events. |
| SavedAdventure / template | A reusable versioned route plan, independent of a past session. Following it creates a new owned session and revalidates routing, freshness, and availability. |
| TripDiary | Private-by-default owner/session-linked editable document with version, draft status, generated-at time, and optional generation provenance. It is not the event store. |
| DiaryEntry | Ordered text/note/story-reference/media-reference entries. Record whether user-authored or generated and retain source-event references for generated factual claims. |
| JourneyMedia | Private object reference, owner, capture consent, processing status, media type/size, sanitized metadata, caption, and retention/deletion state. Never expose storage paths as public authorization. |
| PublishedAdventure | Separate immutable or explicitly versioned sanitized snapshot with visibility, owner, publication status, selected content, approximate geometry, and revocable sharing identifiers. |
| UserProfile | Separate private account/preferences from an optional discoverable profile. New profile visibility is private. Installation IDs are not authentication secrets. |
| Future social records | Follows, reactions, comments, reports, blocks, and saved public adventures reference published/profile IDs, not private diary/session IDs. Engagement is not automatically consented personalization data. |

Flow: existing operational services -> normalized events/outcomes -> durable owned journey -> private diary projection -> user-reviewed publication snapshot. Context ranking reads a derived view; it does not own every subsystem.

## 6. API and Flutter Impact

Proposed API surface, subject to established contract conventions:

- Owner-scoped journey list/detail, completion history, export, and deletion.
- Idempotent batch journey-event ingestion with per-event acknowledgements; server-derived lifecycle events remain authoritative.
- Private diary read/update with optimistic concurrency; recap creation returns a job/status resource rather than holding a long synchronous request open.
- Later: authorized media upload/finalization/deletion and publication preview/publish/unpublish. Public reads resolve sanitized published records only.

Candidate route shapes include `GET /api/me/journeys`, `GET /api/me/journeys/{id}`, and `POST /api/me/journeys/{id}/events`. These are not implemented endpoints. Never accept a request-body owner ID as authorization.

Flutter changes should replace the placeholder history view with a real history list/detail while retaining active-walk screens. Use application-support storage rather than temporary directories for an opted-in durable local journal. Add a bounded offline outbox, visible sync failures, and version-aware updates. Add diary editing only after this workflow is reliable.

Do not reuse Camera Explorer's transient captures as diary photos without a deliberate capture/save action. Do not block navigation or audio while diary synchronization runs.

## 7. Persistence and Migration Plan

1. Inspect deployed database state and applied migration history before writing migrations. Existing init SQL must not be assumed applied, current, or safe to rerun.
2. Implement and integration-test real repositories and transaction boundaries. Changing a storage setting to PostgreSQL does not repair the throwing repository.
3. Establish owners and guest-to-account claiming rules. Legacy unowned data needs explicit quarantine/claim/expiry decisions; never assign it based on a guessed profile ID.
4. Reuse existing session, stop/content snapshot, route revision, feedback, and narration-progress structures where appropriate. Add event/diary tables through ordered migrations, not a second parallel schema.
5. Add event uniqueness scoped to owner/session/client event ID; reject conflicting reuse, acknowledge identical retries. Persist state changes and corresponding events atomically or use a transactional outbox.
6. Use optimistic concurrency for session/diary changes. Order server lifecycle events by server sequence; retain client time separately for delayed playback reports. Validate route revision and payload version.
7. Preserve event IDs until acknowledged. Test response loss after commit, app termination, duplicate batches, and replay after sign-in changes. Cache queues alone are insufficient.
8. Define deletion across database rows, blobs, cache derivatives, search projections, and queued jobs. Existing nullable profile foreign keys with `ON DELETE SET NULL` must not leave private routes retained unintentionally.
9. Define hosting volumes, database backups, restoration tests, migration rollout/rollback, retention, and observability before claiming durability.

Store minimal history by default: planned route, confirmed visited stops, explicit playback outcomes, and user notes. Actual precise travel traces require separate opt-in, bounded retention, and clear display labels.

## 8. Privacy and Publication Boundaries

- Diaries and profiles start private. History saving and recommendation learning are separate controls, honoring existing preferences.
- Every private read/write/export/delete requires verified ownership. Test cross-account IDs, guest claiming, media URLs, background jobs, and account switching.
- AI recaps receive only permitted journey facts and user-selected notes. Never infer that a person visited, listened, enjoyed, or photographed something solely because it was planned or offered.
- Public content must be an explicit reviewed selection. Remove precise home/accommodation endpoints, sensitive locations, private notes, live positions, and identifying metadata by default. Approximation must consider identifying routes, not just round coordinates.
- Private, Followers, Unlisted, and Public need distinct authorization. Unlisted links are bearer-accessible, not private. Followers visibility requires viewer identity and block checks. Do not expose unsupported visibility choices before enforcement exists.
- Publication/unpublication uses revocable references and cache invalidation. Warn that external downloads and social-platform copies cannot be reliably recalled.
- Media needs private storage, short-lived authorized delivery, type/size limits, metadata stripping, processing checks, and deletion handling. Children and unreviewed media must not be automatically published.
- Reporting, blocking, moderation operations, abuse limits, and child-safety policy are launch prerequisites for public community features, not follow-up enhancements.
- Extend export/deletion beyond current account/profile/preference data to events, diaries, media, publications, and derived data. Document backup retention and deletion limits.
- Review provider content-storage and attribution permissions before permanent archival or redistribution. This audit does not establish legal compliance or content licenses.

## 9. Reliability Workstream: Keep Separate

Before expanding the product surface:

1. Trace speech authorization end to end. `ResolveUserAsync` and `/api/speech/render` behavior must align with actual mobile credentials; do not solve 401s by broadly disabling authorization.
2. Field-verify the staged arrival-gate fixes with recorded transitions: arrival narration completed -> gate released -> eligible story starts. Preserve navigation priority and prevent partial-story restart loops.
3. Distinguish research timeout, no evidence, geographic rejection, expiry, and playback scheduling in diagnostics. The current backend has separate research/classification time budgets; production results still need verification.
4. Improve current-event retrieval with explicit locality, dates, event windows, source provenance, and expiry tests. If no verified local event exists, report that rather than inventing one or silently presenting old history as current news.
5. Test story coverage and late generation. A failed refresh should not unnecessarily discard still-valid content; geographically flexible stories can be reconsidered after their initial window only when their meaning remains valid. Do not simply disable arrival/turn gates.
6. Enforce a truthful route time budget: bounded replanning, fewer stops, or an explicit user-approved longer route. A 198-minute result must not appear to satisfy a 90-minute request.

Use separate commits and acceptance evidence for reliability versus memory expansion. A different language model is not a substitute for these changes.

## 10. Delivery Milestones and Acceptance

| Milestone | Scope | Required acceptance |
|---|---|---|
| M0: Reliability and identity prerequisites | Narration checks above; production identity decision; owner access policy and durable storage design. | Reproduce and verify arrival-to-story transitions; no duplicate restarts; speech auth succeeds for authorized users and rejects others; route budgets are truthful. |
| M1: Durable owned journey foundation | Persist existing sessions and minimal timeline; completed-history list/detail; idempotent bounded outbox. Add only observations/outcomes needed by this slice. | History survives API/app restart; cross-owner access denied; duplicate events create one outcome; response-loss retries safe; consent honored; export/deletion tested. |
| M2: Private trip diary | Editable grounded recap, notes, entry references; deliberate media support as a subsequent increment. | Recap cannot claim skipped stories were heard; failed generation preserves edits; offline edit conflicts handled; private media cannot be accessed by another user. |
| M3: Controlled sharing | Sanitized publication preview/snapshot, revocable unlisted links, exportable cards and platform-neutral sharing. | No private record exposed; precise sensitive locations removed; revocation and unauthorized reads tested; provider-content eligibility enforced. |
| M4: Community | Optional discoverable profiles, follows, feed, reactions/comments/bookmarks, moderation/report/block tools. | Audience ACLs and blocks enforced on all reads; abuse controls and moderation workflows operational before launch. |
| M5: Creator experiences | Versioned templates, Try This Adventure, Side Quests, tourism/creator profiles, sponsorship disclosure. | A new session is created rather than copying private history; routes/content revalidated; sponsored content distinguishable. |
| M6: Predictive ranking | Consent-based ranking from sufficient real outcomes, with deterministic safety constraints and evaluation. | Measurable improvement against existing ranking; opt-out respected; social engagement not silently repurposed; rollback available. |

## 11. Risks and Decisions Still Needed

- Which production identity provider and secure guest mechanism should be used? Resolve before durable private cloud data is enabled.
- Which deployed database and persistent storage are actually available, and which SQL has been applied? Source does not answer deployment state.
- Should history preserve only planned route plus confirmed stops by default? Recommended: yes; precise travelled traces remain separately opt-in.
- What retention periods and export/deletion service expectations apply to events, media, diagnostics, and backups?
- What content may legally and contractually be retained or redistributed? A generated narrative is not automatically unrestricted.
- How should existing beta installations migrate without losing restoration state or allowing unauthorized account claims?
- Source-based tests do not verify outdoor GPS, mobile background execution, production credentials, provider latency, or billing limits. A recorded field acceptance run remains necessary.

## 12. Exact First Coding Scope

After approving identity and storage choices, implement **M1's smallest vertical slice**, with reliability fixes tracked separately:

1. Establish verified owner resolution and enforce it on the new private history surface. Add owner/claim rules to persisted walk sessions without duplicating their state machine.
2. Implement durable persistence for the existing walk lifecycle and minimal events: started, stop arrived, completed/cancelled, and distinct narration outcomes. Do not add media, social tables, predictive ranking, or AI recaps yet.
3. Add owner-scoped history list/detail and tests against a real disposable database, including restart, rollback, concurrency, deletion, and cross-owner access.
4. Replace Flutter's placeholder history with the list/detail and a bounded idempotent outcome outbox. Label planned versus visited information accurately.
5. Run a real walk, restart both sides, verify history and playback outcomes, then begin private diary drafting.

This is a scoped sequence, not permission to bypass the identity decision or silently migrate production data. Keep the existing staged narration changes separate from the foundation commits.

## Validation Performed

- Backend: `dotnet run --project rover_middleware/Rover.Tests --no-restore` -> **158 passed, 0 failed**.
- Flutter: existing Flutter tool snapshot, `test --no-pub --reporter failures-only` -> **189 passed**.
- No live provider calls, deployed database checks, phone field tests, or authentication penetration tests were performed for this audit.
- Existing staged Flutter work was preserved. The only intended repository addition from this audit is this report.
