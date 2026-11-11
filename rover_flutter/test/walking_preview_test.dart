import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rover/src/api/rover_api_client.dart';
import 'package:rover/src/ui/fremont_tour.dart';
import 'package:rover/src/ui/prepared_walk_screen.dart';
import 'package:rover/src/ui/tour_route_preview.dart';

class _Planner extends RoverApiClient {
  final approachInterests = <List<String>>[];
  @override
  Future<Map<String, dynamic>> nearbyJourneyStops({
    required Map<String, double> location,
    required List<String> interests,
  }) async {
    approachInterests.add(interests);
    return {'stops': []};
  }
  final requests = <List<String>>[];
  @override
  Future<Map<String, dynamic>> planJourney({
    required Map<String, double> start,
    required Map<String, double>? end,
    required List<Map<String, dynamic>> stops,
    required bool suggest,
    required int minutes,
    required List<String> interests,
    String pace = 'Standard',
  }) async {
    expect(minutes, 45);
    expect(suggest, false);
    expect(pace, 'Leisurely');
    requests.add(interests);
    return {
      'coordinates': [start, ...stops],
      'distanceMeters': 2000,
      'walkingMinutes': 40,
      'visitMinutes': 20,
      'stops': stops,
    };
  }
}

void main() {
  testWidgets(
    'Fremont keeps the same start and chapter order across interest previews',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final planner = _Planner();
      Future<PreparedWalk> load(List<String> interests) =>
          fremontTour(start: 'Plaza', interests: interests, depth: '');
      final walk = await load(['history']);
      PreparedWalk? selected;
      await tester.pumpWidget(
        MaterialApp(
          home: TourRoutePreview(
            initialWalk: walk,
            rehearsalStart: fremontRehearsalStart,
            api: planner,
            loadWalk: load,
            pace: 'Easy',
            profileInterests: const ['history'],
            onUse: (walk) => selected = walk,
          ),
        ),
      );
      Future<void> tap(String text) async {
        final finder = find.text(text);
        await tester.ensureVisible(finder);
        await tester.tap(finder);
        await tester.pumpAndSettle();
      }

      await tap('Use shared test start');
      await tap('Preview walking route');
      expect(find.text('15 min over your 45 min budget'), findsOneWidget);
      await tap('Use this walk');
      final history = selected!;
      await tap('Architecture');
      expect(find.text('Use this walk'), findsNothing);
      await tap('Preview walking route');
      await tap('Use this walk');
      expect(selected!.path.first, history.path.first);
      expect(
        selected!.stops.map((s) => s.name),
        history.stops.map((s) => s.name),
      );
      expect(
        selected!.stops.first.story.text,
        isNot(history.stops.first.story.text),
      );
      expect(history.path.first, fremontRehearsalStart);
      expect(planner.approachInterests, [['history'], ['architecture']]);
      expect(planner.requests, [
        ['history'],
        ['architecture'],
      ]);
    },
  );
}

