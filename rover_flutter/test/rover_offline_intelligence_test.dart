import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rover/src/api/location_observation_models.dart';
import 'package:rover/src/api/location_story_models.dart';
import 'package:rover/src/api/problem_details.dart';
import 'package:rover/src/api/rover_api_client.dart';
import 'package:rover/src/api/walk_repository.dart';
import 'package:rover/src/location/rover_location.dart';
import 'package:rover/src/on_device_ai/rover_offline_intelligence.dart';
import 'package:rover/src/on_device_ai/rover_scout.dart';

void main() {
  final now = DateTime.utc(2026, 9, 2, 12);
  late Directory directory;
  late RoverOfflineIntelligence intelligence;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('rover-offline-test-');
    intelligence = RoverOfflineIntelligence(
      cacheFile: File('${directory.path}${Platform.pathSeparator}cache.json'),
      nowUtc: () => now,
    )..configure(enabled: true);
  });

  tearDown(() async {
    await directory.delete(recursive: true);
  });

  test('stores only durable claims and labels offline playback', () async {
    await intelligence.store(_request(), _response(now));

    final cached = await intelligence.findStory(_request());

    expect(cached, isNotNull);
    expect(cached!.offlineCached, isTrue);
    expect(
      cached.shortSpokenNarration,
      startsWith('From your offline stories'),
    );
    expect(cached.shortSpokenNarration, contains('built in 1894'));
    expect(cached.shortSpokenNarration, isNot(contains('open today')));
    expect(cached.tellMeMore, isNot(contains('meters away')));
    expect(cached.factIdsUsed, ['history-1']);
    expect(intelligence.cacheState, RoverOfflineCacheState.available);
  });

  test('rejects Google-sourced and expired Story Packs', () async {
    await intelligence.store(
      _request(),
      _response(now, providerName: 'Google Places'),
    );
    await intelligence.store(
      _request(placeId: 'expired'),
      _response(
        now,
        placeId: 'expired',
        expiresUtc: now.subtract(const Duration(minutes: 1)),
      ),
    );

    expect(intelligence.snapshot.entryCount, 0);
    expect(intelligence.cacheState, RoverOfflineCacheState.unavailable);
  });

  test('rejects Story Pack 2.0 when retention forbids offline use', () async {
    await intelligence.store(
      _request(),
      _response(now, schemaVersion: '2.0', offlineEligible: false),
    );

    expect(intelligence.snapshot.entryCount, 0);
    expect(intelligence.cacheState, RoverOfflineCacheState.unavailable);
  });

  test('rejects live retention and sanitizes mixed Story Packs', () async {
    await intelligence.store(
      _request(placeId: 'live'),
      _response(
        now,
        placeId: 'live',
        schemaVersion: '2.0',
        retentionClass: 'live',
      ),
    );
    await intelligence.store(
      _request(placeId: 'mixed'),
      _response(
        now,
        placeId: 'mixed',
        schemaVersion: '2.0',
        retentionClass: 'mixed',
      ),
    );

    expect(intelligence.snapshot.entryCount, 1);
    final cached = await intelligence.findStory(_request(placeId: 'mixed'));
    expect(cached?.shortSpokenNarration, contains('built in 1894'));
    expect(cached?.shortSpokenNarration, isNot(contains('open today')));
    expect(cached?.storyPackV2?.cacheEligibility?.retentionClass, 'evergreen');
  });

  test(
    'supplies nearby Camera context and OCR name matching offline',
    () async {
      await intelligence.store(_request(), _response(now));

      final context = await intelligence.findContext(
        location: const RoverLatLng(latitude: 44.678, longitude: -76.395),
        radiusMeters: 500,
      );
      final resolution = await intelligence.resolveObservation(
        const LocationObservationResolveRequest(
          recognizedText: 'Welcome to Sample Museum',
          location: RoverLatLng(latitude: 44.678, longitude: -76.395),
          radiusMeters: 500,
          nearbyPlaceIds: [],
        ),
      );

      expect(context, isNotNull);
      expect(
        context!.sourceWarnings.single,
        startsWith('Offline cached match.'),
      );
      expect(context.rankedPlaces.single.name, 'Sample Museum');
      expect(resolution?.status, LocationObservationResolutionStatus.verified);
      expect(resolution?.diagnosticCode, 'offline_cached_match');
    },
  );

  test('HTTP repository falls back only for connectivity failures', () async {
    await intelligence.store(_request(), _response(now));
    final repository = HttpWalkRepository(
      client: _OfflineClient(),
      offlineIntelligence: intelligence,
    );

    final response = await repository.createLocationStory(_request());

    expect(response.offlineCached, isTrue);
    expect(intelligence.connectivityState, RoverConnectivityState.offline);
  });

  test('reloads a fresh Story Pack from device storage', () async {
    await intelligence.store(_request(), _response(now));
    final reloaded = RoverOfflineIntelligence(
      cacheFile: File('${directory.path}${Platform.pathSeparator}cache.json'),
      nowUtc: () => now.add(const Duration(hours: 1)),
    )..configure(enabled: true);

    final cached = await reloaded.findStory(_request());

    expect(cached?.offlineCached, isTrue);
    expect(reloaded.snapshot.entryCount, 1);
  });

  test('clear removes cached personal data from disk', () async {
    await intelligence.store(_request(), _response(now));
    expect(intelligence.snapshot.entryCount, 1);

    await intelligence.clear();

    expect(intelligence.snapshot.entryCount, 0);
    expect(
      await File('${directory.path}${Platform.pathSeparator}cache.json')
          .exists(),
      isFalse,
    );
  });
}

