import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rover/src/api/adaptive_route_story_models.dart';
import 'package:rover/src/just_walking/area_walking_controller.dart';
import 'package:rover/src/just_walking/area_story_details.dart';
import 'package:rover/src/location/rover_location.dart';
import 'package:rover/src/voice/rover_voice_controller.dart';

import 'voice_controller_test.dart'
    show
        FakeTextToSpeech,
        FakeSpeechRecognizer,
        FakeAudioSession,
        FakeVoiceWalkRepository;

AdaptiveRouteStory story(String id, DateTime now) =>
    AdaptiveRouteStory.fromJson({
      'storyId': id,
      'audienceSuitability': 'family',
      'title': 'Area history $id',
      'anchor': {'latitude': 52.373, 'longitude': 4.883},
      'expiresUtc': now.add(const Duration(hours: 6)).toIso8601String(),
      'variants': [
        {
          'length': 'Standard',
          'estimatedDurationSeconds': 60,
          'narration': 'A detailed account of this neighbourhood.',
          'claimIds': ['fact'],
        },
      ],
      'claims': [
        {
          'claimId': 'fact',
          'text': 'A sourced fact.',
          'sourceIds': ['source'],
        },
      ],
      'sources': [
        {
          'sourceId': 'source',
          'providerName': 'City archive',
          'title': 'Local history',
          'url': 'https://example.org/history',
        },
      ],
    });

