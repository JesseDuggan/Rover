# Phase 6 Report - Route Preview and Itinerary

Date: 2026-08-26

## Summary

Phase 6 replaces the early route-preview placeholders with a local mock
route-generation service and editable itinerary model. Route preview now works
without a backend and produces structured ROAMs with ordered stops, route
geometry, time totals, distance, accessibility notes, warnings, and edit
actions.

## Created and Updated

- `lib/src/adventure/roam.dart`
  - Added `RoverRoam`.
  - Added `RoverStop`.
  - Added `OrderedRoverStop`.
  - Added `MockRouteGenerationService`.
  - Added realistic sample ROAMs for San Francisco, New York City, and a short
    local discovery walk.
- `lib/src/maps/rover_map_view.dart`
  - Updated the map to consume ordered itinerary stops and route geometry.
  - Marker numbers are generated from `OrderedRoverStop.sequence`.
  - No sequence numbers are encoded into static map imagery.
- `lib/src/ui/placeholder_screens.dart`
  - Rebuilt route preview around the generated ROAM itinerary.
  - Added refresh and regenerate actions.
  - Added remove, replace, and drag reorder support for stops.
  - Added summary fields for total time, walking time, content time, distance,
    starting point, accessibility notes, and warnings.
- `test/roam_test.dart`
  - Added ordered-stop, reorder, replacement, distance, and time-budget tests.
- `test/widget_test.dart`
  - Updated route-preview expectations for the richer itinerary UI.

## ROAM Data

Each generated ROAM contains:

- Title
- Summary
- Total estimated time
- Walking time
- Content time
- Distance
- Starting point
- Ordered stops
- Route geometry
- Accessibility notes
- Weather or closure warnings when available
- Refresh and regenerate actions

Each stop contains:

- Generated sequence number from the ordered itinerary
- Name
- Image reference
- Short description
- Estimated visit time
- Coordinates
- Category
- Optional audio
- Why Rover selected it

## Sample ROAMs

Created realistic local sample data for:

- `Bayfront stories and hidden corners` - 90 minutes in San Francisco.
- `Midtown family discovery loop` - family exploration in New York City.
- `Short local discovery walk` - a compact neighborhood route.

The mock generator chooses an appropriate sample from the current
`AdventureRequest` and trims lower-priority trailing stops when needed to fit a
tighter time budget.

## Itinerary Editing

The route preview supports:

- Refreshing the current route totals.
- Regenerating the route with a new mock warning state.
- Removing a stop.
- Replacing a stop with a same-category alternate.
- Reordering stops with `ReorderableListView`.

After edits, `RoverRoam.copyWith` recalculates walking time, content time,
distance, route geometry, and sequential stop numbers from the updated ordered
stop list.

## Verification

Commands completed:

- `dart --disable-dart-dev format lib test`
- `flutter analyze`
- `flutter test --no-test-assets`
- `flutter build apk --debug --no-pub`

Results:

- Formatting: passed.
- `flutter analyze`: passed with no issues.
- `flutter test --no-test-assets`: passed, 36 tests.
- Ordered-stop logic: covered by unit tests.
- Time-budget boundaries: covered by unit tests.
- Duplicate sequence prevention after reorder: covered by unit tests.
- Route preview without backend: covered by widget tests and local mock service.
- Credential scan: no tokens, API keys, passwords, or secrets found.

Android build status:

- The Android debug build command still returns exit code 1 in this local
  Gradle/JDK environment.
- Only Android Studio's bundled JBR was available during verification.
- Previous Gradle daemon logs showed the build action dispatching a successful
  result while the command process returned nonzero during daemon handling.
- Because the command exit code is still 1, the Android build requirement is not
  marked complete for Phase 6.

## Definition of Done

- [x] Ordered-stop logic has unit tests.
- [x] Time-budget calculation has boundary tests.
- [x] Reordering cannot produce duplicate numbers.
- [x] Route preview works without a backend.
- [!] Android debug build command does not exit successfully in this local
  Gradle/JDK environment.
- [x] Phase 6 report created.
