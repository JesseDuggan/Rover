import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
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
  @override
  Future<Json> getStoryImages(List<String> sourceUrls, {double? latitude, double? longitude}) async =>
      {'status': 'empty', 'images': <Json>[]};

  final requests = <List<Json>>[];
  final suggested = <bool>[];
  final paces = <String>[];
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
  @override
  Future<Json> researchAreaStories({
    required double latitude,
    required double longitude,
    required List<String> interests,
    required List<String> excludedTitles,
    int searchRadiusMeters = 1000,
  }) async {
    researchCalls++;
    return {
      'stories': [
        for (final audience in ['unreviewed', 'family'])
          {
            'storyId': audience,
            'title': 'Neighbourhood history',
            'audienceSuitability': audience,
            'anchor': {'latitude': latitude, 'longitude': longitude},
            'expiresUtc': DateTime.now()
                .toUtc()
                .add(const Duration(hours: 1))
                .toIso8601String(),
            'sources': [
              {'sourceId': 'archive'},
            ],
            'claims': [
              {
                'sourceIds': ['archive'],
              },
            ],
            'variants': [
              {'narration': 'Local history: $audience.'},
            ],
          },
      ],
    };
  }

  bool disconnected = false;
  int researchCalls = 0;
  bool receivedJourney = false;
  @override
  Future<StoryQuestionResponse> researchStoryQuestion(
    StoryQuestionRequest request,
  ) async {
    if (disconnected) throw const HttpException('Connection aborted');
    return const StoryQuestionResponse(
    status: 'empty',
    scope: 'City',
    format: 'Single',
    answers: [],
  );
  }
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
    researchCalls++;
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
    String pace = 'Standard',
  }) async {
    requests.add([...stops]);
    suggested.add(suggest);
    paces.add(pace);
    return {
      'stops': [stop],
      if (suggest)
        'skipped': [
          {'name': 'Old quay', 'reason': 'Outside walking corridor'},
        ],
      'coordinates': [start, end!],
      'walkingMinutes': 10,
      'visitMinutes': 5,
      'distanceMeters': 760,
    };
  }
}

