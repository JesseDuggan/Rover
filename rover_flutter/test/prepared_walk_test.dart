import 'dart:async';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rover/src/ui/prepared_walk_screen.dart';
import 'package:rover/src/voice/rover_audio_services.dart';
import 'package:rover/src/location/rover_location.dart';

class Voice implements RoverTextToSpeech {
  final spoken = <String>[];
  Completer<void>? pending;
  @override
  Future<void> speak(String text) {
    spoken.add(text);
    pending = Completer<void>();
    return pending!.future;
  }

  @override
  Future<void> stop() async {
    if (pending?.isCompleted == false) pending!.complete();
  }

  @override
  Future<void> configure({required double rate}) async {}
  @override
  Future<void> dispose() => stop();
  @override
  Future<void> pause() => stop();
}

class Location extends RoverLocationProvider {
  final readings = StreamController<RoverLocationReading>.broadcast();
  int requests = 0;
  @override
  String get label => 'Test';
  @override
  bool get requestsSystemPermission => true;
  @override
  Future<LocationFailure?> requestForegroundPermission() async {
    requests++;
    return null;
  }

  @override
  Stream<RoverLocationReading> watchLocation() => readings.stream;
  @override
  Future<RoverLocationResult> getCurrentLocation() =>
      throw UnimplementedError();
  void at(double lat, double lon) => readings.add(
    RoverLocationReading(
      location: RoverLatLng(latitude: lat, longitude: lon),
      recordedAtUtc: DateTime.now().toUtc(),
      accuracyMeters: 5,
    ),
  );
}

Future<void> finishStory(WidgetTester t, Voice voice) async {
  for (var i = 0; i < 20 && find.text('Continue walking').evaluate().isEmpty; i++) {
    await voice.stop();
    await t.pump();
  }
  expect(find.text('Continue walking'), findsOneWidget);
}

