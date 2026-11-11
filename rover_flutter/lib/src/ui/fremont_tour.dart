import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';

import 'prepared_walk_screen.dart';

const fremontRehearsalStart = LatLng(36.17392, -115.14396);

/// Load the same reviewed landmarks for both starts. Interests choose the
/// narration at each landmark, independently of its position in the walk.
Future<PreparedWalk> fremontTour({
  required String start,
  required List<String> interests,
  required String depth,
}) => loadCityTour(
  asset: 'fremont',
  start: start,
  interests: interests,
  depth: depth,
);

Future<PreparedWalk> loadCityTour({
  required String asset,
  required String start,
  required List<String> interests,
  required String depth,
}) async {
  final tour = jsonDecode(
    await rootBundle.loadString('assets/tours/$asset.json'),
  ) as Map<String, dynamic>;
  final credits = jsonDecode(
    await rootBundle.loadString('assets/tours/photo_credits.json'),
  ) as List;
  final creditsByAsset = {
    for (final credit in credits) credit['asset']: credit,
  };
  final route = tour['starts'][start];
  final chapters = tour['chapters'] as List;
  final selected = interests.map((v) => v.toLowerCase().trim()).toSet();
  LatLng point(List values) => LatLng(values[0] as double, values[1] as double);
  final stops = <PreparedStop>[];
  for (final index in route['order'] as List) {
    final chapter = chapters[index];
    final angles = chapter['angles'] as List;
    int matches(dynamic angle) =>
        (angle['interests'] as List).where(selected.contains).length;
    final best = matches(angles[1]) > matches(angles[0]) ? 1 : 0;
    final words = [
      chapter['opening'],
      angles[best]['text'],
      if (depth.toLowerCase() == 'deeper stories') angles[1 - best]['text'],
    ].join(' ');
    final image = chapter['photo'];
    final credit = image == null ? null : creditsByAsset[image['asset']];
    stops.add(
      PreparedStop(
        chapter['name'],
        point(chapter['point']),
        WalkAnswer(words, Map<String, String>.from(chapter['sources'])),
        optional: chapter['optional'] == true,
        photo: credit == null
            ? null
            : TourPhoto(
                asset: 'assets/tours/${image['asset']}.jpg',
                caption: image['caption'],
                author: credit['author'],
                license: credit['license'],
                source: credit['source'],
                licenseUrl: credit['licurl'],
              ),
      ),
    );
  }
  return PreparedWalk(
    tour['title'],
    [for (final p in route['path']) point(p)],
    stops,
    theme: tour['theme'] ?? 'the changing face of Fremont Street',
    orderedChapters: true,
  );
}
