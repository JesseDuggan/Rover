import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rover/src/active_roam/active_roam_controller.dart';
import 'package:rover/src/active_roam/active_roam_repository.dart';
import 'package:rover/src/active_roam/active_roam_session.dart';
import 'package:rover/src/active_roam/screen_awake_controller.dart';
import 'package:rover/src/adventure/adventure_request.dart';
import 'package:rover/src/api/adaptation_models.dart';
import 'package:rover/src/api/adaptive_route_story_models.dart';
import 'package:rover/src/api/ask_rover_models.dart';
import 'package:rover/src/api/journey_narration_models.dart';
import 'package:rover/src/api/local_discovery_options.dart';
import 'package:rover/src/api/location_story_models.dart';
import 'package:rover/src/api/location_observation_models.dart';
import 'package:rover/src/api/location_update_models.dart';
import 'package:rover/src/api/problem_details.dart';
import 'package:rover/src/api/profile_models.dart';
import 'package:rover/src/api/speech_models.dart';
import 'package:rover/src/api/rover_api_config.dart';
import 'package:rover/src/api/rover_api_client.dart';
import 'package:rover/src/api/walk_models.dart';
import 'package:rover/src/api/walk_repository.dart';
import 'package:rover/src/location/rover_location.dart';
import 'package:rover/src/maps/google_maps_config.dart';
import 'package:rover/src/maps/mapbox_config.dart';

