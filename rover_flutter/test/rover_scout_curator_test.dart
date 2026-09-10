import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rover/src/active_roam/active_roam_session.dart';
import 'package:rover/src/adventure/roam.dart';
import 'package:rover/src/location/rover_location.dart';
import 'package:rover/src/on_device_ai/rover_ai_models.dart';
import 'package:rover/src/on_device_ai/rover_ai_provider.dart';
import 'package:rover/src/on_device_ai/rover_ai_diagnostics_screen.dart';
import 'package:rover/src/on_device_ai/rover_curator.dart';
import 'package:rover/src/on_device_ai/rover_on_device_ai_coordinator.dart';
import 'package:rover/src/on_device_ai/rover_on_device_ai_scope.dart';
import 'package:rover/src/on_device_ai/rover_phase13_flags.dart';
import 'package:rover/src/on_device_ai/rover_scout.dart';

void main() {
  const scout = RoverScoutService();
  const curator = RoverCuratorService();
  final now = DateTime.utc(2026, 9, 1, 12);

  test('Scout derives movement route geofence and attention state', () {
    final walking = scout.derive(
      session: _session(distanceMeters: 400),
      reading: _reading(speed: 1.4),
      capturedAtUtc: now,
    );
    expect(walking.travelMode, RoverTravelMode.walking);
    expect(walking.routeState, RoverRouteState.onRoute);
    expect(walking.geofenceState, RoverGeofenceState.outside);
    expect(walking.attentionOpportunity, RoverAttentionOpportunity.open);

    final approaching = scout.derive(
      session: _session(distanceMeters: 90),
      reading: _reading(speed: 1.2),
      previous: walking,
      capturedAtUtc: now,
    );
    expect(approaching.geofenceState, RoverGeofenceState.approaching);
    expect(approaching.attentionOpportunity, RoverAttentionOpportunity.blocked);

    final inside = scout.derive(
      session: _session(distanceMeters: 20, arrivalCandidate: true),
      reading: _reading(speed: 0.2),
      previous: approaching,
      capturedAtUtc: now,
    );
    expect(inside.travelMode, RoverTravelMode.stationary);
    expect(inside.geofenceState, RoverGeofenceState.inside);

    final settledInside = scout.derive(
      session: _session(distanceMeters: 20, arrivedAtCurrentStop: true),
      reading: _reading(speed: 0.2),
      previous: inside,
      capturedAtUtc: now,
    );
    expect(settledInside.geofenceState, RoverGeofenceState.inside);
    expect(settledInside.attentionOpportunity, RoverAttentionOpportunity.open);

    final leaving = scout.derive(
      session: _session(distanceMeters: 80),
      reading: _reading(speed: 6),
      previous: settledInside,
      capturedAtUtc: now,
    );
    expect(leaving.travelMode, RoverTravelMode.driving);
    expect(leaving.geofenceState, RoverGeofenceState.leaving);
  });

  test(
    'Curator deterministically prefers verified interest and route match',
    () {
      final decision = curator.rank(
        situation: _situation(
          currentStopId: 'stop-1',
          nearbyVerifiedPoiIds: const ['history-story'],
        ),
        candidates: const [
          RoverCuratorStoryCandidate(
            storyId: 'general-story',
            verifiedEvidenceIds: ['fact-2'],
            interests: ['shopping'],
            confidence: 0.9,
            baseScore: 70,
          ),
          RoverCuratorStoryCandidate(
            storyId: 'history-story',
            verifiedEvidenceIds: ['fact-1'],
            interests: ['history'],
            routeStopIds: ['stop-1'],
            confidence: 0.8,
            baseScore: 50,
          ),
        ],
        preferences: const RoverCuratorPreferences(interests: ['history']),
        nowUtc: now,
      );

      expect(decision.diagnosticCode, 'selected_deterministically');
      expect(decision.selected?.candidate.storyId, 'history-story');
      expect(decision.selected?.reasons, contains('interest match'));
      expect(decision.selected?.reasons, contains('current route relevance'));
      expect(decision.selected?.reasons, contains('nearby verified place'));
    },
  );

  test('Curator excludes unverified repeated excluded and stale stories', () {
    final decision = curator.rank(
      situation: _situation(),
      candidates: [
        const RoverCuratorStoryCandidate(
          storyId: 'unverified',
          verifiedEvidenceIds: [],
        ),
        const RoverCuratorStoryCandidate(
          storyId: 'repeated',
          verifiedEvidenceIds: ['fact-repeated'],
        ),
        const RoverCuratorStoryCandidate(
          storyId: 'excluded',
          verifiedEvidenceIds: ['fact-excluded'],
          exclusionTags: ['nightlife'],
        ),
        RoverCuratorStoryCandidate(
          storyId: 'stale',
          verifiedEvidenceIds: const ['fact-stale'],
          freshness: RoverStoryFreshness.timeSensitive,
          expiresAtUtc: now.subtract(const Duration(minutes: 1)),
        ),
        const RoverCuratorStoryCandidate(
          storyId: 'eligible',
          verifiedEvidenceIds: ['fact-eligible'],
        ),
      ],
      preferences: const RoverCuratorPreferences(exclusions: ['nightlife']),
      previouslyNarratedContentIds: const {'fact-repeated'},
      nowUtc: now,
    );

    expect(decision.selected?.candidate.storyId, 'eligible');
    expect(decision.excludedCandidateCount, 4);
    expect(decision.rankedCandidates, hasLength(1));
  });

  test('Curator suppresses optional selection during navigation urgency', () {
    final decision = curator.rank(
      situation: _situation(
        routeState: RoverRouteState.offRoute,
        attention: RoverAttentionOpportunity.blocked,
      ),
      candidates: const [
        RoverCuratorStoryCandidate(
          storyId: 'verified-story',
          verifiedEvidenceIds: ['fact-1'],
          baseScore: 90,
        ),
      ],
      preferences: const RoverCuratorPreferences(),
      nowUtc: now,
    );

    expect(decision.selected, isNull);
    expect(decision.diagnosticCode, 'navigation_urgent');
    expect(decision.rankedCandidates, hasLength(1));
  });

  test('Curator resolves equal scores by stable story identifier', () {
    final decision = curator.rank(
      situation: _situation(),
      candidates: const [
        RoverCuratorStoryCandidate(
          storyId: 'story-b',
          verifiedEvidenceIds: ['fact-b'],
        ),
        RoverCuratorStoryCandidate(
          storyId: 'story-a',
          verifiedEvidenceIds: ['fact-a'],
        ),
      ],
      preferences: const RoverCuratorPreferences(),
      nowUtc: now,
    );

    expect(decision.selected?.candidate.storyId, 'story-a');
  });

  test('coordinator runs deterministic curation without enabling speech', () {
    final coordinator = RoverOnDeviceAiCoordinator(
      flags: const RoverPhase13Flags(enabled: true, curatorLocal: true),
      provider: const DisabledRoverAiProvider(),
    );
    final situation = coordinator.observeSituation(
      session: _session(distanceMeters: 400),
      reading: _reading(speed: 1.2),
      nearbyVerifiedPoiIds: const ['story-1'],
      capturedAtUtc: now,
    );
    final first = coordinator.curate(
      situation: situation,
      candidates: const [
        RoverCuratorStoryCandidate(
          storyId: 'story-1',
          verifiedEvidenceIds: ['fact-1'],
        ),
      ],
      preferences: const RoverCuratorPreferences(),
      nowUtc: now,
    );

    expect(first.selected?.candidate.storyId, 'story-1');
    expect(coordinator.autonomousCurationSpeechEnabled, isFalse);

    coordinator.markContentNarrated(const ['fact-1']);
    final repeated = coordinator.curate(
      situation: situation,
      candidates: const [
        RoverCuratorStoryCandidate(
          storyId: 'story-1',
          verifiedEvidenceIds: ['fact-1'],
        ),
      ],
      preferences: const RoverCuratorPreferences(),
      nowUtc: now,
    );
    expect(repeated.selected, isNull);
    expect(repeated.diagnosticCode, 'no_eligible_verified_story');
  });

  test(
    'coordinator notifies listeners only when visible Scout state changes',
    () async {
      final coordinator = RoverOnDeviceAiCoordinator(
        flags: const RoverPhase13Flags(enabled: true, curatorLocal: true),
        provider: const DisabledRoverAiProvider(),
      );
      var notifications = 0;
      coordinator.addListener(() => notifications += 1);

      coordinator.observeSituation(
        session: _session(distanceMeters: 400),
        reading: _reading(speed: 1.2),
        capturedAtUtc: now,
      );
      coordinator.observeSituation(
        session: _session(distanceMeters: 400),
        reading: _reading(speed: 1.2),
        capturedAtUtc: now.add(const Duration(seconds: 5)),
      );
      coordinator.observeSituation(
        session: _session(distanceMeters: 400),
        reading: _reading(speed: 6),
        capturedAtUtc: now.add(const Duration(seconds: 10)),
      );

      expect(notifications, 2);
      await coordinator.dispose();
    },
  );

  testWidgets('AI diagnostics follows live Scout state without refresh', (
    tester,
  ) async {
    final coordinator = RoverOnDeviceAiCoordinator(
      flags: const RoverPhase13Flags(enabled: true, curatorLocal: true),
      provider: const DisabledRoverAiProvider(),
    );
    addTearDown(coordinator.dispose);
    coordinator.observeSituation(
      session: _session(distanceMeters: 400),
      reading: _reading(speed: 1.2),
      capturedAtUtc: now,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: RoverOnDeviceAiScope(
          coordinator: coordinator,
          child: const RoverAiDiagnosticsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Travel mode'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('walking'), findsOneWidget);

    coordinator.observeSituation(
      session: _session(distanceMeters: 400),
      reading: _reading(speed: 6),
      capturedAtUtc: now.add(const Duration(seconds: 5)),
    );
    await tester.pump();

    expect(find.text('driving'), findsOneWidget);
    expect(find.text('walking'), findsNothing);
  });

  testWidgets('AI diagnostics refresh requests new capabilities', (
    tester,
  ) async {
    final provider = _CountingRoverAiProvider();
    final coordinator = RoverOnDeviceAiCoordinator(
      flags: const RoverPhase13Flags(enabled: true, curatorLocal: true),
      provider: provider,
    );
    addTearDown(coordinator.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: RoverOnDeviceAiScope(
          coordinator: coordinator,
          child: const RoverAiDiagnosticsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(provider.capabilityCalls, 1);
    expect(find.text('Screen refreshed'), findsOneWidget);

    await tester.tap(find.byTooltip('Refresh capabilities'));
    await tester.pumpAndSettle();

    expect(provider.capabilityCalls, 2);
  });
}

class _CountingRoverAiProvider extends DisabledRoverAiProvider {
  int capabilityCalls = 0;

  @override
  Future<RoverAiCapabilitySnapshot> getCapabilities() async {
    capabilityCalls += 1;
    return RoverAiCapabilitySnapshot.unsupported(
      checkedAtUtc: DateTime.utc(2026, 9, 1, 12, 0, capabilityCalls),
    );
  }
}

RoamSession _session({
  required double distanceMeters,
  bool arrivalCandidate = false,
  bool arrivedAtCurrentStop = false,
}) {
  const stop = RoverStop(
    id: 'stop-1',
    name: 'Verified stop',
    image: '',
    shortDescription: 'A sourced place.',
    estimatedVisitMinutes: 5,
    coordinates: RoverLatLng(latitude: 44.0, longitude: -76.0),
    category: 'history',
    whySelected: 'Route relevance',
  );
  const roam = RoverRoam(
    title: 'Test ROAM',
    summary: 'Test',
    walkingMinutes: 20,
    distanceMiles: 1,
    startingPoint: 'Test',
    stops: [stop],
    routeGeometry: [RoverLatLng(latitude: 44.0, longitude: -76.0)],
    accessibilityNotes: [],
    warnings: [],
  );
  return RoamSession(
    roam: roam,
    status: RoamSessionStatus.active,
    currentStopIndex: 0,
    completedStopIds: const {},
    skippedStopIds: const {},
    simulatedLocation: const RoverLatLng(latitude: 44.0, longitude: -76.01),
    audioStatus: AudioPlaybackStatus.stopped,
    screenAwake: true,
    arrivedAtCurrentStop: arrivedAtCurrentStop,
    distanceToNextStopMeters: distanceMeters,
    arrivalCandidate: arrivalCandidate,
    arrivalCandidateStopId: arrivalCandidate ? stop.id : null,
  );
}

RoverLocationReading _reading({required double speed}) {
  return RoverLocationReading(
    location: const RoverLatLng(latitude: 44.0, longitude: -76.01),
    recordedAtUtc: DateTime.utc(2026, 9, 1, 12),
    accuracyMeters: 5,
    speedMetersPerSecond: speed,
  );
}

RoverSituationSnapshot _situation({
  RoverRouteState routeState = RoverRouteState.onRoute,
  RoverAttentionOpportunity attention = RoverAttentionOpportunity.open,
  String? currentStopId,
  List<String> nearbyVerifiedPoiIds = const [],
}) {
  return RoverSituationSnapshot(
    capturedAtUtc: DateTime.utc(2026, 9, 1, 12),
    travelMode: RoverTravelMode.walking,
    routeState: routeState,
    geofenceState: RoverGeofenceState.outside,
    attentionOpportunity: attention,
    connectivityState: RoverConnectivityState.online,
    offlineCacheState: RoverOfflineCacheState.unavailable,
    routeRevision: 1,
    currentStopId: currentStopId,
    nearbyVerifiedPoiIds: nearbyVerifiedPoiIds,
  );
}
