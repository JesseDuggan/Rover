import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rover/src/adaptive_stories/adaptive_route_story_device_cache.dart';
import 'package:rover/src/api/adaptive_route_story_models.dart';

void main() {
  late Directory directory;
  late File file;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('rover-phase16-cache-');
    file = File('${directory.path}${Platform.pathSeparator}cache.json');
  });

  tearDown(() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  test('eligible route pack survives restart and selects locally', () async {
    final cache = AdaptiveRouteStoryDeviceCache(file: file);
    final state = _state(provider: 'Wikipedia');

    expect(await cache.store(state), isTrue);
    final reloaded = AdaptiveRouteStoryDeviceCache(file: file);
    final selected = await reloaded.select(
      'walk-1',
      3,
      const NextRouteStoryRequest(routeProgressMeters: 120),
    );

    expect(reloaded.packCount, 1);
    expect(selected?.story.storyId, 'story-1');
    expect(selected?.variant.length, 'Standard');
  });

  test('Google-sourced route packs are never persisted', () async {
    final cache = AdaptiveRouteStoryDeviceCache(file: file);

    expect(await cache.store(_state(provider: 'Google Maps')), isFalse);
    expect(await file.exists(), isFalse);
    expect(cache.packCount, 0);
  });

  test(
    'collection duration round trips but excludes filtered online coverage',
    () async {
      final original = _state(provider: 'Wikipedia');
      final pack = AdaptiveRouteStoryPack.fromJson({
        ...original.pack!.toJson(),
        'collection': {
          'title': 'Stories along your walk',
          'narrationSeconds': 60,
          'walkingSeconds': 1200,
          'uncoveredSegmentIds': ['segment-2'],
        },
      });
      expect(
        AdaptiveRouteStoryPack.fromJson(pack.toJson())
            .collection!
            .narrationSeconds,
        60,
      );
      expect(pack.collection!.uncoveredSegmentIds, ['segment-2']);
      expect(original.pack!.collection, isNull);
      final online = _state(provider: 'OnlineResearch').pack!.stories.single;
      final mixed = AdaptiveRouteStoryPackState.fromJson({
        ...original.toJson(),
        'pack': {
          ...pack.toJson(),
          'stories': [
            pack.stories.single.toJson(),
            {...online.toJson(), 'storyId': 'online'},
          ],
        },
      });
      final cache = AdaptiveRouteStoryDeviceCache(file: file);
      await cache.store(mixed);
      expect((await cache.get('walk-1', 3))!.pack!.collection, isNull);
    },
  );

  test(
    'online research is excluded without losing downloadable stories',
    () async {
      final cache = AdaptiveRouteStoryDeviceCache(file: file);
      final wiki = _state(provider: 'Wikipedia');
      final research = _state(provider: 'OnlineResearch').pack!.stories.first
          .toJson();
      final mixed = AdaptiveRouteStoryPackState.fromJson({
        ...wiki.toJson(),
        'pack': {
          ...wiki.pack!.toJson(),
          'stories': [
            wiki.pack!.stories.first.toJson(),
            {...research, 'storyId': 'research-only'},
          ],
        },
      });
      expect(await cache.store(mixed), isTrue);
      final stored = await cache.get('walk-1', 3);
      expect(stored!.pack!.stories.map((story) => story.storyId), ['story-1']);
      expect(await file.readAsString(), isNot(contains('research-only')));
      final source = RouteStorySource.fromJson({
        'providerName': 'Museum',
        'allowsOfflineUse': false,
      });
      expect(source.canCache, isFalse);
      expect(
        RouteStorySource.fromJson(source.toJson()).allowsOfflineUse,
        isFalse,
      );
    },
  );

  test(
    'missed history catches up without ignoring navigation or distance',
    () async {
      final cache = AdaptiveRouteStoryDeviceCache(file: file);
      await cache.store(_state(provider: 'Wikipedia'));
      expect(
        await cache.select(
          'walk-1',
          3,
          const NextRouteStoryRequest(routeProgressMeters: 400),
        ),
        isNotNull,
      );
      expect(
        await cache.select(
          'walk-1',
          3,
          const NextRouteStoryRequest(routeProgressMeters: 601),
        ),
        isNull,
      );
      expect(
        await cache.select(
          'walk-1',
          3,
          const NextRouteStoryRequest(
            routeProgressMeters: 400,
            secondsUntilNextManeuver: 10,
          ),
        ),
        isNull,
      );
    },
  );

  test(
    'history plays on approach with bounded distance and navigation time',
    () async {
      final cache = AdaptiveRouteStoryDeviceCache(file: file);
      for (final intent in [
        'HiddenHistory',
        'StreetHistory',
        'NeighbourhoodHistory',
        'CityHistory',
        'GeneralLocationQuestion',
      ]) {
        await cache.store(
          _state(provider: 'Wikipedia', intent: intent, opens: 600),
        );
        final selected = await cache.select(
          'walk-1',
          3,
          const NextRouteStoryRequest(
            routeProgressMeters: 300,
            secondsUntilNextManeuver: 75,
          ),
        );
        expect(selected != null, intent != 'GeneralLocationQuestion');
        for (final request in const [
          NextRouteStoryRequest(routeProgressMeters: 299),
          NextRouteStoryRequest(
            routeProgressMeters: 300,
            secondsUntilNextManeuver: 74,
          ),
          NextRouteStoryRequest(
            routeProgressMeters: 300,
            excludedStoryIds: ['story-1'],
          ),
        ]) {
          expect(await cache.select('walk-1', 3, request), isNull);
        }
      }
      expect(
        _state(provider: 'Wikipedia').pack!.stories.single.playbackWindowStart,
        0,
      );
    },
  );

  test('expired story is not selected from a still-valid pack', () async {
    final cache = AdaptiveRouteStoryDeviceCache(file: file);
    final state = _state(
      provider: 'Wikipedia',
      storyExpiry: DateTime.now().toUtc().subtract(const Duration(minutes: 1)),
    );
    expect(await cache.store(state), isTrue);
    expect(
      await cache.select(
        'walk-1',
        3,
        const NextRouteStoryRequest(routeProgressMeters: 120),
      ),
      isNull,
    );
  });

  test('offline events survive restart and flush in order', () async {
    final cache = AdaptiveRouteStoryDeviceCache(file: file);
    final first = RouteStoryPlaybackEventRequest(
      storyId: 'story-1',
      kind: 'Started',
      occurredUtc: DateTime.utc(2026, 9, 7, 12),
    );
    final second = RouteStoryPlaybackEventRequest(
      storyId: 'story-1',
      kind: 'Completed',
      occurredUtc: DateTime.utc(2026, 9, 7, 12, 1),
    );
    await cache.applyEvent('walk-1', 3, first, queueForSync: true);
    await cache.applyEvent('walk-1', 3, second, queueForSync: true);

    final reloaded = AdaptiveRouteStoryDeviceCache(file: file);
    final kinds = <String>[];
    await reloaded.flushEvents((event) async {
      kinds.add(event.request.kind);
    });

    expect(kinds, ['Started', 'Completed']);
    expect(reloaded.queuedEventCount, 0);
  });

  test('successful prefix is removed when a later event fails', () async {
    final cache = AdaptiveRouteStoryDeviceCache(file: file);
    for (final kind in ['Started', 'Completed']) {
      await cache.applyEvent(
        'walk-1',
        3,
        RouteStoryPlaybackEventRequest(
          storyId: 'story-1',
          kind: kind,
          occurredUtc: DateTime.utc(2026, 9, 7, 12),
        ),
        queueForSync: true,
      );
    }
    var calls = 0;

    await expectLater(
      cache.flushEvents((event) async {
        calls++;
        if (calls == 2) throw StateError('offline again');
      }),
      throwsStateError,
    );

    expect(cache.queuedEventCount, 1);
  });
}

