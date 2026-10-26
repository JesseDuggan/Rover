import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rover/src/api/location_story_models.dart';
import 'package:rover/src/location/location_controller.dart';
import 'package:rover/src/ui/tell_here_screen.dart';
import 'package:rover/src/voice/rover_voice_controller.dart';
import 'support/location_fixtures.dart';
import 'voice_controller_test.dart' show FakeVoiceWalkRepository;

class HereRepository extends FakeVoiceWalkRepository {
  LocationStoryRequest? request;
  bool expired = false;
  @override
  Future<LocationStoryResponse> createLocationStory(LocationStoryRequest value) async {
    request = value;
    return LocationStoryResponse.fromJson({
      'storyTitle': 'Here in Nice',
      'shortSpokenNarration': 'A sourced introduction.',
      'tellMeMore': 'A longer sourced account.',
      'factIdsUsed': ['fact'],
      'sourceReferences': [{'sourceUrl': 'https://example.org/history', 'attribution': 'Local archive'}],
      'confidence': 0.9,
      'requiredAttribution': ['Local archive'],
      'warnings': [],
      if (expired) 'expiresUtc': '2000-01-01T00:00:00Z',
    });
  }
}

class HereVoice extends RoverVoiceController {
  HereVoice(HereRepository repository) : super(walkRepository: repository);
  final spoken = <String>[];
  int stops = 0;
  @override
  Future<void> stopAll() async { stops++; }
  @override
  Future<void> stopQuestionAnswer() async { stops++; }
  @override
  Future<bool> playHereNarration(String text) async { spoken.add(text); return true; }
}

void main() {
  for (final expired in [false, true]) {
    testWidgets('Tell here uses a fresh fix and rejects expired evidence $expired', (tester) async {
      final repository = HereRepository()..expired = expired;
      final provider = SimulatedLocationProvider();
      final location = LocationController(realProvider: provider);
      await location.ensureDeviceLocation(forceRefresh: true);
      provider.moveNext();
      final voice = HereVoice(repository);
      await tester.pumpWidget(MaterialApp(home: TellHereScreen(
        voice: voice, repository: repository, location: location,
        interests: const ['history'],
      )));
      await tester.pumpAndSettle();
      expect(repository.request!.location.latitude, provider.current.latitude);
      expect(repository.request!.routeGeometry, isEmpty);
      expect(repository.request!.selectedPlaceIds, isEmpty);
      expect(voice.stops, greaterThan(0));
      if (expired) {
        expect(voice.spoken, isEmpty);
        expect(find.textContaining('No verified introduction'), findsOneWidget);
      } else {
        expect(voice.spoken.single, contains('A sourced introduction.'));
        await tester.tap(find.text('Hear more'));
        await tester.pumpAndSettle();
        expect(voice.spoken.last, contains('A longer sourced account.'));
        expect(find.text('A longer sourced account.'), findsOneWidget);
      }
      await tester.pumpWidget(const SizedBox());
      location.dispose();
      voice.dispose();
    });
  }
}
