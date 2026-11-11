import 'package:flutter_test/flutter_test.dart';
import 'package:rover/src/ui/fremont_tour.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Both Fremont starts reach every chapter in walking order', () async {
    final names = <Set<String>>[];
    for (final start in ['Plaza', 'El Cortez']) {
      final walk = await fremontTour(start: start, interests: ['history'], depth: '');
      expect(walk.stops.first.name, startsWith(start));
      expect(walk.path.first, walk.stops.first.point);
      expect(walk.path.last, walk.stops.last.point);
      expect(walk.stops.length, 10);
      var cursor = 0;
      for (final stop in walk.stops) {
        final index = walk.path.indexOf(stop.point, cursor);
        expect(index, greaterThanOrEqualTo(cursor), reason: stop.name);
        cursor = index + 1;
        expect(stop.story.sources, isNotEmpty);
      }
      names.add(walk.stops.map((s) => s.name).toSet());
    }
    expect(names.first, names.last);
  });

  test('Profile changes the spoken stories and depth preserves the route', () async {
    final history = await fremontTour(start: 'Plaza', interests: ['History'], depth: '');
    final design = await fremontTour(start: 'Plaza', interests: ['Architecture'], depth: '');
    final deeper = await fremontTour(start: 'Plaza', interests: ['Architecture'], depth: 'deeper stories');
    expect(design.path, history.path);
    expect(design.stops.first.story.text, contains('glass dome'));
    expect(history.stops.first.story.text, contains('auction'));
    expect(deeper.stops.first.story.text, startsWith(design.stops.first.story.text));
    expect(deeper.stops.first.story.text, contains('auction'));
  });
}
