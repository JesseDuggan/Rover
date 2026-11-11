import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:rover/src/preferences/preferences_controller.dart';
import 'package:rover/src/preferences/preferences_repository.dart';
import 'package:rover/src/ui/prepared_walk_screen.dart';
import 'package:rover/src/maps/rover_map_view.dart';
import 'package:rover/src/memories/memories_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rover/src/ui/explore_tours.dart';
import 'package:rover/src/ui/fremont_tour.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('all Vegas tours can be browsed without location services', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: ExploreToursScreen()));
    for (final tour in vegasTours) {
      await tester.scrollUntilVisible(find.text(tour.name), 150);
      expect(find.text(tour.name), findsOneWidget);
      expect(find.text(tour.estimate), findsOneWidget);
      expect(
        find.image(AssetImage('assets/tours/${tour.asset}.jpg')),
        findsOneWidget,
      );
    }
  });

  for (final tour in vegasTours) {
    test(
      '${tour.name} has ordered route triggers and personal memories',
      () async {
        final walk = await loadCityTour(
          asset: tour.asset,
          start: tour.asset == 'fremont' ? 'Plaza' : 'Default',
          interests: ['architecture'],
          depth: 'Deeper stories',
        );
        var cursor = 0;
        for (final stop in walk.stops) {
          final index = walk.path.indexOf(stop.point, cursor);
          expect(index, greaterThanOrEqualTo(cursor), reason: stop.name);
          cursor = index + 1;
          expect(stop.story.sources, isNotEmpty);
        }
        final outing = tourMemoryJourney(tour, walk);
        expect(outing.route.distanceMiles, greaterThan(0));
        expect(outing.route.stops.length, walk.stops.length);
        expect(outing.route.title, tour.name);
      },
    );
  }
  testWidgets('tour camera opens directly and keeps the selected outing', (
    tester,
  ) async {
    await tester.pumpWidget(
      PreferencesScope(
        controller: PreferencesController(MemoryPreferencesRepository()),
        child: const MaterialApp(home: ExploreToursScreen()),
      ),
    );
    rootBundle.evict('assets/tours/LV-02.json');
      rootBundle.evict('assets/tours/photo_credits.json');
      final name = vegasTours[1].name;
    await tester.drag(find.byType(ListView), const Offset(0, -480));
    await tester.pumpAndSettle();
    await tester.tap(find.text(name));
    await tester.pumpAndSettle();
    expect(find.byType(PreparedWalkScreen), findsOneWidget);
    expect(find.byType(RoverMapView), findsOneWidget);
    await tester.tap(find.text('Take photo or video'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    final camera = tester.widget<MemoryCaptureScreen>(
      find.byType(MemoryCaptureScreen),
    );
    expect(camera.journey!.route.title, name);
    expect(find.text('Photo'), findsOneWidget);
    expect(find.text('Video'), findsOneWidget);
  });

}
