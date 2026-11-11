import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rover/src/ui/tour_locations.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('all master records survive, with 13 destinations and no invented audio pin', () async {
    final d = jsonDecode(
      await rootBundle.loadString('assets/tours/LV-05.json'),
    ) as Map;
    final rows = (d['locations'] as List).cast<Map>();
    Map row(String id) => rows.firstWhere((r) => r['id'] == id);
    expect(rows.map((r) => r['id']).toSet().length, 16);
    expect(tourDestinations(rows).length, 13);
    expect(rows.where((r) => r['group'] == 'core').length, 4);
    expect(rows.where((r) => r['group'] == 'nightlife').length, 5);
    expect(row('LVAD004')['geofenceId'], 'LVAD003');
    expect(row('LVAD004')['latitude'], row('LVAD003')['latitude']);
    expect(row('LVAD006')['parentId'], 'LVAD005');
    expect(row('LVAD007')['latitude'], isNull);
    expect(tourLocationDirections(row('LVAD007')), isNull);
    for (final r in rows.where((r) => r['visit_mode'] == 'rideshare')) {
      expect(
        tourLocationDirections(r)!.queryParameters['travelmode'],
        'driving',
      );
      expect(r['placeId'], isNotEmpty);
    }
    final storyIds = (d['storyChapters'] as List)
        .map((s) => s['storyId'])
        .toSet();
    expect(storyIds.length, 8);
    expect(rows.expand((r) => r['storyIds'] as List).toSet(), storyIds);
    expect((d['chapters'] as List).map((c) => c['locationId']).toList(), [
      'LVAD001',
      'LVAD002',
      'LVAD003',
      'LVAD005',
    ]);
  });
}
