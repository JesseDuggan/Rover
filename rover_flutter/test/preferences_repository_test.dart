import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rover/src/preferences/preferences_repository.dart';
import 'package:rover/src/preferences/rover_preferences.dart';
import 'package:rover/src/api/journey_narration_models.dart';
import 'package:rover/src/location/rover_location.dart';

void main() {
  test('memory repository saves, loads, and resets preferences', () async {
    final repository = MemoryPreferencesRepository();
    const preferences = RoverPreferences(
      firstName: 'Riley',
      interests: ['food', 'hidden gems'],
      walkingPace: 'steady',
      completedOnboarding: true,
      storyDensity: 'Story-Rich',
      excludedStoryCategories: ['weather'],
      developmentApiBaseUrl: 'http://10.23.45.67:5080',
    );

    await repository.save(preferences);
    expect(await repository.load(), isA<RoverPreferences>());
    expect((await repository.load()).firstName, 'Riley');
    expect((await repository.load()).interests, ['food', 'hidden gems']);
    expect((await repository.load()).storyDensity, 'Story-Rich');
    expect((await repository.load()).excludedStoryCategories, ['weather']);
    expect(
      (await repository.load()).developmentApiBaseUrl,
      'http://10.23.45.67:5080',
    );

    await repository.reset();
    expect((await repository.load()).completedOnboarding, isFalse);
  });

  test('file repository persists preferences across instances', () async {
    final directory = await Directory.systemTemp.createTemp('rover_test_');
    final file = File('${directory.path}${Platform.pathSeparator}prefs.json');
    final firstRepository = FilePreferencesRepository(file: file);
    final secondRepository = FilePreferencesRepository(file: file);

    addTearDown(() async {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    });

    await firstRepository.save(
      const RoverPreferences(
        firstName: 'Jesse',
        interests: ['art'],
        language: 'English',
        completedOnboarding: true,
        developmentApiBaseUrl: 'http://10.23.45.67:5080',
      ),
    );

    final loaded = await secondRepository.load();
    expect(loaded.firstName, 'Jesse');
    expect(loaded.interests, ['art']);
    expect(loaded.language, 'English');
    expect(loaded.completedOnboarding, isTrue);
    expect(loaded.developmentApiBaseUrl, 'http://10.23.45.67:5080');

    await secondRepository.reset();
    expect((await firstRepository.load()).firstName, isEmpty);
  });

  test('older local preferences default to Highlights', () {
    final preferences = RoverPreferences.fromJson('{"firstName":"Jesse"}');

    expect(preferences.storyDensity, 'Highlights');
    expect(preferences.excludedStoryCategories, isEmpty);
  });

  test('journey evaluation carries live story preferences', () {
    final json = JourneyNarrationEvaluateRequest(
      location: const RoverLatLng(latitude: 44.678, longitude: -76.395),
      storyDensity: 'story-rich',
      preferredStoryCategories: const ['history'],
      excludedStoryCategories: const ['weather'],
    ).toJson();

    expect(json['storyDensity'], 'story-rich');
    expect(json['preferredStoryCategories'], ['history']);
    expect(json['excludedStoryCategories'], ['weather']);
  });
}
