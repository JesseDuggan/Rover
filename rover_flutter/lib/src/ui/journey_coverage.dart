import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

/// Distances are measured along the supplied pedestrian polyline, in metres.
class JourneyCoverage {
  final List<LatLng> points;
  final List<double> metres = [0];
  static const distance = Distance(roundResult: false);

  JourneyCoverage(this.points) {
    for (var i = 1; i < points.length; i++) {
      metres.add(metres.last + distance(points[i - 1], points[i]));
    }
  }

  double get total => metres.last;

  LatLng at(double m) {
    for (var i = 1; i < points.length; i++) {
      if (m <= metres[i] && metres[i] > metres[i - 1]) {
        return distance.offset(
          points[i - 1],
          math.max(0, m - metres[i - 1]),
          distance.bearing(points[i - 1], points[i]),
        );
      }
    }
    return points.last;
  }

  ({double along, double away}) project(LatLng point) {
    var along = 0.0, away = distance(points.first, point);
    for (var i = 1; i < points.length; i++) {
      final length = metres[i] - metres[i - 1];
      if (length < 0.01) continue;
      final a = points[i - 1];
      final heading = distance.bearing(a, points[i]);
      final delta = (distance.bearing(a, point) - heading) * math.pi / 180;
      final offset = (distance(a, point) * math.cos(delta)).clamp(0.0, length);
      final separation = distance(distance.offset(a, offset, heading), point);
      if (separation < away) {
        away = separation;
        along = metres[i - 1] + offset;
      }
    }
    return (along: along, away: away);
  }

  List<({double start, double end})> gaps(Iterable<double> stories) {
    final positions = [
      0.0,
      ...stories.where((m) => m >= 0 && m <= total),
      total,
    ]..sort();
    return [
      for (var i = 1; i < positions.length; i++)
        if (positions[i] > positions[i - 1])
          (start: positions[i - 1], end: positions[i]),
    ];
  }

  // Check the start first, then split the largest remaining gaps. Bounded for long routes.
  List<double> searchPoints(Iterable<double> positions) {
    final occupied = positions.toList();
    final probes = <double>[];
    for (var i = 0; i < 6; i++) {
      final open = gaps([...occupied, ...probes])
          .where((g) => g.end - g.start >= 250)
          .toList();
      if (open.isEmpty) break;
      if (i > 0 || open.first.start > 0) {
        open.sort((a, b) => (b.end - b.start).compareTo(a.end - a.start));
      }
      final gap = open.first;
      probes.add(
        i == 0 && gap.start == 0
            ? math.min(175, gap.end / 2)
            : (gap.start + gap.end) / 2,
      );
    }
    return probes;
  }
}

String shortPassage(String text) {
  final value = text.trim();
  if (value.length <= 360) return value;
  final cut = value.substring(0, 360);
  final ends = RegExp(r'[.!?](?:\s|$)|[。！？]').allMatches(cut).toList();
  return ends.isEmpty ? '' : cut.substring(0, ends.last.start + 1).trim();
}

bool foodCategory(String value) => RegExp(
  r'\b(food|coffee|caf[eé]|bakery|dining|restaurant|bar|pub)\b',
  caseSensitive: false,
).hasMatch(value.replaceAll('_', ' '));

/// A mixed walk already visits its planned stops. Use its gap searches to uncover other interests.
List<String> coverageInterests(List<String> interests) {
  final other = interests.where((i) => !foodCategory(i)).toList();
  return other.isEmpty ? interests : other;
}
