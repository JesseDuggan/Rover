import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rover/src/ui/explore_tours.dart';
import 'package:rover/src/ui/fremont_tour.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('adult draft uses saved chapters and unique outdoor triggers', () async {
    final walk = await loadCityTour(
      asset: afterDarkTour.asset,
      start: 'Default',
      interests: ['history'],
      depth: 'Deeper stories',
    );
    expect(afterDarkTour.minimumAge, 21);
    expect(afterDarkTour.savedNarration, isTrue);
    expect(walk.stops.length, 4);
    expect(walk.stops.map((s) => s.point).toSet().length, 4);
    expect(walk.orderedChapters, isTrue);
    expect(walk.stops.first.name, contains('Golden Gate'));
    expect(walk.stops.last.name, contains('Mob Museum'));
    final block = walk.stops.firstWhere((s) => s.name.startsWith('Block 16'));
    expect(block.story.text, contains('elsewhere, not on this block'));
    for (final stop in walk.stops) {
      expect(stop.story.sources, isNotEmpty);
      expect(stop.story.text, isNot(contains('Fremont Street,')));
    }
  });
  testWidgets('adult tour stays hidden until explicit group age confirmation', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: ExploreToursScreen()));
    expect(find.text(afterDarkTour.name), findsNothing);
    await tester.scrollUntilVisible(
      find.text('Show adults-only tours (21+)'),
      400,
    );
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text(afterDarkTour.name), findsNothing);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Everyone is 21+'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text(afterDarkTour.name), -250);
    expect(find.text(afterDarkTour.name), findsOneWidget);
  });
}