LocationStoryRequest _request({String placeId = 'sample-museum'}) {
  return LocationStoryRequest(
    location: const RoverLatLng(latitude: 44.678, longitude: -76.395),
    radiusMeters: 150,
    routeGeometry: const [],
    interests: const ['History'],
    selectedPlaceIds: [placeId],
  );
}

LocationStoryResponse _response(
  DateTime now, {
  String placeId = 'sample-museum',
  String providerName = 'Local archive',
  DateTime? expiresUtc,
  String schemaVersion = '1.1',
  bool offlineEligible = true,
  String? retentionClass,
}) {
  final expiry = expiresUtc ?? now.add(const Duration(days: 7));
  return LocationStoryResponse.fromJson({
    'storyTitle': 'Sample Museum',
    'shortSpokenNarration':
        'Server narration is replaced by grounded sections.',
    'tellMeMore': 'Server detail.',
    'placeId': placeId,
    'factIdsUsed': ['history-1', 'hours-1', 'relative-1'],
    'sourceReferences': const [],
    'confidence': 0.91,
    'requiredAttribution': [providerName],
    'warnings': const [],
    'storyPack': {
      'schemaVersion': schemaVersion,
      if (schemaVersion == '2.0')
        'cacheEligibility': {
          'offlineEligible': offlineEligible,
          'audioCacheEligible': offlineEligible,
          'retentionClass':
              retentionClass ?? (offlineEligible ? 'evergreen' : 'restricted'),
          'reason': 'Test retention policy.',
        },
      'profile': 'HistoryEnthusiast',
      'placeIdentity': {
        'canonicalPlaceId': placeId,
        'name': 'Sample Museum',
        'latitude': 44.678,
        'longitude': -76.395,
        'address': '1 Main Street',
        'categories': ['Museum'],
        'verifiedUtc': now.toIso8601String(),
      },
      'sections': [
        {
          'sectionType': 'Arrival',
          'sentences': [
            {
              'sentenceId': 'sentence-history',
              'text': 'Sample Museum was built in 1894.',
              'contentType': 'Fact',
              'evidenceIds': ['history-1'],
              'confidence': 0.94,
            },
            {
              'sentenceId': 'sentence-hours',
              'text': 'It is open today until five.',
              'contentType': 'Fact',
              'evidenceIds': ['hours-1'],
              'confidence': 0.8,
            },
          ],
        },
        {
          'sectionType': 'Deeper',
          'sentences': [
            {
              'sentenceId': 'sentence-relative',
              'text': 'It is 20 meters away.',
              'contentType': 'Fact',
              'evidenceIds': ['relative-1'],
              'confidence': 0.9,
            },
          ],
        },
      ],
      'evidenceClaims': [
        {
          'evidenceId': 'history-1',
          'claimType': 'HistoricalFact',
          'category': 'history',
          'text': 'The building dates to 1894.',
          'sourceIds': ['source-1'],
          'verificationStatus': 'Verified',
          'confidence': 0.94,
          'retrievedUtc': now.toIso8601String(),
          'expiresUtc': expiry.toIso8601String(),
        },
        {
          'evidenceId': 'hours-1',
          'claimType': 'BusinessHours',
          'category': 'opening_hours',
          'text': 'Open today until five.',
          'sourceIds': ['source-1'],
          'verificationStatus': 'Verified',
          'confidence': 0.8,
          'retrievedUtc': now.toIso8601String(),
          'expiresUtc': expiry.toIso8601String(),
        },
        {
          'evidenceId': 'relative-1',
          'claimType': 'RelativeLocation',
          'category': 'relative_location',
          'text': '20 meters away.',
          'sourceIds': ['source-1'],
          'verificationStatus': 'Verified',
          'confidence': 0.9,
          'retrievedUtc': now.toIso8601String(),
          'expiresUtc': expiry.toIso8601String(),
        },
      ],
      'sources': [
        {
          'sourceId': 'source-1',
          'providerName': providerName,
          'sourceTitle': 'Town archive',
          'sourceUrl': 'https://example.test/archive',
          'attribution': providerName,
          'license': 'CC BY 4.0',
          'retrievedUtc': now.toIso8601String(),
          'expiresUtc': expiry.toIso8601String(),
          'confidence': 0.95,
        },
      ],
      'generatedUtc': now.toIso8601String(),
      'lastVerifiedUtc': now.toIso8601String(),
      'expiresUtc': expiry.toIso8601String(),
      'validation': {
        'isValid': true,
        'status': 'Valid',
        'validatedUtc': now.toIso8601String(),
        'issues': const [],
      },
    },
  });
}

class _OfflineClient extends RoverApiClient {
  @override
  Future<LocationStoryResponse> createLocationStory(
    LocationStoryRequest request,
  ) {
    throw const RoverApiConnectionException('offline');
  }
}
