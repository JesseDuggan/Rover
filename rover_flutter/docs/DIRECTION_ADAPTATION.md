# Direction-aware walking

Off-route handling proposes a new route; it never automatically accepts it.

- The existing server gate requires multiple accurate readings at least 50 m off route, including its GPS noise allowance.
- The app waits for GPS accuracy of 25 m or better, travel speed of at least 0.4 m/s, and a valid travel heading.
- At most one proposal is pending. Attempts and declined proposals have a five-minute cooldown.
- The map's off-route panel offers "Follow your new direction?". Review lists the proposed stops and remaining duration; accepting may change the destination.
- Nearby candidates must match interests and lie within 75 degrees of the travel heading. Visited, sponsored, dismissed, duplicate, and explicitly accessibility-limited candidates are excluded.
- Up to eight walking-route checks select at most four stops within the original time budget minus elapsed time. Existing pace and accessibility preferences reach the routing provider.
- The last selected stop becomes the new destination. A later Rejoin keeps that destination.
- Route/story-plan and narrative-arc refresh use the existing adaptation acceptance pipeline. The original route is untouched by evaluation or rejection.
- Movement over 30 m, a heading change over 60 degrees, expiry, or a revision change prevents accepting a stale proposal. Failed discovery leaves the walk unchanged.

## Field checks

1. Install build 20261029 and use the updated Railway backend.
2. Start a walk outdoors with good GPS reception.
3. Safely take a different public walking route and continue beyond 50 m from the planned route.
4. Tap "Follow your new direction?" on the map and inspect the proposed stops.
5. Choose Keep current route. Confirm the route stays unchanged and prompts do not immediately repeat.
6. On a later proposal, choose Follow new direction. Confirm the path and destination change, completed stops stay completed, and narration uses the refreshed route.
7. Move farther than 30 m while reviewing a proposal. Accepting should ask for a fresh suggestion, not apply an outdated route.

This release does not add chat, story exports, or actual-GPS full-walk replay.