void main() {
  testWidgets('new arrival interrupts and skipping it resumes the nearby unfinished sentence', (t) async {
    final path = bloorRehearsal.path;
    final origin = path.first;
    final next = LatLng(origin.latitude, origin.longitude + .0015);
    final walk = PreparedWalk('Local walk', path, [
      PreparedStop('First', origin, const WalkAnswer('First sentence. Finish this story.', {})),
      PreparedStop('Second', next, const WalkAnswer('Second stop story.', {})),
    ]);
    final voice = Voice(), location = Location();
    await t.pumpWidget(MaterialApp(home: PreparedWalkScreen(
      walk: walk, voice: voice, location: location, research: (_) async => null)));
    await t.tap(find.text('Test on foot with GPS'));
    await t.pump();
    location.at(origin.latitude, origin.longitude);
    await t.pump();
    await voice.stop();
    await t.pump();
    expect(voice.spoken.last, 'Finish this story.');
    location.at(next.latitude, next.longitude);
    await t.pump();
    expect(voice.spoken.last, 'Second stop story.');
    await t.ensureVisible(find.text('Continue to next stop'));
    await t.tap(find.text('Continue to next stop'));
    await t.pump();
    expect(voice.spoken.last, 'Finish this story.');
    expect(voice.spoken.where((s) => s == 'First sentence.'), hasLength(1));
    expect(voice.spoken.where((s) => s == 'Second stop story.'), hasLength(1));
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('arrival announces the matching photo and the walker can open and close it', (t) async {
    t.view.physicalSize = const Size(900, 1600);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final path = bloorRehearsal.path;
    const photo = TourPhoto(asset: 'assets/tours/plaza.jpg', caption: 'the Plaza Hotel and Casino',
      author: 'Photographer', license: 'CC BY', source: 'https://commons.wikimedia.org', licenseUrl: 'https://creativecommons.org');
    final walk = PreparedWalk('Test tour', path, [
      PreparedStop('Plaza', path.first, const WalkAnswer('Look up at the hotel.', {}), photo: photo),
      PreparedStop('Next stop', path.last, const WalkAnswer('Another story.', {})),
    ], theme: 'downtown', orderedChapters: true);
    final voice = Voice();
    await t.pumpWidget(MaterialApp(home: PreparedWalkScreen(walk: walk, voice: voice, research: (_) async => null)));
    expect(find.byTooltip('View photo of Plaza'), findsOneWidget);
    expect(find.byTooltip('View photo of Next stop'), findsNothing);
    await t.ensureVisible(find.text('Play from home'));
    await t.tap(find.text('Play from home'));
    await t.pump();
    await voice.stop();
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
    expect(voice.spoken.last, photo.cue);
    final view = find.text('View photo · ${photo.caption}');
    await t.ensureVisible(view);
    await t.tap(view);
    await t.pumpAndSettle();
    expect(find.text('Story photo'), findsOneWidget);
    await t.tap(find.byTooltip('Close photo'));
    await t.pumpAndSettle();
    await voice.stop();
    await t.pump();
    expect(voice.spoken.last, 'Look up at the hotel.');
    expect(voice.spoken.where((s) => s == photo.cue), hasLength(1));
    await t.pumpWidget(const SizedBox());
  });

  testWidgets(
    'trail resumes the interrupted sentence and recaps only heard chapters',
    (t) async {
      t.view.physicalSize = const Size(900, 1600);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final path = bloorRehearsal.path;
      PreparedStop chapter(String name, int i) => PreparedStop(
        name,
        path[i],
        WalkAnswer('First $name. Second $name.', {
          'Archive': 'https://example.org/archive',
        }),
      );
      final walk = PreparedWalk('Trail', path, [
        chapter('One', 0),
        chapter('Two', 4),
        chapter('Three', 7),
      ], theme: 'local history');
      final voice = Voice(), location = Location();
      await t.pumpWidget(
        MaterialApp(
          home: PreparedWalkScreen(
            walk: walk,
            voice: voice,
            location: location,
            research: (_) => throw StateError('Unexpected request'),
            followUp: (s, q) async {
              expect(s.name, 'One');
              expect(q, 'Who lived here?');
              return const WalkAnswer('Local answer.', {});
            },
          ),
        ),
      );
      await t.ensureVisible(find.text('Test on foot with GPS'));
      await t.tap(find.text('Test on foot with GPS'));
      await t.pump();
      await voice.stop();
      await t.pump();
      Future<void> arrive(int i) async {
        location.at(path[i].latitude, path[i].longitude);
        await t.pump();
      }

      await arrive(0);
      await voice.stop();
      await t.pump();
      expect(voice.spoken.last, 'Second One.');
      await t.ensureVisible(find.text('Ask a question'));
      await t.tap(find.text('Ask a question'));
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField), 'Who lived here?');
      await t.tap(find.text('Ask'));
      await t.pumpAndSettle();
      expect(voice.spoken.last, 'Local answer.');
      await voice.stop();
      await t.pump();
      expect(voice.spoken.last, 'Second One.');
      await voice.stop();
      await t.pump();
      await t.ensureVisible(find.text('Continue walking'));
      await t.tap(find.text('Continue walking'));
      await t.pump();
      await t.ensureVisible(find.text('Skip next stop'));
      await t.tap(find.text('Skip next stop'));
      await t.pump();
      await arrive(4);
      await arrive(7);
      expect(voice.spoken.last, contains('From One'));
      for (var i = 0; i < 3; i++) {
        await voice.stop();
        await t.pump();
      }
      await t.ensureVisible(find.text('Continue walking'));
      await t.tap(find.text('Continue walking'));
      await t.pump();
      await arrive(9);
      expect(voice.spoken.last, contains('One, Three'));
      expect(voice.spoken.last, isNot(contains('Two')));
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'Perth question uses the reached stop and a late answer cannot resume a stopped walk',
    (t) async {
      final original = bloorRehearsal.stops.single;
      final stop = PreparedStop(
        'Local field-test stop',
        original.point,
        original.story,
      );
      final walk = PreparedWalk('Prepared walk', bloorRehearsal.path, [stop]);
      final pending = Completer<WalkAnswer?>();
      final voice = Voice();
      PreparedStop? askedAbout;
      await t.pumpWidget(
        MaterialApp(
          home: PreparedWalkScreen(
            walk: walk,
            voice: voice,
            research: (place) {
              askedAbout = place;
              return pending.future;
            },
          ),
        ),
      );
      await t.tap(find.text('Play from home'));
      await t.pump();
      await t.pump(const Duration(seconds: 1));
      await voice.stop();
      await t.pump();
      await t.tap(find.text('What’s there now?'));
      await t.pump();
      expect(askedAbout, same(stop));
      await t.tap(find.text('Stop walk'));
      await t.pump();
      final before = List.of(voice.spoken);
      pending.complete(const WalkAnswer('Late answer', {}));
      await t.pump();
      expect(voice.spoken, before);
      expect(find.text('Walk stopped.'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets('Perth GPS field test plays the museum checkpoint once', (
    t,
  ) async {
    final voice = Voice(), location = Location();
    await t.pumpWidget(
      MaterialApp(
        home: PreparedWalkScreen(
          walk: perthFieldTest,
          voice: voice,
          location: location,
          research: (_) => throw StateError('Unexpected network research'),
        ),
      ),
    );
    await t.tap(find.text('Test on foot with GPS'));
    await t.pump();
    final start = perthFieldTest.path.first,
        museum = perthFieldTest.stops.single.point,
        end = perthFieldTest.path.last;
    location.at(start.latitude, start.longitude);
    await t.pump();
    expect(voice.spoken, isEmpty);
    location.at(museum.latitude, museum.longitude);
    await t.pump();
    await t.pump();
    expect(voice.spoken.single, contains('stone house'));
    await t.tap(find.text('What’s there now?'));
    await t.pump();
    expect(voice.spoken.last, contains('Perth Museum'));
    await voice.stop();
    await t.pump();
    await finishStory(t, voice);
    expect(voice.spoken.join(' '), contains('Roderick Matheson'));
    location.at(end.latitude, end.longitude);
    await t.pump();
    await t.pump();
    expect(find.text('Walk complete'), findsOneWidget);
    expect(voice.spoken.where((s) => s.contains('Roderick Matheson')), hasLength(1));
    await t.pumpWidget(const SizedBox());
    await location.readings.close();
  });
  for (final live in [false, true]) {
    testWidgets(
      'theatre, interruption, answer and resume with ${live ? "GPS" : "simulation"}',
      (t) async {
        final voice = Voice(), location = Location();
        await t.pumpWidget(
          MaterialApp(
            home: PreparedWalkScreen(
              walk: bloorRehearsal,
              voice: voice,
              location: location,
              research: (_) =>
                  throw StateError('Preset must be identical offline'),
            ),
          ),
        );
        await t.tap(
          find.text(live ? 'Test on foot with GPS' : 'Play from home'),
        );
        await t.pump();
        if (live) {
          location.at(44.9, -76.2);
          await t.pump();
          expect(voice.spoken, isEmpty);
          final theatre = bloorRehearsal.stops.first.point;
          location.at(theatre.latitude, theatre.longitude);
        }
        await t.pump(const Duration(seconds: 1));
        await t.pump();
        expect(location.requests, live ? 1 : 0);
        expect(voice.spoken.single, contains('south side of Bloor'));
        await t.tap(find.text('What’s there now?'));
        await t.pump();
        expect(voice.spoken.last, contains('Shoppers Drug Mart'));
        expect(find.textContaining('Follow-up ·'), findsOneWidget);
        await voice.stop();
        await t.pump();
        expect(voice.spoken.last, contains('south side of Bloor'));
        await finishStory(t, voice);
        expect(voice.spoken.join(' '), contains('Chapman and Oxley'));
        await t.tap(find.text('Continue walking'));
        await t.pump();
        if (live) {
          final end = bloorRehearsal.path.last;
          location.at(end.latitude, end.longitude);
        }
        await t.pump(const Duration(seconds: 60));
        await t.pump();
        expect(find.text('Walk complete'), findsOneWidget);
        expect(voice.spoken.where((s) => s.contains('Chapman and Oxley')), hasLength(1));
        await t.pumpWidget(const SizedBox());
        await location.readings.close();
      },
    );
  }
}