AdaptiveRouteStoryPackState _state({
  required String provider,
  DateTime? storyExpiry,
  String intent = 'HiddenHistory',
  double opens = 100,
}) {
  final now = DateTime.now().toUtc();
  final source = RouteStorySource(
    sourceId: 'source-1',
    providerName: provider,
    attribution: provider,
    retrievedUtc: now,
    confidence: 0.9,
  );
  final story = AdaptiveRouteStory(
    storyId: 'story-1',
    segmentId: 'segment-1',
    placeId: 'place-1',
    title: 'A local story',
    intent: intent,
    category: 'history',
    latitude: 44.6,
    longitude: -76.3,
    opensAtRouteMeters: opens,
    closesAtRouteMeters: opens + 200,
    variants: const [
      RouteStoryNarrationVariant(
        length: 'Standard',
        estimatedDurationSeconds: 60,
        narration: 'A grounded local story.',
        claimIds: ['claim-1'],
      ),
    ],
    claims: const [
      RouteStoryClaim(
        claimId: 'claim-1',
        text: 'A grounded local story.',
        sourceIds: ['source-1'],
        confidence: 0.9,
      ),
    ],
    sources: [source],
    evidenceScore: 0.9,
    expiresUtc: storyExpiry,
  );
  return AdaptiveRouteStoryPackState(
    walkSessionId: 'walk-1',
    routeRevision: 3,
    status: 'Ready',
    updatedUtc: now,
    heardStoryIds: const [],
    savedStoryIds: const [],
    pack: AdaptiveRouteStoryPack(
      schemaVersion: '3.0',
      packId: 'pack-1',
      idempotencyKey: 'key-1',
      walkSessionId: 'walk-1',
      routeId: 'route-1',
      routeRevision: 3,
      promptVersion: 'phase16-test',
      generatedUtc: now,
      expiresUtc: now.add(const Duration(days: 2)),
      stories: [story],
      warnings: const [],
    ),
  );
}
