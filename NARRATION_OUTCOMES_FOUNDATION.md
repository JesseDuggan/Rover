# Narration Outcomes Foundation

First incremental implementation following the journey-memory audit.

## Implemented

Route-pack state now includes `playbackOutcomes` with distinct sets:

- `completedStoryIds`
- `skippedStoryIds`
- `dismissedStoryIds`
- `interruptedStoryIds`
- `failedStoryIds`

Only an explicit `Completed` report adds a completed story. Reports for saving,
starting, pausing, or replaying do not imply completion. Repeated reports for the
same story/outcome are case-insensitively deduplicated. A story may appear in
multiple sets if different attempts had different outcomes; these are not counts
of attempts or a chronological event journal.

The existing playback-events endpoint additionally accepts `Interrupted` and
`Failed`. Undefined numeric enum values are rejected. Flutter now reports these
outcomes from a typed voice-controller result. A user pause remains `Paused`, a
preflight safety hold is not a failure, and successful device fallback remains a
completion. There is no new history screen in this increment.

`heardStoryIds` remains the legacy autoplay exclusion set. Changing its meaning
would risk replaying skipped or dismissed stories. Future diary consumers must
use explicit completion outcomes, never that exclusion set, as reported listening
evidence. Client reports are not independently verified proof of listening.

## Refresh and Compatibility

Short in-process state-update locks prevent playback reports from overwriting
one another and allow successful or failed research refreshes to preserve current
outcomes. Network research is outside these locks. This is not cross-replica
database concurrency control.

The existing file repository serializes the new state when persistent caching is
enabled. Old cache files without outcomes remain readable with empty outcome
sets: historical exclusion data is deliberately not reclassified as completed.

Retention is still route-pack cache retention and outcomes remain revision-scoped.
This is not durable private journey history, a database migration, or a diary.
No new personal information, precise location trace, public endpoint, or social
sharing was added. Existing cache content-eligibility rules are unchanged.

## Verification and Rollout

Run the backend suite from the repository root:

```powershell
dotnet run --project rover_middleware/Rover.Tests --no-restore
```

Coverage includes outcome separation, duplicate/case-variant reports, unchanged
autoplay exclusions, file reload, legacy cache loading, and playback reported
during successful and failed refreshes.

Deploy the API before installing the updated Flutter build: older APIs do not
accept the new event kinds. No API deployment or Git commit was performed here.
Flutter changes build on the existing staged narration fixes without replacing
them. The offline event queue also retains the new outcome kinds for later sync.

## Phone Acceptance Check

1. Install the updated APK after deploying the matching API. Start a walk with a
   ready story pack and verify POI arrival audio still has priority.
2. Let a story finish. Expect one `Completed` report and no automatic repeat when
   another GPS update arrives.
3. Reach a navigation instruction during a story. Expect `Interrupted`, not
   `Completed` or `Failed`; after navigation clears, resume at the interrupted
   sentence rather than the beginning of the entire story.
4. Pause a story manually, then wait through several GPS/poll updates. It must
   remain paused until Resume is selected.
5. Check provider fallback: when premium delivery fails but device speech works,
   the story still completes. A genuine audio failure should display a retry
   message and leave the story available rather than marking it heard.
6. Disconnect during a playback outcome report, reconnect, and check queued
   events synchronize. Failed/interrupted reports must not become completions.

Automated Flutter coverage includes typed voice results, navigation interruption
and sentence-boundary resume, failure cleanup/retry, manual pause, successful
device fallback, and online/offline outcome submission. Real outdoor GPS,
background execution, installed credentials, and production audio remain field
checks.

Flutter integration validation: all 200 tests passed. Static analysis reported
no errors or warnings and three pre-existing style information notices. The APK
build attempt targeted 1.0.0+11, but no successful new APK was produced during
this validation; do not mistake the existing output APK for this update.

Next: choose production identity and durable storage, then implement owner-scoped
journey history. Field-verify the playback integration before relying on these
outcomes for journey coverage metrics.