void main() {
  test('live map moves while a location request is still pending', () async {
    final locations = StreamController<RoverLocationReading>();
    final repository = _DelayedLocationRepository();
    final controller = ActiveRoamController(
      repository: MemoryActiveRoamRepository(),
      walkRepository: repository,
      locationProvider: _StreamingLocationProvider(locations.stream),
      screenAwakeController: MemoryScreenAwakeController(),
    );
    await controller.load();
    await controller.createWalk(
      request: _adventureRequest(),
      location: const RoverLatLng(latitude: 37.7879, longitude: -122.4075),
    );
    await controller.startApiWalk();
    final now = DateTime.now().toUtc();
    locations.add(
      RoverLocationReading(
        location: const RoverLatLng(latitude: 37.7900, longitude: -122.4100),
        recordedAtUtc: now,
        accuracyMeters: 5,
      ),
    );
    await repository.started.future;
    const newer = RoverLatLng(latitude: 37.79004, longitude: -122.4100);
    locations.add(
      RoverLocationReading(
        location: newer,
        recordedAtUtc: now.add(const Duration(seconds: 2)),
        accuracyMeters: 5,
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(controller.session.simulatedLocation, newer);
    repository.release.complete();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(controller.session.simulatedLocation, newer);
    await controller.stopLocationTracking();
    controller.dispose();
    await locations.close();
  });
  test('API duration includes visits exactly once', () {
    final walk = WalkSession.fromJson(_walkJson());
    final roam = walk.toRoam();
    expect(roam.contentMinutes, greaterThan(0));
    expect(roam.totalEstimatedMinutes, walk.estimatedDurationMinutes);
    expect(
      roam.walkingMinutes,
      walk.estimatedDurationMinutes - roam.contentMinutes,
    );
  });
  tearDown(() => RoverApiConfig.setDevelopmentOverride(null));

  for (final offRoute in [false, true]) {
    test(
      'unheard geofence entry survives stale candidate and rejoin: offRoute=$offRoute',
      () async {
        final locations = StreamController<RoverLocationReading>();
        final controller = ActiveRoamController(
          repository: MemoryActiveRoamRepository(),
          walkRepository: _PendingArrivalRepository(offRoute: offRoute),
          locationProvider: _StreamingLocationProvider(locations.stream),
          screenAwakeController: MemoryScreenAwakeController(),
        );
        await controller.load();
        await controller.createWalk(
          request: _adventureRequest(),
          location: const RoverLatLng(latitude: 37.7879, longitude: -122.4075),
        );
        await controller.startApiWalk();
        await controller.markArrivalNarrated('union-square-plaza');

        Future<void> reading(int second) async {
          final recordedAt = DateTime.utc(2026, 9, 17, 12, 0, second);
          locations.add(
            RoverLocationReading(
              location: const RoverLatLng(
                latitude: 37.7879,
                longitude: -122.4075,
              ),
              recordedAtUtc: recordedAt,
              accuracyMeters: 5,
            ),
          );
          for (var attempt = 0; attempt < 100; attempt++) {
            await Future<void>.delayed(const Duration(milliseconds: 10));
            if (controller.latestLocationReading?.recordedAtUtc == recordedAt &&
                controller.session.geofenceEntryDebug != null) {
              return;
            }
          }
          fail('Location update did not finish');
        }

        await reading(0);
        await Future<void>.delayed(const Duration(milliseconds: 100));
        expect(controller.session.recentNarrationStopId, 'sponsored-gear-stop');
        await reading(10);
        expect(controller.session.recentNarrationStopId, 'sponsored-gear-stop');
        expect(
          controller.session.geofenceEntryDebug,
          contains('recovered entry'),
        );
        await controller.markArrivalNarrated('sponsored-gear-stop');
        await reading(20);
        expect(controller.session.recentNarrationStopId, isNull);

        await controller.stopLocationTracking();
        await locations.close();
        controller.dispose();
      },
    );
  }

  test('Phase 16 route story requests serialize and packs parse', () {
    const request = NextRouteStoryRequest(
      routeProgressMeters: 125.5,
      secondsUntilNextManeuver: 70,
      preferredLength: 'Short',
      excludedStoryIds: ['heard-1'],
    );
    final state = AdaptiveRouteStoryPackState.fromJson({
      'walkSessionId': 'walk-1',
      'routeRevision': 2,
      'status': 'Ready',
      'updatedUtc': '2026-09-07T12:00:00Z',
      'heardStoryIds': <String>['heard-1'],
      'pack': {
        'schemaVersion': '3.0',
        'packId': 'pack-1',
        'idempotencyKey': 'key-1',
        'walkSessionId': 'walk-1',
        'routeId': 'route-1',
        'routeRevision': 2,
        'promptVersion': 'phase16-deterministic-v1',
        'generatedUtc': '2026-09-07T12:00:00Z',
        'expiresUtc': '2026-09-09T12:00:00Z',
        'stories': <Map<String, dynamic>>[],
        'warnings': <String>[],
      },
    });

    expect(request.toJson()['routeProgressMeters'], 125.5);
    expect(request.toJson()['excludedStoryIds'], ['heard-1']);
    expect(state.status, 'Ready');
    expect(state.routeRevision, 2);
    expect(state.pack?.schemaVersion, '3.0');
  });

  test('API URL configuration joins paths safely', () {
    const config = RoverApiConfig(baseUrl: ' http://10.0.2.2:5080/// ');

    expect(config.normalizedBaseUrl, 'http://10.0.2.2:5080');
    expect(config.uri('/health').toString(), 'http://10.0.2.2:5080/health');
    expect(
      config.uri('api/walks').toString(),
      'http://10.0.2.2:5080/api/walks',
    );
  });

  test('API URL defaults match local development platforms', () {
    expect(
      RoverApiConfig.resolveBaseUrl(
        suppliedBaseUrl: '',
        platform: TargetPlatform.android,
      ),
      'http://10.0.2.2:5080',
    );
    expect(
      RoverApiConfig.resolveBaseUrl(
        suppliedBaseUrl: '',
        platform: TargetPlatform.windows,
      ),
      'http://127.0.0.1:5080',
    );
    expect(
      RoverApiConfig.resolveBaseUrl(
        suppliedBaseUrl: '',
        platform: TargetPlatform.android,
        isWeb: true,
      ),
      'http://127.0.0.1:5080',
    );
  });

  test('supplied LAN API URL overrides platform defaults', () {
    expect(
      RoverApiConfig.resolveBaseUrl(
        suppliedBaseUrl: ' http://192.168.137.1:5080/ ',
        platform: TargetPlatform.android,
      ),
      'http://192.168.137.1:5080',
    );
    expect(
      () => RoverApiConfig.normalizeBaseUrl('192.168.1.4:5080'),
      throwsArgumentError,
    );
  });

  test('named beta API environment uses Railway HTTPS URL', () {
    expect(
      RoverApiConfig.resolveBaseUrl(
        suppliedBaseUrl: '',
        environment: 'beta',
        betaBaseUrl: 'https://rover-api.up.railway.app',
        platform: TargetPlatform.android,
      ),
      'https://rover-api.up.railway.app',
    );
  });

  test('debug runtime API override updates existing configurations', () {
    const config = RoverApiConfig(baseUrl: 'http://10.0.2.2:5080');

    RoverApiConfig.setDevelopmentOverride('http://10.23.45.67:5080/');

    expect(config.normalizedBaseUrl, 'http://10.23.45.67:5080');
    expect(config.uri('/health').toString(), 'http://10.23.45.67:5080/health');
  });

  test('request serialization matches middleware contract', () {
    const request = CreateWalkRequest(
      latitude: 37.7879,
      longitude: -122.4075,
      availableMinutes: 60,
      interests: ['architecture'],
      walkingPace: 'Standard',
      accessibilityPreferences: ['AvoidStairs'],
    );

    expect(request.toJson(), {
      'latitude': 37.7879,
      'longitude': -122.4075,
      'availableMinutes': 60,
      'interests': ['architecture'],
      'walkingPace': 'Standard',
      'accessibilityPreferences': ['AvoidStairs'],
      'naturalRequest': '',
      'companions': 'Solo',
      'routeShape': 'Loop route',
      'environment': 'Either',
      'includePaidAttractions': false,
      'surpriseMe': false,
    });
  });

  test('tester profile is optional and carries no market settings', () {
    const request = CreateWalkRequest(
      latitude: 43.65,
      longitude: -79.37,
      availableMinutes: 60,
      interests: ['history'],
      walkingPace: 'Standard',
      accessibilityPreferences: [],
      profileId: 'f8cf7c6e-86d3-4a6f-8da2-1a0e13a1340c',
    );
    expect(request.toJson()['profileId'], request.profileId);
    expect(request.toJson().containsKey('market'), isFalse);
  });

  for (final mode in ['resolved', 'unavailable', 'explicit']) {
    test('walk profile lookup is optional: $mode', () async {
      final client = _ProfileCapturingApiClient();
      addTearDown(client.close);
      var lookups = 0;
      final repository = HttpWalkRepository(
        client: client,
        profileIdResolver: () async {
          lookups++;
          if (mode == 'unavailable') throw StateError('Profile offline');
          return 'f8cf7c6e-86d3-4a6f-8da2-1a0e13a1340c';
        },
      );
      final session = await repository.createWalk(
        CreateWalkRequest(
          latitude: 43.65,
          longitude: -79.37,
          availableMinutes: 60,
          interests: const ['history'],
          walkingPace: 'Standard',
          accessibilityPreferences: const [],
          profileId: mode == 'explicit'
              ? '11111111-1111-1111-1111-111111111111'
              : null,
        ),
      );
      expect(session.stops, isNotEmpty);
      expect(lookups, mode == 'explicit' ? 0 : 1);
      expect(client.receivedProfileId, switch (mode) {
        'explicit' => '11111111-1111-1111-1111-111111111111',
        'resolved' => 'f8cf7c6e-86d3-4a6f-8da2-1a0e13a1340c',
        _ => null,
      });
    });
  }

  test('Phase 15.8 narration memory contracts round trip', () {
    final occurredAt = DateTime.utc(2026, 9, 4, 12);
    final interaction = StoryInteractionRequest(
      eventId: 'event-1',
      storyId: 'story-1',
      category: 'history',
      kind: 'Completed',
      occurredAtUtc: occurredAt,
    );
    const narration = JourneyNarrationEvaluateRequest(
      location: RoverLatLng(latitude: 44.678, longitude: -76.395),
      profileId: '11111111-1111-1111-1111-111111111111',
    );
    final decision = JourneyNarrationDecision.fromJson({
      'shouldNarrate': true,
      'kind': 'LocalHistory',
      'priority': 'ContextualStory',
      'cooldownSeconds': 90,
      'factIdsUsed': <String>[],
      'sourceReferences': <Map<String, dynamic>>[],
      'warnings': <String>[],
      'rankingScore': 112.5,
      'rankingReasons': <String>['explicit preference +20'],
    });

    expect(interaction.toJson()['kind'], 'Completed');
    expect(interaction.toJson()['occurredAtUtc'], '2026-09-04T12:00:00.000Z');
    expect(narration.toJson()['profileId'], narration.profileId);
    expect(decision.rankingScore, 112.5);
    expect(decision.rankingReasons, contains('explicit preference +20'));
  });

  test('Phase 15.9 speech cache policy serializes explicitly', () {
    final expires = DateTime.utc(2026, 9, 5, 12);
    final request = RenderSpeechRequest(
      text: 'A reusable grounded story.',
      purpose: 'StopNarration',
      cacheEligible: true,
      cacheExpiresUtc: expires,
      storyId: 'story-1',
      variantId: 'story-1:standard',
    );

    expect(request.toJson()['cacheEligible'], isTrue);
    expect(request.toJson()['cacheExpiresUtc'], '2026-09-05T12:00:00.000Z');
    expect(request.toJson()['variantId'], 'story-1:standard');
  });

  test('response parsing and enum fallback are safe', () {
    final session = WalkSession.fromJson(_walkJson(status: 'Ready'));

    expect(session.walkSessionId, 'walk-1');
    expect(session.status, WalkStatus.ready);
    expect(session.stops.first.contentSource, WalkContentSource.roverEditorial);
    expect(WalkStatus.parse('FutureStatus'), WalkStatus.unknown);
    expect(WalkContentType.parse('FutureType'), WalkContentType.unknown);
    expect(session.route!.provider, 'Mock');
    expect(session.route!.coordinates.first.longitude, -122.4075);
    expect(session.routeQuality!.estimatedExperienceTimeMinutes, 30);
    expect(session.lifecycleConsistency!.isConsistent, isTrue);
  });

  test('Mapbox token configuration is explicit and non-crashing', () {
    const config = MapboxConfig();

    expect(config.hasPublicToken, isFalse);
    expect(config.developmentMessage, contains('MAPBOX_PUBLIC_TOKEN'));
  });

  test('Google Maps Android key configuration is explicit', () {
    const missing = GoogleMapsConfig(apiKey: '');
    const configured = GoogleMapsConfig(apiKey: 'android-restricted-key');

    expect(missing.hasApiKey, isFalse);
    expect(missing.developmentMessage, contains('GOOGLE_MAPS_ANDROID_API_KEY'));
    expect(configured.hasApiKey, isTrue);
    expect(configured.developmentMessage, isNull);
  });

  test('ProblemDetails parsing prefers detail and captures errors', () {
    final problem = ProblemDetails.fromJson({
      'title': 'Validation failed',
      'status': 400,
      'detail': 'Coordinates are invalid.',
      'errors': {
        'latitude': ['Latitude is required.'],
      },
    });

    expect(problem.displayMessage, 'Coordinates are invalid.');
    expect(problem.errors['latitude'], ['Latitude is required.']);
  });

  test(
    'repository operations delegate to HTTP implementation boundary',
    () async {
      final repository = FakeWalkRepository();
      final created = await repository.createWalk(_request());
      final started = await repository.startWalk(created.walkSessionId);
      final arrived = await repository.arriveAtStop(
        created.walkSessionId,
        started.nextStop!.stopId,
      );
      final location = await repository.updateLocation(
        created.walkSessionId,
        LocationUpdateRequest(
          location: started.nextStop!.coordinates,
          recordedAtUtc: DateTime.utc(2026, 8, 27, 15),
          accuracyMeters: 8,
        ),
      );

      expect(repository.calls, [
        'createWalk',
        'startWalk',
        'arriveAtStop:union-square-plaza',
        'updateLocation',
      ]);
      expect(arrived.visitedStopCount, 1);
      expect(location.arrivalCandidate, isTrue);
    },
  );

  test(
    'controller creates, starts, simulates arrival, completes and cancels',
    () async {
      final repository = FakeWalkRepository();
      final controller = ActiveRoamController(
        repository: MemoryActiveRoamRepository(),
        walkRepository: repository,
        locationProvider: _FakeLocationProvider(
          const RoverLatLng(latitude: 37.7879, longitude: -122.4075),
        ),
        screenAwakeController: MemoryScreenAwakeController(),
      );
      await controller.load();

      await controller.createWalk(
        request: _adventureRequest(),
        location: const RoverLatLng(latitude: 37.7879, longitude: -122.4075),
      );
      expect(controller.session.apiWalkSessionId, 'walk-1');
      expect(controller.session.status, RoamSessionStatus.notStarted);

      await controller.startApiWalk();
      expect(controller.session.status, RoamSessionStatus.active);

      await controller.simulateArrivalAtNextStop();
      expect(
        controller.session.completedStopIds,
        contains('union-square-plaza'),
      );

      while (controller.session.completedStopIds.length <
          controller.session.roam.stops.length) {
        await controller.simulateArrivalAtNextStop();
      }

      await controller.completeApiWalk();
      expect(controller.session.status, RoamSessionStatus.completed);

      await controller.cancelApiWalk();
      expect(controller.session.status, RoamSessionStatus.ended);
      expect(controller.session.errorMessage, isNull);
    },
  );

  test(
    'failed remote cancellation releases saved walk and rejects late GPS',
    () async {
      final locations = StreamController<RoverLocationReading>.broadcast();
      final repository = _FailedCancellationRepository();
      final storage = MemoryActiveRoamRepository();
      final controller = ActiveRoamController(
        repository: storage,
        walkRepository: repository,
        locationProvider: _StreamingLocationProvider(locations.stream),
        screenAwakeController: MemoryScreenAwakeController(),
      );
      await controller.load();
      await controller.createWalk(
        request: _adventureRequest(),
        location: const RoverLatLng(latitude: 37.7879, longitude: -122.4075),
      );
      await controller.startApiWalk();
      locations.add(
        RoverLocationReading(
          location: const RoverLatLng(latitude: 37.7879, longitude: -122.4075),
          recordedAtUtc: DateTime.now().toUtc(),
          accuracyMeters: 5,
        ),
      );
      await repository.started.future;
      await controller.cancelApiWalk();
      expect(controller.isTrackingLocation, isFalse);
      expect(controller.session.status, RoamSessionStatus.ended);
      expect(controller.session.errorMessage, isNull);
      repository.release.complete();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(controller.session.status, RoamSessionStatus.ended);
      expect((await storage.load())!.status, RoamSessionStatus.ended);
      await controller.createWalk(
        request: _adventureRequest(),
        location: const RoverLatLng(latitude: 37.7879, longitude: -122.4075),
      );
      await controller.startApiWalk();
      expect(controller.session.status, RoamSessionStatus.active);
      expect(controller.isTrackingLocation, isTrue);
      controller.dispose();
      await locations.close();
    },
  );

  test('controller prevents duplicate API actions', () async {
    final repository = FakeWalkRepository(
      delay: const Duration(milliseconds: 50),
    );
    final controller = ActiveRoamController(
      repository: MemoryActiveRoamRepository(),
      walkRepository: repository,
      screenAwakeController: MemoryScreenAwakeController(),
    );
    await controller.load();

    final first = controller.createWalk(
      request: _adventureRequest(),
      location: const RoverLatLng(latitude: 37.7879, longitude: -122.4075),
    );
    final second = controller.createWalk(
      request: _adventureRequest(),
      location: const RoverLatLng(latitude: 37.7879, longitude: -122.4075),
    );
    await Future.wait([first, second]);

    expect(
      repository.calls.where((call) => call == 'createWalk'),
      hasLength(1),
    );
  });

  for (final outcome in ['accept', 'decline', 'moved', 'no heading', 'poor GPS', 'stationary']) {
    test(
      'off-route direction change requires approval: $outcome',
      () async {
        final locations = StreamController<RoverLocationReading>();
        final repository = FakeWalkRepository(offRoute: true);
        final controller = ActiveRoamController(
          repository: MemoryActiveRoamRepository(),
          walkRepository: repository,
          locationProvider: _StreamingLocationProvider(locations.stream),
          screenAwakeController: MemoryScreenAwakeController(),
        );
        await controller.load();
        await controller.createWalk(
          request: _adventureRequest(),
          location: const RoverLatLng(latitude: 37.7879, longitude: -122.4075),
        );
        await controller.startApiWalk();

        locations.add(
          RoverLocationReading(
            location: const RoverLatLng(
              latitude: 37.7920,
              longitude: -122.4140,
            ),
            recordedAtUtc: DateTime.utc(2026, 9, 3, 12),
            accuracyMeters: outcome == 'poor GPS' ? 80 : 5,
            headingDegrees: outcome == 'no heading' ? null : 90,
            speedMetersPerSecond: outcome == 'stationary' ? 0 : 1.2,
          ),
        );
        for (
          var attempt = 0;
          attempt < 50 && controller.session.pendingAdaptation == null;
          attempt++
        ) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }

        if (['no heading', 'poor GPS', 'stationary'].contains(outcome)) {
          expect(repository.calls, isNot(contains('evaluateAdaptation:FollowDirection')));
          expect(repository.calls, isNot(contains('acceptAdaptation:adapt-1')));
          await controller.stopLocationTracking();
          await locations.close();
          controller.dispose();
          return;
        }
        expect(repository.calls, contains('evaluateAdaptation:FollowDirection'));
        expect(repository.calls, isNot(contains('acceptAdaptation:adapt-1')));
        expect(controller.session.pendingAdaptation?.type, 'FollowDirection');
        if (outcome == 'moved') {
          locations.add(RoverLocationReading(
            location: const RoverLatLng(latitude: 37.7920, longitude: -122.4100),
            recordedAtUtc: DateTime.utc(2026, 9, 3, 12, 1),
            accuracyMeters: 5, headingDegrees: 90, speedMetersPerSecond: 1.2));
          await Future<void>.delayed(const Duration(milliseconds: 100));
          await controller.acceptPendingAdaptation();
          expect(repository.calls, isNot(contains('acceptAdaptation:adapt-1')));
          expect(controller.session.errorMessage, contains('position or route changed'));
        } else if (outcome == 'accept') {
          await controller.acceptPendingAdaptation();
          expect(repository.calls, contains('acceptAdaptation:adapt-1'));
        } else {
          await controller.rejectPendingAdaptation();
          expect(repository.calls, contains('rejectAdaptation:adapt-1'));
          expect(repository.calls, isNot(contains('acceptAdaptation:adapt-1')));
          locations.add(
            RoverLocationReading(
              location: const RoverLatLng(
                latitude: 37.7920,
                longitude: -122.4138,
              ),
              recordedAtUtc: DateTime.utc(2026, 9, 3, 12, 1),
              accuracyMeters: 5,
              headingDegrees: 90,
              speedMetersPerSecond: 1.2,
            ),
          );
          await Future<void>.delayed(const Duration(milliseconds: 100));
          expect(
            repository.calls.where(
              (call) => call == 'evaluateAdaptation:FollowDirection',
            ),
            hasLength(1),
          );
        }
        expect(controller.session.pendingAdaptation, isNull);
        await controller.stopLocationTracking();
        await locations.close();
        controller.dispose();
      },
    );
  }

  test('timeout and connection failures surface typed messages', () {
    const timeout = RoverApiTimeoutException('timed out');
    const connection = RoverApiConnectionException('connection failed');

    expect(timeout, isA<RoverApiException>());
    expect(connection, isA<RoverApiException>());
    expect(timeout.message, 'timed out');
    expect(connection.message, 'connection failed');
  });

  test('sponsored content disclosure is visible in parsed stop', () {
    final session = WalkSession.fromJson(_walkJson());
    final sponsored = session.stops.last;

    expect(sponsored.contentSource, WalkContentSource.sponsored);
    expect(sponsored.sponsoredDisclosure, contains('Sponsored content'));
    expect(sponsored.toRoverStop().isSponsored, isTrue);
  });

  test('Google Places attribution survives walk stop parsing', () {
    final json = _walkJson();
    final first = (json['stops'] as List).first as Map<String, dynamic>;
    first.addAll({
      'discoveryProviderName': 'GooglePlaces',
      'providerPlaceId': 'ChIJ-test',
      'sourceUrl': 'https://maps.google.com/?cid=test',
      'requiredAttribution': ['Google Maps'],
    });

    final stop = WalkSession.fromJson(json).stops.first;

    expect(stop.discoveryProviderName, 'GooglePlaces');
    expect(stop.providerPlaceId, 'ChIJ-test');
    expect(stop.requiredAttribution, ['Google Maps']);
    expect(stop.toRoverStop().attributionLabel, 'Google Maps');
  });
}

class _PendingArrivalRepository extends FakeWalkRepository {
  _PendingArrivalRepository({super.offRoute});
  @override
  Future<WalkSession> arriveAtStop(
    String walkSessionId,
    String stopId, {
    double? latitude,
    double? longitude,
  }) async {
    throw const RoverApiException('Confirmation pending', statusCode: 409);
  }
}

class _FakeLocationProvider implements RoverLocationProvider {
  const _FakeLocationProvider(this.location);

  final RoverLatLng location;

  @override
  String get label => 'Fake location';

  @override
  bool get requestsSystemPermission => false;

  @override
  Future<bool> isLocationServiceEnabled() async => true;

  @override
  Future<LocationFailure?> checkPermissionStatus() async => null;

  @override
  Future<LocationFailure?> requestForegroundPermission() async => null;

  @override
  Future<bool> openSettings() async => true;

  @override
  Future<RoverLocationResult> getCurrentLocation() async {
    return RoverLocationResult.success(location);
  }

  @override
  Stream<RoverLocationReading> watchLocation() async* {}
}

class _StreamingLocationProvider implements RoverLocationProvider {
  const _StreamingLocationProvider(this.readings);

  final Stream<RoverLocationReading> readings;

  @override
  String get label => 'Streaming test location';

  @override
  bool get requestsSystemPermission => false;

  @override
  Future<bool> isLocationServiceEnabled() async => true;

  @override
  Future<LocationFailure?> checkPermissionStatus() async => null;

  @override
  Future<LocationFailure?> requestForegroundPermission() async => null;

  @override
  Future<bool> openSettings() async => true;

  @override
  Future<RoverLocationResult> getCurrentLocation() async =>
      RoverLocationResult.success(
        const RoverLatLng(latitude: 37.7879, longitude: -122.4075),
      );

  @override
  Stream<RoverLocationReading> watchLocation() => readings;
}

CreateWalkRequest _request() {
  return const CreateWalkRequest(
    latitude: 37.7879,
    longitude: -122.4075,
    availableMinutes: 60,
    interests: ['architecture'],
    walkingPace: 'Standard',
    accessibilityPreferences: ['AvoidStairs'],
  );
}

AdventureRequest _adventureRequest() {
  return AdventureRequest.empty.copyWith(
    availableMinutes: 60,
    startingPoint: 'Union Square test location',
    interests: const ['architecture'],
    pace: 'Steady',
  );
}

class _ProfileCapturingApiClient extends RoverApiClient {
  String? receivedProfileId;

  @override
  Future<WalkSession> createWalk(
    CreateWalkRequest request, {
    String? profileId,
  }) async {
    receivedProfileId = request.profileId ?? profileId;
    return WalkSession.fromJson(_walkJson());
  }
}

Map<String, dynamic> _walkJson({String status = 'Ready', int visited = 0}) {
  final stops = [
    _stopJson('union-square-plaza', 1, visited: visited > 0),
    _stopJson(
      'sponsored-gear-stop',
      2,
      contentSource: 'Sponsored',
      contentType: 'SponsoredRecommendation',
      sponsoredDisclosure: 'Sponsored content: this stop is paid placement and is not Rover editorial content.',
      visited: visited > 1,
    ),
  ];
  final pendingStops = stops.where((stop) => stop['visited'] == false).toList();
  final nextStop = pendingStops.isEmpty ? null : pendingStops.first;
  return {
    'walkSessionId': 'walk-1',
    'status': status,
    'startingLocation': {'latitude': 37.7879, 'longitude': -122.4075},
    'lastKnownLocation': null,
    'createdAtUtc': '2026-08-27T14:44:07.9945999+00:00',
    'startedAtUtc': status == 'InProgress'
        ? '2026-08-27T14:45:07.9945999+00:00'
        : null,
    'completedAtUtc': status == 'Completed'
        ? '2026-08-27T14:55:07.9945999+00:00'
        : null,
    'cancelledAtUtc': status == 'Cancelled'
        ? '2026-08-27T14:55:07.9945999+00:00'
        : null,
    'availableMinutes': 60,
    'estimatedDurationMinutes': 51,
    'estimatedDistanceMeters': 840,
    'routeSummary': 'A compact Union Square loop.',
    'interests': ['architecture'],
    'walkingPace': 'Standard',
    'accessibilityPreferences': ['AvoidStairs'],
    'timeRemainingMinutes': 60 - (visited * 6),
    'visitedStopCount': visited,
    'walkProgressPercentage': visited / stops.length * 100,
    'nextStop': nextStop,
    'recentNarrationStopId': null,
    'recentNarration': null,
    'route': _routeJson(),
    'originalRoute': _routeJson(),
    'routeRevision': 1,
    'routeRevisions': [
      {
        'revision': 1,
        'reason': 'Original route',
        'appliedAtUtc': '2026-08-27T14:44:07.9945999+00:00',
        'addedStopIds': <String>[],
        'removedStopIds': <String>[],
        'reorderedStopIds': ['union-square-plaza', 'sponsored-gear-stop'],
      },
    ],
    'distanceToNextStopMeters': 12.5,
    'routeProgressPercentage': visited / stops.length * 100,
    'isOffRoute': false,
    'distanceFromRouteMeters': 4,
    'routeQuality': {
      'totalRouteDistanceMeters': 200,
      'estimatedWalkingTimeMinutes': 18,
      'estimatedStopTimeMinutes': 12,
      'estimatedExperienceTimeMinutes': 30,
      'availableTimeUtilization': 0.5,
      'backtrackingEstimateMeters': 0,
      'repeatedSegmentCount': 0,
      'returnToStartEstimateMeters': 25,
      'warnings': <String>[],
    },
    'lifecycleConsistency': {
      'isConsistent': true,
      'stopCount': stops.length,
      'routeRevision': 1,
      'nextStopId': nextStop?['stopId'],
      'warnings': <String>[],
    },
    'stops': stops,
  };
}

Map<String, dynamic> _routeJson() {
  return {
    'routeId': 'mock-union-square-v1',
    'provider': 'Mock',
    'version': 'union-square-v1',
    'generatedAtUtc': '2026-08-27T14:44:07.9945999+00:00',
    'coordinates': [
      {'longitude': -122.4075, 'latitude': 37.7879},
      {'longitude': -122.4075, 'latitude': 37.7880},
      {'longitude': -122.4075, 'latitude': 37.7879},
    ],
    'geoJson': {
      'type': 'LineString',
      'coordinates': [
        [-122.4075, 37.7879],
        [-122.4075, 37.7880],
        [-122.4075, 37.7879],
      ],
    },
    'bounds': {
      'southwest': {'longitude': -122.4075, 'latitude': 37.7879},
      'northeast': {'longitude': -122.4075, 'latitude': 37.7880},
    },
    'distanceMeters': 200,
    'durationMinutes': 18,
    'maneuvers': [
      {
        'sequenceNumber': 1,
        'instruction': 'Walk to stop 1: Union Square Plaza.',
        'distanceMeters': 0,
        'durationMinutes': 1,
      },
    ],
  };
}

Map<String, dynamic> _stopJson(
  String id,
  int sequence, {
  bool visited = false,
  String contentSource = 'RoverEditorial',
  String contentType = 'History',
  String? sponsoredDisclosure,
}) {
  return {
    'stopId': id,
    'sequenceNumber': sequence,
    'name': sequence == 1
        ? 'Union Square Plaza'
        : 'Sponsored Walking Gear Stop',
    'latitude': 37.7879,
    'longitude': -122.4075,
    'shortDescription': 'A Union Square stop.',
    'narration': sponsoredDisclosure == null
        ? 'Rover editorial narration.'
        : 'This sponsored stop is not Rover editorial content.',
    'category': sequence == 1 ? 'Landmark' : 'Sponsored',
    'contentType': contentType,
    'contentSource': contentSource,
    'sponsoredDisclosure': sponsoredDisclosure,
    'estimatedVisitMinutes': 6,
    'distanceFromPreviousStopMeters': sequence == 1 ? 0 : 100,
    'arrivalRadiusMeters': 25,
    'visited': visited,
    'arrivalState': visited ? 'Arrived' : 'Pending',
    'arrivedAtUtc': visited ? '2026-08-27T14:50:07.9945999+00:00' : null,
  };
}

class _FailedCancellationRepository extends FakeWalkRepository {
  final started = Completer<void>();
  final release = Completer<void>();
  @override
  Future<LocationUpdateResult> updateLocation(
    String id,
    LocationUpdateRequest request,
  ) async {
    final result = await super.updateLocation(id, request);
    started.complete();
    await release.future;
    return result;
  }

  @override
  Future<WalkSession> cancelWalk(String id) async =>
      throw StateError('Offline');
}

class _DelayedLocationRepository extends FakeWalkRepository {
  final started = Completer<void>();
  final release = Completer<void>();
  @override
  Future<LocationUpdateResult> updateLocation(
    String id,
    LocationUpdateRequest request,
  ) async {
    if (!started.isCompleted) {
      started.complete();
      await release.future;
    }
    return super.updateLocation(id, request);
  }
}

class FakeWalkRepository implements WalkRepository {
  FakeWalkRepository({this.delay = Duration.zero, this.offRoute = false});

  final Duration delay;
  final bool offRoute;
  final calls = <String>[];
  int visited = 0;
  WalkStatus status = WalkStatus.ready;

  @override
  Future<GuestProfile> createOrGetGuestProfile(String installationId) {
    throw UnimplementedError();
  }

  @override
  Future<GuestProfile> updateProfilePreferences(
    String profileId,
    UpdateProfilePreferencesRequest request,
  ) {
    throw UnimplementedError();
  }

  @override
  Future<GuestProfile> saveDiscovery(
    String profileId,
    SaveDiscoveryRequest request,
  ) {
    throw UnimplementedError();
  }

  @override
  Future<void> recordStoryInteraction(
    String profileId,
    StoryInteractionRequest request,
  ) async {}

  @override
  Future<void> deleteProfile(String profileId) {
    throw UnimplementedError();
  }

  @override
  Future<RenderedSpeechAudio> renderSpeech(RenderSpeechRequest request) {
    throw UnimplementedError();
  }

  @override
  Future<Map<String, dynamic>> getHealth() async {
    calls.add('getHealth');
    return {'status': 'Healthy'};
  }

  @override
  Future<WalkSession> createWalk(CreateWalkRequest request) async {
    calls.add('createWalk');
    await _wait();
    status = WalkStatus.ready;
    visited = 0;
    return WalkSession.fromJson(_walkJson());
  }

  @override
  Future<WalkSession> getWalk(String walkSessionId) async {
    calls.add('getWalk');
    return WalkSession.fromJson(
      _walkJson(status: _statusName(), visited: visited),
    );
  }

  @override
  Future<List<WalkStop>> getStops(String walkSessionId) async {
    calls.add('getStops');
    return WalkSession.fromJson(_walkJson()).stops;
  }

  @override
  Future<WalkStop?> getNextStop(String walkSessionId) async {
    calls.add('getNextStop');
    return WalkSession.fromJson(_walkJson(visited: visited)).nextStop;
  }

  @override
  Future<WalkSession> startWalk(String walkSessionId) async {
    calls.add('startWalk');
    status = WalkStatus.inProgress;
    return WalkSession.fromJson(_walkJson(status: 'InProgress'));
  }

  @override
  Future<WalkSession> arriveAtStop(
    String walkSessionId,
    String stopId, {
    double? latitude,
    double? longitude,
  }) async {
    calls.add('arriveAtStop:$stopId');
    visited++;
    return WalkSession.fromJson(
      _walkJson(status: 'InProgress', visited: visited),
    );
  }

  @override
  Future<LocationUpdateResult> updateLocation(
    String walkSessionId,
    LocationUpdateRequest request,
  ) async {
    calls.add('updateLocation');
    return LocationUpdateResult.fromJson({
      'walkSessionId': walkSessionId,
      'status': _statusName(),
      'accepted': true,
      'nextStop': _stopJson('union-square-plaza', 1),
      'distanceToNextStopMeters': 8,
      'routeProgressPercentage': 10,
      'estimatedMinutesRemaining': 16,
      'isOffRoute': offRoute,
      'distanceFromRouteMeters': offRoute ? 120 : 2,
      'arrivalCandidate': true,
      'arrivalCandidateReadingCount': 1,
      'confirmedArrival': null,
      'serverTimestampUtc': '2026-08-27T15:00:01Z',
    });
  }

  @override
  Future<AskRoverResponse> askRover(
    String walkSessionId,
    AskRoverRequest request,
  ) async {
    calls.add('askRover');
    return AskRoverResponse.fromJson({
      'conversationId': request.conversationId ?? 'conv-test',
      'turnId': 'turn-test',
      'answerText': 'Mock answer for ${request.questionText}',
      'createdAtUtc': '2026-08-27T15:00:02Z',
      'currentStopId': request.currentStopId,
      'provider': 'Mock',
      'suggestedAction': 'Informational',
      'safetyNotice': 'Stay aware.',
    });
  }

  @override
  Future<JourneyNarrationDecision> evaluateJourneyNarration(
    String walkSessionId,
    JourneyNarrationEvaluateRequest request,
  ) async {
    calls.add('evaluateJourneyNarration');
    return JourneyNarrationDecision.fromJson({
      'shouldNarrate': false,
      'kind': 'QuietWalk',
      'priority': 'ContextualStory',
      'narrationText': null,
      'placeId': null,
      'factIdsUsed': <String>[],
      'sourceReferences': <Map<String, dynamic>>[],
      'cooldownSeconds': 90,
      'warnings': <String>['No verified fact.'],
    });
  }

  @override
  Future<LocationStoryResponse> createLocationStory(
    LocationStoryRequest request,
  ) async {
    calls.add('createLocationStory');
    return LocationStoryResponse.fromJson({
      'storyTitle': 'Nearby story',
      'shortSpokenNarration': 'A short verified nearby story.',
      'tellMeMore': null,
      'placeId': 'test-place',
      'factIdsUsed': <String>['test-fact'],
      'sourceReferences': <Map<String, dynamic>>[
        {
          'providerName': 'Test',
          'attribution': 'Test data',
          'sourceUrl': null,
          'license': 'Test',
        },
      ],
      'confidence': 0.8,
      'requiredAttribution': <String>['Test data'],
      'warnings': <String>[],
    });
  }

  @override
  Future<LocationObservationResolution> resolveLocationObservation(
    LocationObservationResolveRequest request,
  ) {
    calls.add('resolveLocationObservation');
    return Future.value(
      const LocationObservationResolution(
        status: LocationObservationResolutionStatus.unresolved,
        candidates: [],
        diagnosticCode: 'observation_unresolved',
        warnings: [],
      ),
    );
  }

  @override
  Future<LocationStoryContext> getLocationContext({
    required double latitude,
    required double longitude,
    required int radiusMeters,
    String? routeId,
  }) async {
    calls.add('getLocationContext');
    return LocationStoryContext.fromJson({
      'rankedPlaces': <Map<String, dynamic>>[],
      'sourceWarnings': <String>[],
      'providerStatus': <Map<String, dynamic>>[],
    });
  }

  @override
  Future<LocalDiscoveryOptionsResult> getLocalDiscoveryOptions({
    required double latitude,
    required double longitude,
  }) async {
    calls.add('getLocalDiscoveryOptions');
    return LocalDiscoveryOptionsResult.fromJson({
      'provider': 'Fake',
      'radiusDegrees': 0.01,
      'maximumDistanceMeters': 1000,
      'discoveryError': null,
      'options': <Map<String, dynamic>>[],
    });
  }

  @override
  Future<WalkAdaptationProposal> evaluateAdaptation(
    String walkSessionId,
    WalkAdaptationEvaluateRequest request,
  ) async {
    calls.add('evaluateAdaptation:${request.requestedType}');
    return WalkAdaptationProposal.fromJson({
      'adaptationId': 'adapt-1',
      'walkSessionId': walkSessionId,
      'type': request.requestedType ?? 'ContinueUnchanged',
      'title': 'Add nearby coffee',
      'explanation': 'A short nearby discovery.',
      'estimatedAddedMinutes': 8,
      'estimatedAddedDistanceMeters': 120,
      'estimatedNewTotalMinutes': 26,
      'affectedStops': ['discovery-coffee-maiden-lane'],
      'addedStops': ['discovery-coffee-maiden-lane'],
      'removedStops': <String>[],
      'reorderedStops': ['union-square-plaza', 'discovery-coffee-maiden-lane'],
      'proposedRoute': _routeJson(),
      'proposedStops': [_stopJson('discovery-coffee-maiden-lane', 2)],
      'routeRevision': request.routeRevision,
      'proposedRouteRevision': request.routeRevision + 1,
      'createdAtUtc': '2026-08-27T15:00:03Z',
      'expiresAtUtc': request.requestedType == 'FollowDirection'
          ? DateTime.now()
                .toUtc()
                .add(const Duration(minutes: 10))
                .toIso8601String()
          : '2026-08-27T15:10:03Z',
      'status': 'Proposed',
    });
  }

  @override
  Future<WalkSession> acceptAdaptation(
    String walkSessionId,
    String adaptationId,
    int routeRevision,
  ) async {
    calls.add('acceptAdaptation:$adaptationId');
    return WalkSession.fromJson(
      _walkJson(status: 'InProgress', visited: visited),
    );
  }

  @override
  Future<WalkAdaptationProposal> rejectAdaptation(
    String walkSessionId,
    String adaptationId,
  ) async {
    calls.add('rejectAdaptation:$adaptationId');
    return WalkAdaptationProposal.fromJson({
      'adaptationId': adaptationId,
      'walkSessionId': walkSessionId,
      'type': 'AddDiscovery',
      'title': 'Rejected',
      'explanation': 'Rejected',
      'estimatedAddedMinutes': 0,
      'estimatedAddedDistanceMeters': 0,
      'estimatedNewTotalMinutes': 18,
      'affectedStops': <String>[],
      'addedStops': <String>[],
      'removedStops': <String>[],
      'reorderedStops': <String>[],
      'proposedRoute': _routeJson(),
      'proposedStops': <Map<String, dynamic>>[],
      'routeRevision': 1,
      'proposedRouteRevision': 2,
      'createdAtUtc': '2026-08-27T15:00:03Z',
      'expiresAtUtc': '2026-08-27T15:10:03Z',
      'status': 'Rejected',
    });
  }

  @override
  Future<WalkSession> completeWalk(String walkSessionId) async {
    calls.add('completeWalk');
    status = WalkStatus.completed;
    return WalkSession.fromJson(_walkJson(status: 'Completed', visited: 2));
  }

  @override
  Future<WalkSession> cancelWalk(String walkSessionId) async {
    calls.add('cancelWalk');
    if (status == WalkStatus.completed) {
      throw const RoverApiException(
        'Completed and Cancelled walks cannot be changed.',
      );
    }
    status = WalkStatus.cancelled;
    return WalkSession.fromJson(
      _walkJson(status: 'Cancelled', visited: visited),
    );
  }

  Future<void> _wait() async {
    if (delay > Duration.zero) {
      await Future<void>.delayed(delay);
    }
  }

  String _statusName() {
    return switch (status) {
      WalkStatus.ready => 'Ready',
      WalkStatus.inProgress => 'InProgress',
      WalkStatus.completed => 'Completed',
      WalkStatus.cancelled => 'Cancelled',
      WalkStatus.created => 'Created',
      WalkStatus.unknown => 'Unknown',
    };
  }
}