void main() {
  test('broader context survives cache JSON and plays near origin, not distant subject', () async {
    final now = DateTime.now().toUtc();
    final regional = AdaptiveRouteStory.fromJson({
      ...story('regional', now).toJson(),
      'geographicScope': 'region',
      'geographicArea': 'Test province',
      'anchor': {'latitude': 53.0, 'longitude': 5.2},
      'contextOrigin': {'latitude': 52.373, 'longitude': 4.883},
    });
    final restored = AdaptiveRouteStory.fromJson(regional.toJson());
    var plays = 0;
    final controller = AreaWalkingController(
      clock: () => now,
      cancelResearch: () {},
      research: (_, _) async => AreaStoryCollection('ready', [restored]),
      narrate: (_) async {
        plays++;
        return true;
      },
    );
    await controller.update(
      RoverLocationReading(
        location: const RoverLatLng(latitude: 52.373, longitude: 4.883),
        recordedAtUtc: now,
        accuracyMeters: 5,
      ),
    );
    expect(plays, 1);
    expect(restored.latitude, 53.0);
    expect(controller.coverageLabel(restored), 'region context: Test province');
    controller.reading = RoverLocationReading(
      location: const RoverLatLng(latitude: 53.0, longitude: 5.2),
      recordedAtUtc: now,
      accuracyMeters: 5,
    );
    expect(controller.available(restored), isFalse);
    controller.dispose();
  });
  test('area autoplay skips sensitive stories but explicit playback remains available', () async {
    final now = DateTime.now().toUtc();
    final sensitive = AdaptiveRouteStory.fromJson({
      ...story('sensitive', now).toJson(),
      'audienceSuitability': 'sensitive',
      'sensitivityNotice': 'Content note: wartime history.',
    });
    final played = <String>[];
    final controller = AreaWalkingController(
      clock: () => now,
      cancelResearch: () {},
      research: (_, _) async =>
          AreaStoryCollection('ready', [sensitive, story('family', now)]),
      narrate: (s) async {
        played.add(s.storyId);
        return true;
      },
    );
    await controller.update(
      RoverLocationReading(
        location: const RoverLatLng(latitude: 52.373, longitude: 4.883),
        recordedAtUtc: now,
        accuracyMeters: 8,
      ),
    );
    expect(played, ['family']);
    await controller.play(sensitive);
    expect(played, ['family', 'sensitive']);
    controller.dispose();
  });

  test(
    'sparse results widen in bounded stages and label regional stories',
    () async {
      var time = DateTime.utc(2026, 10, 4);
      late AreaWalkingController controller;
      final radii = <int>[];
      controller = AreaWalkingController(
        clock: () => time,
        cancelResearch: () {},
        research: (_, _) async {
          radii.add(controller.searchRadiusMeters);
          final radius = controller.searchRadiusMeters;
          final regional = story('region', time).toJson();
          regional['anchor'] = {'latitude': 52.4, 'longitude': 4.883};
          return AreaStoryCollection(
            'ready',
            radius == 20000 ? [AdaptiveRouteStory.fromJson(regional)] : [],
            searchRadiusMeters: radius,
          );
        },
        narrate: (_) async => true,
      );
      Future<void> tick() => controller.update(
        RoverLocationReading(
          location: const RoverLatLng(latitude: 52.373, longitude: 4.883),
          recordedAtUtc: time,
          accuracyMeters: 5,
        ),
      );
      await tick();
      expect(controller.coverageMessage, contains('5 km'));
      time = time.add(const Duration(seconds: 21));
      await tick();
      expect(controller.coverageMessage, contains('20 km'));
      time = time.add(const Duration(seconds: 21));
      await tick();
      expect(radii, [1000, 5000, 20000]);
      expect(
        controller.coverageLabel(controller.stories.single),
        contains('Regional context'),
      );
      expect(controller.heard, contains('region'));
      time = time.add(const Duration(seconds: 21));
      await tick();
      expect(radii.length, 3);
      controller.dispose();
    },
  );

  test(
    'provider failure does not claim sparse coverage or broaden search',
    () async {
      final time = DateTime.now().toUtc();
      final controller = AreaWalkingController(
        cancelResearch: () {},
        research: (_, _) async => const AreaStoryCollection('failed', []),
        narrate: (_) async => true,
      );
      await controller.update(
        RoverLocationReading(
          location: const RoverLatLng(latitude: 52.373, longitude: 4.883),
          recordedAtUtc: time,
          accuracyMeters: 5,
        ),
      );
      expect(controller.searchRadiusMeters, 1000);
      expect(controller.coverageMessage, isNull);
      controller.dispose();
    },
  );
  test(
    'area narration plays prepared text without another research request',
    () async {
      final tts = FakeTextToSpeech();
      final voice = RoverVoiceController(
        walkRepository: FakeVoiceWalkRepository(),
        textToSpeech: tts,
        speechRecognizer: FakeSpeechRecognizer(),
        audioSession: FakeAudioSession(),
      );
      expect(
        await voice.playAreaStory(story('voice', DateTime.now().toUtc())),
        isTrue,
      );
      expect(tts.spoken, contains('A detailed account of this neighbourhood.'));
      await voice.playAreaStory(
        story('regional', DateTime.now().toUtc()),
        regionalContext: true,
      );
      expect(
        tts.spoken.last,
        startsWith('This story comes from the surrounding region'),
      );
      voice.dispose();
    },
  );
  var now = DateTime.utc(2026, 10, 3);
  RoverLocationReading location({double lat = 52.373}) => RoverLocationReading(
    location: RoverLatLng(latitude: lat, longitude: 4.883),
    recordedAtUtc: now,
    accuracyMeters: 5,
  );

  test(
    'fresh area researches without places, then expands without repeating',
    () async {
      var calls = 0;
      final played = <String>[];
      final controller = AreaWalkingController(
        clock: () => now,
        cancelResearch: () {},
        research: (point, excluded) async {
          calls++;
          if (calls == 2) expect(excluded, contains('Area history first'));
          return AreaStoryCollection('ready', [
            story('first', now),
            if (calls > 1) story('second', now),
          ]);
        },
        narrate: (s) async {
          played.add(s.storyId);
          return true;
        },
      );
      await controller.update(location());
      expect(calls, 1);
      expect(played, ['first']);
      await controller.update(location(), refresh: true);
      expect(calls, 1);
      now = now.add(const Duration(minutes: 3));
      await controller.update(location(lat: 52.377));
      expect(calls, 2);
      expect(controller.stories.length, 2);
      expect(played, ['first', 'second']);
      controller.dispose();
    },
  );
  test('pause cancels research and rejects late collection', () async {
    final pending = Completer<AreaStoryCollection>();
    var cancelled = false;
    final controller = AreaWalkingController(
      clock: () => now,
      cancelResearch: () => cancelled = true,
      research: (_, _) => pending.future,
      narrate: (_) async => throw StateError('Must not play'),
    );
    final work = controller.update(location());
    controller.setPaused(true);
    pending.complete(AreaStoryCollection('ready', [story('late', now)]));
    await work;
    expect(cancelled, isTrue);
    expect(controller.stories, isEmpty);
    expect(controller.status, 'Paused');
    controller.dispose();
  });
  test('moving away during research prevents old-area audio', () async {
    final pending = Completer<AreaStoryCollection>();
    var plays = 0;
    final controller = AreaWalkingController(
      clock: () => now,
      cancelResearch: () {},
      research: (_, _) => pending.future,
      narrate: (_) async {
        plays++;
        return true;
      },
    );
    final work = controller.update(location());
    await controller.update(location(lat: 52.5));
    pending.complete(AreaStoryCollection('ready', [story('old', now)]));
    await work;
    expect(plays, 0);
    controller.dispose();
  });
  test('empty result is explicit and does not rapidly retry', () async {
    var calls = 0;
    final controller = AreaWalkingController(
      clock: () => now,
      cancelResearch: () {},
      research: (_, _) async {
        calls++;
        return const AreaStoryCollection('empty', []);
      },
      narrate: (_) async => false,
    );
    await controller.update(location());
    await controller.update(location());
    expect(controller.status, contains('No new verified'));
    expect(calls, 1);
    controller.dispose();
  });
  testWidgets('area story opens readable narration and source', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: AreaStoryDetails(story: story('read', now))),
      ),
    );
    expect(
      find.text('A detailed account of this neighbourhood.'),
      findsOneWidget,
    );
    expect(find.text('Local history'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
