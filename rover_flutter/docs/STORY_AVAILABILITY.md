# Story availability and replenishment

The journey collection now reports whether all current stories were heard,
unplayed stories remain ahead or behind, or no verified stories are available.
Skipped/dismissed stories are not described as heard. Off-route availability
uses the existing nearby-anchor check rather than route progress.

Refresh displays a progress indicator and an explicit result: new unplayed
stories added, no new verified stories found, or research unavailable.
Concurrent manual refresh is disabled. Pending and failed responses without a
pack retain the previous unexpired collection for the same walk/revision.
Refresh does not clear local completion history. Server-side collection merging
and source expiry remain unchanged.

Automatic replenishment checks the existing 800-metre look-ahead for less than
180 seconds of unheard narration. Its initial wait is one minute. Subsequent
attempts wait at least three minutes and 150 metres, or five minutes without
requiring movement. The existing six-attempt cap per walk, active-walk,
on-route, quiet-mode and offline safeguards remain. Manual refresh shares the
automatic cooldown but can still be requested explicitly after completion.

This change does not promise unlimited content or expand research geography,
change evidence requirements, add images, or introduce Just walk mode.
It requires a new Flutter APK, not an API deployment or new Railway variables.

Field check: listen through a short collection, linger without moving 150 metres,
and verify the refill indicator/result and preserved stories. Test a failed
refresh and a pack with stories ahead. A successful no-new-results response
should not be displayed as a network failure.
