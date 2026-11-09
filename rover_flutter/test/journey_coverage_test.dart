import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:rover/src/ui/journey_coverage.dart';

void main() {
  test('first arrival and quiet time use walking distance covered by pass-by audio', () {
    final report = quietWalking(600, 10, [
      (at: 100.0, walkingSpeech: List.filled(150, 'word').join(' ')),
      (at: 450.0, walkingSpeech: ''),
    ]);
    expect(report.first, 100);
    expect(report.longest, (start: 160.0, end: 450.0));
    expect(report.secondsPerMetre, 1);
    final empty = quietWalking(300, 5, []);
    expect(empty.first, isNull);
    expect(empty.longest, (start: 0.0, end: 300.0));
  });
  for (final origin in [const LatLng(-33.9, 18.4), const LatLng(65, 179.999)]) {
    test('Coverage follows the pedestrian bend at ${origin.latitude}', () {
      const geo = JourneyCoverage.distance;
      final corner = geo.offset(origin, 600, 90);
      final path = JourneyCoverage([
        origin,
        corner,
        geo.offset(corner, 600, 0),
      ]);
      final cue = path.project(geo.offset(corner, 100, 0));
      expect(cue.along, closeTo(700, 3));
      expect(cue.away, lessThan(1));
      expect(geo(path.at(700), geo.offset(corner, 100, 0)), lessThan(3));
      final probes = path.searchPoints([cue.along]);
      expect(probes.first, 175);
      expect(probes.any((p) => p > cue.along), isTrue);
      expect(probes.length, lessThanOrEqualTo(6));
      final gaps = path.gaps([cue.along, cue.along]);
      expect(gaps.length, 2);
      expect(gaps.last.end - gaps.last.start, closeTo(500, 3));
    });
  }
  test(
    'A short sparse route and repeated vertices need no artificial cues',
    () {
      const p = LatLng(-12, 131);
      final path = JourneyCoverage([
        p,
        p,
        JourneyCoverage.distance.offset(p, 200, 0),
      ]);
      expect(path.searchPoints([]), isEmpty);
      expect(path.gaps([]).single.end, closeTo(200, 2));
    },
  );
  test(
    'Short narration ends at a complete sentence in its original language',
    () {
      expect(shortPassage('A short sourced fact.'), 'A short sourced fact.');
      expect(shortPassage('Une phrase. ${"x" * 400}'), 'Une phrase.');
      expect(shortPassage('歴史。${"字" * 400}'), '歴史。');
      expect(shortPassage('x' * 400), isEmpty);
    },
  );
}
