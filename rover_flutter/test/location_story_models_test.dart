import 'package:flutter_test/flutter_test.dart';
import 'package:rover/src/api/location_story_models.dart';

void main() {
  test('Story Pack 1.1 remains readable without 2.0 metadata', () {
    final response = LocationStoryResponse.fromJson({
      'storyTitle': 'Legacy story',
      'shortSpokenNarration': 'A grounded legacy story.',
      'factIdsUsed': const <String>[],
      'sourceReferences': const <Map<String, dynamic>>[],
      'confidence': 0.8,
      'requiredAttribution': const <String>[],
      'warnings': const <String>[],
      'storyPack': {'schemaVersion': '1.1'},
    });

    expect(response.storyPack?['schemaVersion'], '1.1');
    expect(response.storyPackV2, isNull);
  });

  test('Story Pack 2.0 metadata parses through the existing response', () {
    final response = LocationStoryResponse.fromJson({
      'storyTitle': 'A route story',
      'shortSpokenNarration': 'A grounded route story.',
      'factIdsUsed': const ['evidence-1'],
      'sourceReferences': const <Map<String, dynamic>>[],
      'confidence': 0.9,
      'requiredAttribution': const ['Local archive'],
      'warnings': const <String>[],
      'storyPack': {
        'schemaVersion': '2.0',
        'storyId': 'story:abc',
        'entityId': 'place:westport',
        'geographicAnchor': {
          'latitude': 44.678,
          'longitude': -76.395,
          'routeId': 'walk-1',
          'routeSegmentId': 'segment-2',
          'directionalContext': 'Ahead',
        },
        'primaryCategory': 'LocalHistory',
        'categories': ['LocalHistory', 'Architecture'],
        'interestTags': ['history'],
        'narrationVariants': [
          {
            'variantId': 'story:abc:quick',
            'variantType': 'Quick',
            'sectionType': 'CameraTeaser',
            'targetDurationSeconds': 15,
            'estimatedDurationSeconds': 12,
            'sentenceIds': ['sentence-1'],
            'evidenceIds': ['evidence-1'],
          },
        ],
        'evidenceQualityScore': 0.93,
        'freshnessClassification': 'Evergreen',
        'retrievedUtc': '2026-09-03T12:00:00Z',
        'cacheEligibility': {
          'offlineEligible': true,
          'audioCacheEligible': true,
          'retentionClass': 'evergreen',
          'reason': 'Validated evergreen evidence.',
        },
        'interactionState': {'narrationStatus': 'NotOffered'},
        'followUpPrompts': ['Tell me more about local history.'],
        'relatedStoryPackIds': ['story:related'],
      },
    });

    final metadata = response.storyPackV2;
    expect(metadata, isNotNull);
    expect(metadata!.storyId, 'story:abc');
    expect(metadata.entityId, 'place:westport');
    expect(metadata.geographicAnchor?.routeId, 'walk-1');
    expect(metadata.geographicAnchor?.directionalContext, 'Ahead');
    expect(metadata.categories, ['LocalHistory', 'Architecture']);
    expect(metadata.narrationVariants.single.variantType, 'Quick');
    expect(metadata.narrationVariants.single.evidenceIds, ['evidence-1']);
    expect(metadata.evidenceQualityScore, 0.93);
    expect(metadata.freshnessClassification, 'Evergreen');
    expect(metadata.cacheEligibility?.offlineEligible, isTrue);
    expect(metadata.narrationStatus, 'NotOffered');
    expect(metadata.relatedStoryPackIds, ['story:related']);
  });
}
