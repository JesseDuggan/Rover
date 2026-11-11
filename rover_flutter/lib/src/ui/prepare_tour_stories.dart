import '../api/rover_api_client.dart';
import 'prepared_walk_screen.dart';

/// Research once before opening playback. Playback, pause, skip and resume use
/// the prepared results and never call this function again.
Future<PreparedWalk> prepareTourStories(
  RoverApiClient api,
  PreparedWalk walk, {
  required List<String> interests,
  required String depth,
  required void Function(int done, int total) onProgress,
}) async {
  final stops = List<PreparedStop>.of(walk.stops);
  var next = 0, completed = 0;
  Future<void> worker() async {
    while (next < stops.length) {
      final index = next++;
      final stop = stops[index];
      try {
        final result = await api.preparePlaceStory(
          name: stop.name,
          latitude: stop.point.latitude,
          longitude: stop.point.longitude,
          interests: interests,
          contentDepth: depth,
        );
        if (result.researchStatus == 'ready' &&
            result.factIdsUsed.isNotEmpty &&
            result.shortSpokenNarration.trim().isNotEmpty &&
            result.sourceReferences.isNotEmpty) {
          stops[index] = PreparedStop(
            stop.name,
            stop.point,
            WalkAnswer(result.shortSpokenNarration, {
              for (final source in result.sourceReferences)
                if (source.sourceUrl != null)
                  source.sourceTitle ?? source.providerName: source.sourceUrl!,
            }),
            optional: stop.optional,
            photo: stop.photo,
            pictures: stop.pictures,
          );
        }
      } on Exception {
        // The reviewed, interest-selected editorial chapter remains available.
        // Failure must not replace it with a research error or empty narration.
      }
      onProgress(++completed, stops.length);
    }
  }

  await Future.wait([worker(), worker()]);
  return PreparedWalk(
    walk.title,
    walk.path,
    stops,
    theme: walk.theme,
    orderedChapters: walk.orderedChapters,
  );
}
