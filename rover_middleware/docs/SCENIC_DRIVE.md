# Scenic Drive (first release)

## Use it

1. Open the Walk creation screen and tap **Scenic Drive**.
2. Search for a destination (include the city or country), then select a result.
3. Choose **Return to start** if desired.
4. Set total time and time at each stop. Total time includes the destination visit.
5. Open **Interests** and choose from 12 categories or 48 specific interests. Review **Driving preferences**, then tap **Plan drive**.
6. Review the itinerary. If it exceeds your budget, increase the time or choose somewhere closer.
7. While safely parked, tap **Open driving directions**. An active walk is paused before Google Maps opens.
8. At a safe, permitted parking place, return to Walkabout and choose **Tell me about here**.

The car icon next to each itinerary place opens driving directions from the current location to that place.
Long itineraries are split into navigation sections containing at most three intermediate waypoints each. Select the next section while safely parked. Google Maps may adjust routes,
traffic estimates or waypoint support; check the itinerary before departing.

## Boundaries

- This is a driving itinerary planner and Google Maps handoff, not in-app turn-by-turn navigation.
- Walking sessions, arrival geofences, automatic walking narration and walking GPS replay are not used for drives.
- No automatic pass-by stories, drive recording, saved-drive library or drive sharing in this release.
- The itinerary remains on screen while the app stays open; it is not persisted across app termination.
- Suggested places are not verified parking locations. Opening hours, accessibility and parking need checking.
- Route estimates use traffic-aware road routing plus a 15% buffer (minimum 5 minutes).
- Up to six optional interest-based stops are accepted only after routing their detours within the time budget. Older clients default to two extra stops for navigation compatibility.
- Interests and driving preferences are remembered on this device, without storing destination or coordinates.
- Prefer local roads and avoid tolls are routing preferences, not guarantees. Optional rest and EV charging searches do not verify facilities or charger availability.
- Each accepted stop must fit the selected added-driving limit (5-60 minutes) and the total time budget. Unused time is shown; the planner does not promise to fill every minute.
- No fabricated route or walking fallback is returned if driving routing is unavailable.

## Backend

- GET /api/drive-places?query=...&lat=...&lng=...
- POST /api/scenic-drives
- Existing beta authentication and global rate limiter apply. Planning additionally has a 60/hour endpoint limit.
- Existing GoogleRoutes configuration and Google Places provider credentials are reused.
- Destination selection is re-resolved server-side by provider identity, within 1000 km of origin.
- Stop searches use a 3 km radius around outbound route samples. Trips are bounded to 30-720 minutes;
  stop duration is 5-60 minutes.
- No account records or stored walks are changed by planning.
- Interest searches cover outbound route samples with concurrency capped at four and a 35-second discovery budget. Partial discovery produces a warning. At most 16 candidate road-route proposals are checked.
- Requests support preferences and maxOptionalStops (1-6, default 2). The updated app requests 6 and allows up to 210 seconds for planning.

## Checks

ScenicDriveTests covers return-route budgeting, optional detour rejection, invalid selections, invalid budgets,
Google DRIVE request fields, GeoJSON parsing, missing credentials and provider failures.
Flutter scenic_drive_test covers chosen destination, request serialization, one-way and return URLs,
budget invalidation, disabled navigation for overbudget trips, parking confirmation and responsive layouts.
The walk flow regression checks that opening Scenic Drive neither starts nor replaces the walk.
