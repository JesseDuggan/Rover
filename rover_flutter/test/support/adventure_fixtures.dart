import 'package:rover/src/adventure/adventure_request.dart';

class MockAdventureSuggestion {
  const MockAdventureSuggestion({
    required this.title,
    required this.description,
    required this.minutes,
  });

  final String title;
  final String description;
  final int minutes;
}

List<MockAdventureSuggestion> createMockSuggestions(AdventureRequest request) {
  final theme = request.surpriseMe
      ? 'surprise'
      : request.interests.isEmpty
      ? 'local'
      : request.interests.first.toLowerCase();
  final minutes = request.availableMinutes;

  return [
    MockAdventureSuggestion(
      title: 'Warm-up stop',
      description: 'A nearby $theme spot that eases you into the ROAM.',
      minutes: (minutes * 0.25).round(),
    ),
    MockAdventureSuggestion(
      title: 'Main wander',
      description:
          'A ${request.pace.toLowerCase()} stretch tuned for ${request.companions.toLowerCase()}.',
      minutes: (minutes * 0.5).round(),
    ),
    MockAdventureSuggestion(
      title: 'Soft landing',
      description:
          'A final ${request.environment.toLowerCase()} stop before heading on.',
      minutes: (minutes * 0.25).round(),
    ),
  ];
}
