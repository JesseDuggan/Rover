import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rover/src/ui/tour_details.dart';
import 'package:rover/src/voice/rover_audio_services.dart';

class TestVoice implements RoverTextToSpeech {
  final spoken = <String>[];
  int stops = 0;
  @override
  Future<void> configure({required double rate}) async {}
  @override
  Future<void> speak(String text) async {
    spoken.add(text);
  }

  @override
  Future<void> stop() async {
    stops++;
  }

  @override
  Future<void> pause() async {}
  @override
  Future<void> dispose() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Future<Map<String, dynamic>> data() async =>
      jsonDecode(await rootBundle.loadString('assets/tours/LV-05.json'))
          as Map<String, dynamic>;
  test('eight separate stories retain real anchors; optional visits stay outside route', () async {
    final d = await data();
    final stories = d['storyChapters'] as List;
    expect(
      stories.map((s) => s['id']).toList(),
      List.generate(8, (i) => i + 1),
    );
    expect(d['chapters'].length, 4);
    expect(d['starts']['Default']['order'].length, 4);
    expect(d['optionalVisits'].length, 3);
    expect(stories[4]['locationNote'], contains('outside this route'));
    for (final s in stories) {
      expect(s['text'], isNotEmpty);
      expect(s['sources'], isNotEmpty);
    }
    expect(stories.map((s) => s['title']).join(' '), contains('Arizona Club'));
  });
  testWidgets(
    'a chapter can be expanded, read and played without route generation',
    (tester) async {
      final d = (await tester.runAsync(data))!;
      final voice = TestVoice();
      await tester.pumpWidget(
        MaterialApp(
          home: TourDetailsScreen(data: d, voice: voice),
        ),
      );
      await tester.tap(find.text('Stories (8)'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('chapter-1')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Play this story').first);
      await tester.tap(find.text('Play this story').first);
      await tester.pumpAndSettle();
      expect(voice.spoken, [d['storyChapters'][0]['text']]);
      await tester.pumpWidget(const SizedBox());
      expect(voice.stops, greaterThanOrEqualTo(2));
    },
  );
}
