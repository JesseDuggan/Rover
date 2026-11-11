import '../api/rover_api_client.dart';
import '../api/story_question_models.dart';
import '../location/rover_location.dart';
import 'prepared_walk_screen.dart';

Future<WalkAnswer?> askTourQuestion(
  RoverApiClient api,
  PreparedStop stop,
  String question,
) async {
  final result = await api.researchStoryQuestion(
    StoryQuestionRequest(
      location: RoverLatLng(
        latitude: stop.point.latitude,
        longitude: stop.point.longitude,
      ),
      question:
          'At ${stop.name}, the walker asks: $question. Verify the answer for this specific place.',
      scope: 'Street',
      format: 'Single',
      storyCount: 1,
    ),
  );
  final answer = result.answers
      .where(
        (a) =>
            a.story.canAutoplay &&
            a.story.sources.isNotEmpty &&
            a.variant.narration.trim().isNotEmpty,
      )
      .firstOrNull;
  if (answer == null) return null;
  return WalkAnswer(answer.variant.narration, {
    for (final source in answer.story.sources)
      if (source.url != null) source.title ?? source.providerName: source.url!,
  });
}
