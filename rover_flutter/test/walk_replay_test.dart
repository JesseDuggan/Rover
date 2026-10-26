import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rover/src/adventure/roam.dart';
import 'package:rover/src/api/adaptive_route_story_models.dart';
import 'package:rover/src/location/rover_location.dart';
import 'package:rover/src/memories/memory_store.dart';
import 'package:rover/src/memories/walk_replay.dart';
import 'package:rover/src/memories/walk_replay_screen.dart';
import 'package:rover/src/memories/walk_trail_store.dart';
import 'package:rover/src/voice/rover_audio_services.dart';

final start = DateTime.utc(2026, 10, 24, 12);
Map<String, dynamic> point(
  int seconds, {
  int segment = 0,
  String recording = 'one',
  double? lat,
}) => {
  'at': start.add(Duration(seconds: seconds)).toIso8601String(),
  'latitude': lat ?? 43 + seconds / 100000,
  'longitude': 7.0,
  'segment': segment,
  'recordingId': recording,
};
final journey = MemoryJourney(
  id: 'saved',
  route: RoverRoam(
    title: 'Nice',
    summary: 'Nice walk',
    walkingMinutes: 30,
    distanceMiles: 1,
    startingPoint: 'Nice',
    stops: const [],
    routeGeometry: const [],
    accessibilityNotes: const [],
    warnings: const [],
  ),
);
AdaptiveRouteStory story({double lat = 43.0001}) =>
    AdaptiveRouteStory.fromJson({
      'storyId': 'story',
      'title': 'History of Nice',
      'anchor': {'latitude': lat, 'longitude': 7},
      'variants': [
        {'length': 'Standard', 'narration': 'A saved story.'},
      ],
    });

