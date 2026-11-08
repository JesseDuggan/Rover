import 'package:flutter/material.dart';
import 'package:rover/src/api/story_question_models.dart';
import 'package:rover/src/api/location_story_models.dart';
import 'package:rover/src/voice/rover_audio_services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rover/src/api/rover_api_client.dart';
import 'package:rover/src/preferences/preferences_controller.dart';
import 'package:rover/src/preferences/preferences_repository.dart';
import 'package:rover/src/ui/journey_lab_screen.dart';

typedef Json = Map<String, dynamic>;

class FakeJourneyApi extends RoverApiClient {
  final requests = <List<Json>>[];
  final suggested = <bool>[];
  static const stop = <String, dynamic>{
    'name': 'Town Museum',
    'category': 'museum',
    'latitude': 43.65,
    'longitude': -79.38,
    'id': 'google-museum',
    'attribution': 'Museum archive',
    'address': '1 Main Street',
    'sourceUrl': 'https://example.org/museum',
  };
  bool receivedJourney = false;
  @override
  Future<StoryQuestionResponse> researchStoryQuestion(
    StoryQuestionRequest request,
  ) async => const StoryQuestionResponse(
    status: 'empty',
    scope: 'City',
    format: 'Single',
    answers: [],
  );
  @override
  Future<LocationStoryResponse> createDriveStopStory({
    required String id,
    required String name,
    required double latitude,
    required double longitude,
    List<String>? interests,
    Map<String, double>? journeyStart,
    Map<String, double>? journeyEnd,
  }) async {
    receivedJourney =
        journeyStart != null && journeyEnd != null && interests != null;
    return LocationStoryResponse.fromJson({
      'placeId': id,
      'storyTitle': name,
      'shortSpokenNarration': 'Museum story.',
      'factIdsUsed': ['fact1'],
      'sourceReferences': [
        {'providerName': 'museum', 'attribution': 'Museum archive'},
      ],
    });
  }

  @override
  Future<Json> nearbyJourneyStops({
    required Map<String, double> location,
    required List<String> interests,
  }) async => {
    'stops': [stop],
  };
  @override
  Future<Json> planJourney({
    required Map<String, double> start,
    required Map<String, double>? end,
    required List<Json> stops,
    required bool suggest,
    required int minutes,
    required List<String> interests,
  }) async {
    requests.add([...stops]);
    suggested.add(suggest);
    return {
      'stops': [stop],
      'coordinates': [start, end!],
      'walkingMinutes': 10,
      'visitMinutes': 5,
      'distanceMeters': 760,
    };
  }
}

void main() {
  testWidgets(
    'confirmed replacement uses empty suggestions and preserves POI metadata on build',
    (tester) async {
      final api = FakeJourneyApi();
      addTearDown(() => api.close(force: true));
      tester.view.physicalSize = const Size(900, 1500);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        PreferencesScope(
          controller: PreferencesController(MemoryPreferencesRepository()),
          child: MaterialApp(home: JourneyLabScreen(client: api)),
        ),
      );
      Future<void> press(String text) async {
        final finder = find.text(text);
        await tester.ensureVisible(finder);
        await tester.tap(finder);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pump();
      }

      final map = find.byType(FlutterMap);
      final originalMap = tester.element(map);
      final center = tester.getCenter(map);
      await tester.tapAt(center - const Offset(40, 0));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump();
      await tester.tapAt(center + const Offset(40, 0));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump();
      await tester.tapAt(center);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump();
      await press('Town Museum');
      expect(find.text('museum (1)'), findsOneWidget);
      await press('Suggest stops');
      await press('Cancel');
      expect(api.requests, isEmpty);
      await press('Suggest stops');
      await press('Replace stops');
      expect(api.requests.single, isEmpty);
      expect(find.text('Generate journey stories'), findsNothing);
      await press('Build walking route');
      expect(api.suggested, [true, false]);
      expect(api.requests.last, [FakeJourneyApi.stop]);
      expect(find.text('Generate journey stories'), findsOneWidget);
      expect(
        tester
            .widget<PolylineLayer>(find.byType(PolylineLayer))
            .polylines
            .single
            .points,
        hasLength(2),
      );
      final spoken = <String>[];
      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(voiceChannel, (call) async {
        if (call.method == 'ttsSpeak')
          spoken.add(call.arguments['text'] as String);
        return null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(voiceChannel, null));
      tester.view.physicalSize = const Size(900, 600);
      await tester.pump();
      final position = tester.state<ScrollableState>(find.byType(Scrollable).first).position;
      position.jumpTo(position.maxScrollExtent);
      await tester.pump();
      expect(tester.element(find.byType(FlutterMap, skipOffstage: false)), same(originalMap));
      position.jumpTo(0);
      tester.view.physicalSize = const Size(900, 1500);
      await tester.pump();
      await press('Play journey from home');
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 300));
      }
      expect(api.receivedJourney, isTrue);
      expect(spoken, ['Finding a story about Town Museum.', 'Museum story.']);
      spoken.clear();
      await press('Play story');
      expect(spoken, ['Museum story.']);
      expect(find.text('Story finished.'), findsOneWidget);
    },
  );
}