void main() {
  testWidgets(
    'Symphony research keeps the sourced venue history when the follow-up is empty',
    (tester) async {
      final api = FakeJourneyApi();
      addTearDown(() => api.close(force: true));
      final stop = {
        ...FakeJourneyApi.stop,
        'id': 'google-ChIJy70XqzTL1IkR1Lhf72C_vWU',
        'name': 'Toronto Symphony Orchestra',
      };
      final start = {...stop, 'longitude': -79.382};
      final packet =
          'WalkaboutLab1.${base64Url.encode(gzip.encode(utf8.encode(jsonEncode({
            'minutes': 60,
            'scope': 'City',
            'next': 0,
            'area': null,
            'start': start,
            'end': stop,
            'stops': [stop],
            'plan': {
              'coordinates': [start, stop],
              'distanceMeters': 160,
              'walkingMinutes': 3,
              'visitMinutes': 2,
            },
            'stories': {},
          }))))}';
      final messenger = tester.binding.defaultBinaryMessenger;
      final spoken = <String>[];
      messenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (c) async => c.method == 'Clipboard.getData' ? {'text': packet} : null,
      );
      messenger.setMockMethodCallHandler(voiceChannel, (c) async {
        if (c.method == 'ttsSpeak') spoken.add(c.arguments['text']);
        return null;
      });
      addTearDown(() {
        messenger.setMockMethodCallHandler(SystemChannels.platform, null);
        messenger.setMockMethodCallHandler(voiceChannel, null);
      });
      tester.view.physicalSize = const Size(1000, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        PreferencesScope(
          controller: PreferencesController(MemoryPreferencesRepository()),
          child: MaterialApp(home: JourneyLabScreen(client: api)),
        ),
      );
      Future<void> press(String name) async {
        final f = find.text(name);
        await tester.ensureVisible(f);
        await tester.tap(f);
        for (var i = 0; i < 8; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
      }

      await press('Open copied replay');
      await press('Generate journey stories');
      await press('Play story');
      expect(spoken.last, contains('Roy Thomson Hall'));
      expect(spoken.last, contains('Massey Hall'));
      expect(find.textContaining('Longest quiet stretch:'), findsOneWidget);
    },
  );
  testWidgets(
    'A second tester can open the same replay and hear a passing cue before arrival',
    (tester) async {
      final api = FakeJourneyApi();
      addTearDown(() => api.close(force: true));
      final stop = FakeJourneyApi.stop;
      final pass = {
        ...stop,
        'name': 'Harbour plaque',
        'id': 'plaque',
        'longitude': -79.381,
        'metres': 80.0,
      };
      final data = {
        'minutes': 60,
        'scope': 'City',
        'next': 0,
        'area': null,
        'start': {...stop, 'longitude': -79.382},
        'end': stop,
        'stops': [stop],
        'plan': {
          'coordinates': [
            {...stop, 'longitude': -79.382},
            stop,
          ],
          'distanceMeters': 160,
          'walkingMinutes': 3,
          'visitMinutes': 2,
          'coverage': {
            'passing': [pass],
            'notes': [],
          },
        },
        'stories': {
          for (final p in [pass, stop])
            p['id']: (await api.createDriveStopStory(
              id: p['id'] as String,
              name: p['name'] as String,
              latitude: 43.65,
              longitude: -79.38,
            )).toJson()..['shortSpokenNarration'] = 'Story at ${p['name']}.',
        },
      };
      String packet =
          'WalkaboutLab1.${base64Url.encode(gzip.encode(utf8.encode(jsonEncode(data))))}';
      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.getData') return {'text': packet};
        if (call.method == 'Clipboard.setData') packet = call.arguments['text'];
        return null;
      });
      final spoken = <String>[];
      messenger.setMockMethodCallHandler(voiceChannel, (call) async {
        if (call.method == 'ttsSpeak') spoken.add(call.arguments['text']);
        return null;
      });
      addTearDown(() {
        messenger.setMockMethodCallHandler(SystemChannels.platform, null);
        messenger.setMockMethodCallHandler(voiceChannel, null);
      });
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
      Future<void> press(String name) async {
        final button = find.text(name);
        if (button.evaluate().isEmpty) {
          await tester.scrollUntilVisible(
            button,
            350,
            scrollable: find.byType(Scrollable).first,
          );
        }
        await tester.ensureVisible(button);
        await tester.tap(button);
        for (var i = 0; i < 8; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
      }

      await press('Open copied replay');
      await press('Copy replay for a tester');
      expect(
        jsonDecode(
          utf8.decode(gzip.decode(base64Url.decode(packet.split('.').last))),
        )['plan']['coverage']['passing'].first['id'],
        'plaque',
      );
      await press('Play journey from home');
      for (var i = 0; i < 25; i++) {
        await tester.pump(const Duration(milliseconds: 160));
      }
      expect(spoken, ['Story at Harbour plaque.', 'Story at Town Museum.']);
    },
  );
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
      expect(find.text('Generate journey stories'), findsOneWidget);
      expect(api.researchCalls, 0);
      await press('Build walking route');
      expect(api.suggested, [true, false]);
      expect(api.paces, ['Leisurely', 'Leisurely']);
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
      final position = tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position;
      position.jumpTo(position.maxScrollExtent);
      await tester.pump();
      expect(
        tester.element(find.byType(FlutterMap, skipOffstage: false)),
        same(originalMap),
      );
      position.jumpTo(0);
      tester.view.physicalSize = const Size(900, 1500);
      await tester.pump();
      await press('Play journey from home');
      expect(api.researchCalls, 0);
      expect(spoken, isEmpty);
      api.disconnected = true;
      await press('Generate journey stories');
      expect(find.textContaining('Story research was interrupted.'), findsOneWidget);
      expect(api.receivedJourney, isFalse);
      api.disconnected = false;
      await press('Generate journey stories');
      final preparedCalls = api.researchCalls;
      expect(api.receivedJourney, isTrue);
      await press('Play journey from home');
      for (var i = 0; i < 90; i++) {
        await tester.pump(const Duration(milliseconds: 300));
      }
      expect(api.researchCalls, preparedCalls);
      expect(spoken, contains('Museum story.'));
      expect(spoken.where((s) => s == 'Local history: family.'), hasLength(1));
      expect(spoken, isNot(contains('Local history: unreviewed.')));
      spoken.clear();
      await press('Play story');
      expect(spoken, ['Museum story.']);
      expect(find.text('Story finished.'), findsOneWidget);
      await press('Check story gaps');
      await press('Why places were skipped');
      expect(find.text('Old quay'), findsOneWidget);
      expect(find.text('Outside walking corridor'), findsOneWidget);
      expect(find.text('Story gaps along the route'), findsOneWidget);
    },
  );
}