void main() {
  for (final size in [const Size(320, 640), const Size(844, 390)]) {
    testWidgets('Replay controls fit $size with recording sections', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: WalkReplayScreen(
            journey: journey,
            stories: [story()],
            memoryStore: FakeMemories(),
            trailStore: FakeTrail([point(0), point(10), point(20, segment: 1)]),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byTooltip('Play replay'), findsOneWidget);
    });
  }
  test('Interpolation follows recorded fixes, not planned geometry', () {
    final segment = replaySegments([point(0), point(10)]).single;
    expect(segment.duration, 10);
    expect(segment.position(5).latitude, closeTo(43.00005, 0.000001));
    expect(segment.position(100).latitude, 43.0001);
    expect(segment.position(-1).latitude, 43);
  });
  test(
    'Recording sessions, explicit pauses and missing GPS remain separate',
    () {
      final segments = replaySegments([
        point(0),
        point(10),
        point(20, segment: 1),
        point(100, segment: 1),
        point(110, recording: 'two'),
      ]);
      expect(segments, hasLength(4));
      expect(segments.first.fixes, hasLength(2));
    },
  );
  test('Invalid fixes, backward time and impossible jumps break the line', () {
    expect(
      replaySegments([
        point(0),
        {'at': 'bad'},
        point(10),
      ]),
      hasLength(2),
    );
    expect(replaySegments([point(10), point(0)]), hasLength(2));
    expect(replaySegments([point(0), point(10, lat: 50)]), hasLength(2));
    expect(replaySegments([point(0, lat: double.nan)]), isEmpty);
  });
  test('Memories match capture time and place; private memories remain viewable by owner', () {
    final segment = replaySegments([point(0), point(10)]).single;
    WalkMemory memory(int seconds, double lat) => WalkMemory(
      File('$seconds.jpg'),
      details: MemoryDetails(
        capturedAt: start.add(Duration(seconds: seconds)),
        location: RoverLatLng(latitude: lat, longitude: 7),
        sharingLocked: true,
      ),
    );
    final events = replayEvents(segment, [
      memory(5, 43.00005),
      memory(5, 50),
      memory(3600, 43),
    ], []);
    expect(events, hasLength(1));
    expect(events.single.seconds, 5);
    expect(events.single.memory!.details.sharingLocked, isTrue);
  });
  test('Stories outside recorded path are not inserted into replay', () {
    final segment = replaySegments([point(0), point(10)]).single;
    expect(replayEvents(segment, [], [story(), story(lat: 50)]), hasLength(1));
  });
  test('Camera-gap memory appears once without filling the GPS gap', () {
    final sections = replaySegments([
      point(0),
      point(10),
      point(50, segment: 1),
      point(60, segment: 1),
    ]);
    final memory = WalkMemory(
      File('camera.jpg'),
      details: MemoryDetails(
        capturedAt: start.add(const Duration(seconds: 20)),
        location: const RoverLatLng(latitude: 43.0002, longitude: 7),
      ),
    );
    final first = replayEvents(
      sections.first,
      [memory],
      [],
      sections: sections,
    );
    final second = replayEvents(
      sections.last,
      [memory],
      [],
      sections: sections,
    );
    expect(first.single.seconds, 10);
    expect(second, isEmpty);
    expect(sections.first.fixes, hasLength(2));
    expect(sections.last.fixes, hasLength(2));
  });
  test(
    'Journey lookup includes resumed sessions but excludes other walks',
    () async {
      final root = await Directory.systemTemp.createTemp('replay-lookup');
      addTearDown(() => root.delete(recursive: true));
      final memories = MemoryStore(
        directory: Directory('${root.path}/memories'),
      );
      await memories.linkSession('resumed', 'saved');
      final store = WalkTrailStore(
        directory: Directory('${root.path}/trails'),
        memoryStore: memories,
        now: () => start,
      );
      for (final id in ['saved', 'resumed', 'other']) {
        await store.record(
          id,
          RoverLocationReading(
            location: const RoverLatLng(latitude: 43, longitude: 7),
            recordedAtUtc: start,
            accuracyMeters: 5,
          ),
        );
      }
      await store.close();
      final rows = await store.readJourney('saved');
      expect(rows, hasLength(2));
      expect(rows.map((p) => p['recordingId']).toSet(), {'saved', 'resumed'});
      expect(replaySegments(rows), hasLength(2));
    },
  );
  testWidgets(
    'No recorded GPS is labelled planned preview, without play control',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: WalkReplayScreen(
            journey: journey,
            memoryStore: FakeMemories(),
            trailStore: FakeTrail([]),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Planned-route preview'), findsOneWidget);
      expect(find.byTooltip('Play replay'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('Replay progresses, seeks, and pauses in background', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: WalkReplayScreen(
          journey: journey,
          memoryStore: FakeMemories(),
          trailStore: FakeTrail([point(0), point(10)]),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Play replay'));
    await tester.pump(const Duration(seconds: 1));
    expect(find.byTooltip('Pause replay'), findsOneWidget);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(find.byTooltip('Play replay'), findsOneWidget);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    tester.widget<Slider>(find.byType(Slider)).onChanged!(7);
    await tester.pump();
    expect(find.text('0:07 / 0:10'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('Final story pauses map and Continue does not restart replay', (
    tester,
  ) async {
    final speech = FakeSpeech();
    // Use an unreviewed story, so opening it must not autoplay narration.
    await tester.pumpWidget(
      MaterialApp(
        home: WalkReplayScreen(
          journey: journey,
          stories: [story()],
          memoryStore: FakeMemories(),
          trailStore: FakeTrail([point(0), point(10)]),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Next memory or story'));
    await tester.pumpAndSettle();
    expect(find.text('Saved story'), findsOneWidget);
    await tester.tap(find.text('Continue replay'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Play replay'), findsOneWidget);
    expect(find.text('0:10 / 0:10'), findsOneWidget);
    await tester.pumpWidget(
      MaterialApp(
        home: ReplayMediaScreen(
          event: ReplayEvent(seconds: 0, story: story()),
          speech: speech,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(speech.texts, isEmpty);
    await tester.tap(find.byTooltip('Play narration'));
    await tester.pumpAndSettle();
    expect(speech.texts, ['A saved story.']);
    await tester.pumpWidget(const SizedBox());
  });
}

class FakeMemories extends MemoryStore {
  @override
  Future<String> journeyId(String id) async => id;
  @override
  Future<List<WalkMemory>> list() async => [];
}

class FakeTrail extends WalkTrailStore {
  FakeTrail(this.rows);
  final List<Map<String, dynamic>> rows;
  @override
  Future<List<Map<String, dynamic>>> readJourney(String id) async => rows;
}

class FakeSpeech implements RoverTextToSpeech {
  final texts = <String>[];
  @override
  Future<void> configure({required double rate}) async {}
  @override
  Future<void> speak(String text) async {
    texts.add(text);
  }

  @override
  Future<void> stop() async {}
  @override
  Future<void> pause() async {}
  @override
  Future<void> dispose() async {}
}
