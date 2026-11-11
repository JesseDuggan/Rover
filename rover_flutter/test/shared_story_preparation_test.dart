import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:rover/src/api/rover_api_client.dart';
import 'package:rover/src/api/location_story_models.dart';
import 'package:rover/src/preferences/rover_preferences.dart';
import 'package:rover/src/preferences/story_preparation_preferences.dart';
import 'package:rover/src/ui/prepare_tour_stories.dart';
import 'package:rover/src/ui/prepared_walk_screen.dart';

class ResearchApi extends RoverApiClient {
  final requests = <String>[];
  @override
  Future<LocationStoryResponse> preparePlaceStory({
    required String name,
    required double latitude,
    required double longitude,
    required List<String> interests,
    required String contentDepth,
  }) async {
    requests.add('$name|${interests.join(",")}|$contentDepth');
    if (name == 'unavailable') throw Exception('Network unavailable');
    return const LocationStoryResponse(
      storyTitle: 'Prepared',
      shortSpokenNarration: 'Verified deeper account',
      factIdsUsed: ['claim'],
      sourceReferences: [
        LocationSourceReference(
          providerName: 'Archive',
          attribution: 'Archive',
          sourceUrl: 'https://example.org/record',
        ),
      ],
      confidence: .9,
      requiredAttribution: ['Archive'],
      warnings: [],
      researchStatus: 'ready',
    );
  }
}

void main() {
  tearDown(
    () => StoryPreparationPreferences.current = const RoverPreferences(),
  );
  test(
    'all research callers inherit depth but journey interests take precedence',
    () {
      StoryPreparationPreferences.current = const RoverPreferences(
        interests: ['history'],
        contentDepth: 'Deeper stories',
      );
      final request = StoryPreparationPreferences.apply({
        'interests': ['nature'],
      });
      expect(request['interests'], ['nature']);
      expect(request['contentDepth'], 'Deeper stories');
      expect(StoryPreparationPreferences.apply({})['interests'], ['history']);
    },
  );
  test('tour preparation preserves route and reviewed fallback on research failure', () async {
    final api = ResearchApi();
    addTearDown(api.close);
    const point = LatLng(44.9008, -76.2493);
    const reviewed = WalkAnswer('Reviewed chapter', {
      'Archive': 'https://example.org/reviewed',
    });
    const walk = PreparedWalk(
      'Perth comparison',
      [point],
      [
        PreparedStop('available', point, reviewed),
        PreparedStop('unavailable', point, reviewed, optional: true),
      ],
      orderedChapters: true,
    );
    final result = await prepareTourStories(
      api,
      walk,
      interests: ['architecture'],
      depth: 'Deeper stories',
      onProgress: (_, _) {},
    );
    expect(api.requests.length, 2);
    expect(
      api.requests.every((r) => r.endsWith('|architecture|Deeper stories')),
      isTrue,
    );
    expect(result.path, walk.path);
    expect(result.orderedChapters, isTrue);
    expect(result.stops.first.story.text, 'Verified deeper account');
    expect(result.stops.last.story.text, 'Reviewed chapter');
    expect(result.stops.last.optional, isTrue);
    expect(
      result.stops.first.story.sources.values,
      contains('https://example.org/record'),
    );
  });
}
