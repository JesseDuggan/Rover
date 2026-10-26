import '../location/rover_location.dart';
import 'adaptive_route_story_models.dart';

class StoryQuestionRequest {
  const StoryQuestionRequest({
    required this.question,
    required this.location,
    this.scope = 'Auto',
    this.format = 'Auto',
    this.storyCount,
    this.routeGeometry = const [],
    this.availableNarrationSeconds = 300,
  });

  final String question, scope, format;
  final RoverLatLng location;
  final List<RoverLatLng> routeGeometry;
  final int? storyCount;
  final int availableNarrationSeconds;

  Map<String, Object?> toJson() => {
    'question': question,
    'latitude': location.latitude,
    'longitude': location.longitude,
    'scope': scope,
    'format': format,
    if (storyCount != null) 'storyCount': storyCount,
    'availableNarrationSeconds': availableNarrationSeconds,
    'language': 'en',
    if (routeGeometry.isNotEmpty)
      'routeGeometry': [
        for (final point in routeGeometry)
          {'latitude': point.latitude, 'longitude': point.longitude},
      ],
  };
}

class StoryQuestionResponse {
  const StoryQuestionResponse({
    required this.status,
    required this.scope,
    required this.format,
    required this.answers,
    this.message,
  });

  final String status, scope, format;
  final List<AdaptiveRouteStorySelection> answers;
  final String? message;

  factory StoryQuestionResponse.fromJson(Map<String, dynamic> json) =>
      StoryQuestionResponse(
        status: json['status'] as String? ?? 'failed',
        scope: json['scope'] as String? ?? 'Auto',
        format: json['format'] as String? ?? 'Single',
        message: json['message'] as String?,
        answers: (json['answers'] as List? ?? [])
            .whereType<Map<String, dynamic>>()
            .map(AdaptiveRouteStorySelection.fromJson)
            .toList(),
      );
}
