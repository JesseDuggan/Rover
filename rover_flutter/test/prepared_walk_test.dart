import 'dart:async';

import 'package:flutter/material.dart';
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

void main() {
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
      pending.complete(const WalkAnswer('Late answer', {}));
      await t.pump();
      expect(voice.spoken, hasLength(1));
      expect(find.text('Walk stopped.'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
    },
  );
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
        expect(voice.spoken.single, contains('Chapman and Oxley'));
        await t.tap(find.text('What’s there now?'));
        await t.pump();
        expect(voice.spoken.last, contains('Shoppers Drug Mart'));
        expect(find.textContaining('Follow-up ·'), findsOneWidget);
        await voice.stop();
        await t.pump();
        expect(
          find.text(
            live
                ? 'Walking · waiting for the next arrival'
                : 'Simulating the walk',
          ),
          findsOneWidget,
        );
        if (live) {
          final end = bloorRehearsal.path.last;
          location.at(end.latitude, end.longitude);
        }
        await t.pump(const Duration(seconds: 60));
        await t.pump();
        expect(find.text('Walk complete'), findsOneWidget);
        expect(voice.spoken, hasLength(2));
        await t.pumpWidget(const SizedBox());
        await location.readings.close();
      },
    );
  }
}
