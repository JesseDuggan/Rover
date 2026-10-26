import '../api/adaptive_route_story_models.dart';
import '../location/rover_location.dart';
import 'memory_store.dart';

class ReplayFix {
  const ReplayFix(this.at, this.location);
  final DateTime at;
  final RoverLatLng location;
}

class ReplayEvent {
  const ReplayEvent({required this.seconds, this.memory, this.story});
  final double seconds;
  final WalkMemory? memory;
  final AdaptiveRouteStory? story;
  String get title =>
      story?.title ??
      (memory!.details.caption.isNotEmpty
          ? memory!.details.caption
          : memory!.isVideo
          ? 'Video memory'
          : 'Photo memory');
}

class ReplaySegment {
  ReplaySegment(this.fixes);
  final List<ReplayFix> fixes;
  double get duration =>
      fixes.last.at.difference(fixes.first.at).inMilliseconds / 1000;
  RoverLatLng position(double seconds) {
    if (seconds <= 0) return fixes.first.location;
    for (var i = 1; i < fixes.length; i++) {
      final end = fixes[i].at.difference(fixes.first.at).inMilliseconds / 1000;
      if (end < seconds) continue;
      final start =
          fixes[i - 1].at.difference(fixes.first.at).inMilliseconds / 1000;
      final fraction = ((seconds - start) / (end - start)).clamp(0.0, 1.0);
      final a = fixes[i - 1].location;
      final b = fixes[i].location;
      return RoverLatLng(
        latitude: a.latitude + (b.latitude - a.latitude) * fraction,
        longitude: a.longitude + (b.longitude - a.longitude) * fraction,
      );
    }
    return fixes.last.location;
  }
}

// A restart, pause, or invalid fix must never become a straight line across a gap.
List<ReplaySegment> replaySegments(List<Map<String, dynamic>> rows) {
  final result = <ReplaySegment>[];
  var fixes = <ReplayFix>[];
  String? previousKey;
  void finish() {
    if (fixes.isNotEmpty) result.add(ReplaySegment(fixes));
    fixes = [];
  }

  for (final row in rows) {
    final key = '${row['recordingId'] ?? ''}/${row['segment']}';
    if (key != previousKey) finish();
    previousKey = key;
    final at = DateTime.tryParse(
      row['at'] is String ? row['at'] as String : '',
    );
    final lat = row['latitude'];
    final lng = row['longitude'];
    if (at == null ||
        lat is! num ||
        lng is! num ||
        !lat.isFinite ||
        !lng.isFinite ||
        lat.abs() > 90 ||
        lng.abs() > 180) {
      finish();
      continue;
    }
    final location = RoverLatLng(
      latitude: lat.toDouble(),
      longitude: lng.toDouble(),
    );
    if (fixes.isNotEmpty) {
      final elapsed = at.difference(fixes.last.at).inMilliseconds / 1000;
      if (elapsed <= 0 ||
          elapsed > 60 ||
          fixes.last.location.distanceTo(location) / elapsed > 8) {
        finish();
      }
    }
    fixes.add(ReplayFix(at, location));
  }
  finish();
  result.sort((a, b) => a.fixes.first.at.compareTo(b.fixes.first.at));
  return result;
}

List<ReplayEvent> replayEvents(
  ReplaySegment segment,
  List<WalkMemory> memories,
  List<AdaptiveRouteStory> stories, {
  List<ReplaySegment>? sections,
}) {
  final result = <ReplayEvent>[];
  for (final memory in memories) {
    final at = memory.details.capturedAt;
    final location = memory.details.location;
    if (at == null || location == null) continue;
    ReplaySegment? nearest;
    var bestGap = double.infinity;
    var bestSeconds = 0.0;
    // Camera capture can pause GPS. Attach once to a nearby recorded section,
    // without extending its geometry or claiming the missing GPS was recorded.
    for (final candidate in sections ?? [segment]) {
      final offset =
          at.difference(candidate.fixes.first.at).inMilliseconds / 1000;
      final seconds = offset.clamp(0.0, candidate.duration);
      final gap = (offset - seconds).abs();
      if (gap <= 180 &&
          gap < bestGap &&
          candidate.position(seconds).distanceTo(location) <= 75) {
        nearest = candidate;
        bestGap = gap;
        bestSeconds = seconds;
      }
    }
    if (identical(nearest, segment)) {
      result.add(ReplayEvent(seconds: bestSeconds, memory: memory));
    }
  }
  for (final story in stories) {
    if (story.variants.isEmpty) continue;
    final anchor = RoverLatLng(
      latitude: story.relevanceLatitude,
      longitude: story.relevanceLongitude,
    );
    if (!anchor.latitude.isFinite || !anchor.longitude.isFinite) continue;
    ReplayFix? nearest;
    var distance = 100.0;
    for (final fix in segment.fixes) {
      final d = fix.location.distanceTo(anchor);
      if (d < distance) {
        nearest = fix;
        distance = d;
      }
    }
    if (nearest != null) {
      result.add(
        ReplayEvent(
          seconds:
              nearest.at.difference(segment.fixes.first.at).inMilliseconds /
              1000,
          story: story,
        ),
      );
    }
  }
  result.sort((a, b) => a.seconds.compareTo(b.seconds));
  return result;
}
