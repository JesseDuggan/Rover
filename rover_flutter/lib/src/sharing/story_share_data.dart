import '../api/adaptive_route_story_models.dart';

Map<String, dynamic> storyShareData(AdaptiveRouteStory story) {
  final variant =
      story.variants.where((v) => v.length == 'Standard').firstOrNull ??
      story.variants.firstOrNull;
  return {
    'title': story.title,
    'narration': variant?.narration ?? '',
    'notice': [
      if (story.audienceSuitability != 'family')
        'Audience: ${story.audienceSuitability}',
      if (story.sensitivityNotice != null) story.sensitivityNotice!,
      ...story.uncertainClaims,
    ].join('\n'),
    'sources': story.sources
        .map((s) => s.url)
        .whereType<String>()
        .where((url) {
          final uri = Uri.tryParse(url);
          return uri?.scheme == 'https' &&
              uri!.host.isNotEmpty &&
              uri.userInfo.isEmpty;
        })
        .take(20)
        .toList(),
    'location': {'latitude': story.latitude, 'longitude': story.longitude},
  };
}

List<Map<String, dynamic>> storyPackShareData(dynamic pack) {
  if (pack is! Map || pack['stories'] is! List) return [];
  return (pack['stories'] as List)
      .whereType<Map<String, dynamic>>()
      .map(AdaptiveRouteStory.fromJson)
      .map(storyShareData)
      .where((s) => (s['narration'] as String).trim().isNotEmpty)
      .toList();
}
