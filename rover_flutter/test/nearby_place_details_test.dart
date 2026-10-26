import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rover/src/api/location_story_models.dart';
import 'package:rover/src/just_walking/nearby_place_details.dart';

void main() {
  testWidgets('place details show facts and sources', (tester) async {
    final place = LocationPlaceSummary.fromJson({
      'name': 'Old square',
      'address': 'Market street',
      'facts': [
        {'factText': 'The square hosted a weekly market.'},
      ],
      'sourceReferences': [
        {
          'attribution': 'City archive',
          'sourceUrl': 'https://example.org/archive',
        },
      ],
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: NearbyPlaceDetails(place: place)),
      ),
    );
    expect(find.text('Old square'), findsOneWidget);
    expect(find.text('Market street'), findsOneWidget);
    expect(find.text('The square hosted a weekly market.'), findsOneWidget);
    expect(find.textContaining('City archive'), findsOneWidget);
  });
  testWidgets('empty place has explicit unavailable state', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NearbyPlaceDetails(
            place: LocationPlaceSummary.fromJson({'name': 'Nearby place'}),
          ),
        ),
      ),
    );
    expect(
      find.text('No detailed information is available for this place yet.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
