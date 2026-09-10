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
    intent: 'HiddenHistory',
    category: 'history',
    latitude: 44.6,
    longitude: -76.3,
    opensAtRouteMeters: 100,
    closesAtRouteMeters: 300,
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
