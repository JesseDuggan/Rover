import 'package:flutter/foundation.dart';

import '../api/adaptive_route_story_models.dart';
import '../location/rover_location.dart';

class AreaStoryCollection {
  const AreaStoryCollection(
    this.status,
    this.stories, {
    this.searchRadiusMeters = 1000,
  });
  final String status;
  final List<AdaptiveRouteStory> stories;
  final int searchRadiusMeters;
  factory AreaStoryCollection.fromJson(Map<String, dynamic> json) =>
      AreaStoryCollection(
        json['status'] as String? ?? 'failed',
        (json['stories'] as List? ?? [])
            .whereType<Map<String, dynamic>>()
            .map(AdaptiveRouteStory.fromJson)
            .toList(),
        searchRadiusMeters: switch (json['searchRadiusMeters']) {
          5000 => 5000,
          20000 => 20000,
          _ => 1000,
        },
      );
}

class AreaWalkingController extends ChangeNotifier {
  AreaWalkingController({
    required this.research,
    required this.narrate,
    required this.cancelResearch,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;
  final Future<AreaStoryCollection> Function(RoverLatLng, List<String>)
  research;
  final Future<bool> Function(AdaptiveRouteStory) narrate;
  final VoidCallback cancelResearch;
  final DateTime Function() _clock;
  final List<AdaptiveRouteStory> stories = [];
  final Set<String> heard = {};
  final Map<String, DateTime> _retryAfter = {};
  RoverLocationReading? reading;
  RoverLatLng? _searchedAt;
  DateTime? _lastResearch;
  DateTime? _lastPlayed;
  bool busy = false, speaking = false, paused = false, _disposed = false;
  bool questionOpen = false;
  int _generation = 0;
  String status = 'Waiting for location';
  String? playingId;
  int searchRadiusMeters = 1000;
  bool _broadenQueued = false;
  RoverLatLng? _coverageOrigin;
  String? coverageMessage;
  final Map<String, int> _storyRadii = {};

  bool isRegional(AdaptiveRouteStory story) =>
      story.isBroaderContext || (_storyRadii[story.storyId] ?? 1000) > 1000;

  String coverageLabel(AdaptiveRouteStory story) => story.isBroaderContext
      ? story.geographicLabel
      : switch (_storyRadii[story.storyId]) {
          5000 => 'Surrounding area - within 5 km of search location',
          20000 => 'Regional context - within 20 km of search location',
          _ => 'Local story',
        };

  bool _fresh(RoverLocationReading r) =>
      r.location.latitude.isFinite &&
      r.location.longitude.isFinite &&
      r.location.latitude.abs() <= 90 &&
      r.location.longitude.abs() <= 180 &&
      r.accuracyMeters != null &&
      r.accuracyMeters!.isFinite &&
      r.accuracyMeters! >= 0 &&
      r.accuracyMeters! <= 40 &&
      _clock().toUtc().difference(r.recordedAtUtc).abs() <=
          const Duration(minutes: 2);

  bool available(AdaptiveRouteStory story) =>
      reading != null &&
      story.expiresUtc?.isAfter(_clock().toUtc()) == true &&
      reading!.location.distanceTo(
            RoverLatLng(
              latitude: story.contextLatitude ?? story.latitude,
              longitude: story.contextLongitude ?? story.longitude,
            ),
          ) <=
          (story.isBroaderContext
              ? 1000
              : (_storyRadii[story.storyId] ?? 1000));

  Future<void> update(
    RoverLocationReading value, {
    bool refresh = false,
  }) async {
    if (_disposed || paused) return;
    if (!_fresh(value)) {
      reading = null;
      status = 'Waiting for an accurate location';
      _notify();
      return;
    }
    reading = value;
    _notify();
    if (busy || speaking) return;
    if (_coverageOrigin != null &&
        value.location.distanceTo(_coverageOrigin!) >= 1000) {
      searchRadiusMeters = 1000;
      _broadenQueued = false;
      coverageMessage = null;
      _coverageOrigin = value.location;
    }
    final now = _clock().toUtc();
    final elapsed = _lastResearch == null
        ? null
        : now.difference(_lastResearch!);
    final moved =
        _searchedAt == null || value.location.distanceTo(_searchedAt!) >= 350;
    final remaining = stories
        .where((s) => available(s) && !heard.contains(s.storyId))
        .length;
    if (elapsed == null ||
        (_broadenQueued && elapsed >= const Duration(seconds: 20)) ||
        (elapsed >= const Duration(minutes: 2) &&
            (refresh ||
                moved ||
                (remaining == 0 && elapsed >= const Duration(minutes: 5))))) {
      busy = true;
      final generation = _generation;
      _lastResearch = now;
      _searchedAt = value.location;
      _coverageOrigin ??= value.location;
      _broadenQueued = false;
      status = searchRadiusMeters == 1000
          ? 'Researching this neighbourhood...'
          : 'Researching the surrounding area within ${searchRadiusMeters ~/ 1000} km...';
      _notify();
      try {
        final result = await research(
          value.location,
          stories.map((s) => s.title).take(120).toList(),
        );
        if (_disposed || generation != _generation) return;
        final titles = stories.map((s) => s.title.trim().toLowerCase()).toSet();
        var added = 0;
        for (final story in result.stories) {
          if (story.sources.isNotEmpty &&
              story.claims.isNotEmpty &&
              story.variants.isNotEmpty &&
              story.variants.any((v) => v.narration.trim().isNotEmpty) &&
              !stories.any((s) => s.storyId == story.storyId) &&
              titles.add(story.title.trim().toLowerCase())) {
            stories.add(story);
            _storyRadii[story.storyId] = result.searchRadiusMeters;
            added++;
          }
        }
        if (stories.length > 120) stories.removeRange(0, stories.length - 120);
        _storyRadii.removeWhere(
          (id, _) => !stories.any((s) => s.storyId == id),
        );
        if (result.status != 'failed' &&
            added < 2 &&
            searchRadiusMeters < 20000) {
          searchRadiusMeters = searchRadiusMeters == 1000 ? 5000 : 20000;
          _broadenQueued = true;
          coverageMessage =
              'We found few new verified stories nearby. We are widening the search to the surrounding area, up to ${searchRadiusMeters ~/ 1000} km. Regional stories are labeled with their wider context.';
        } else if (result.searchRadiusMeters > 1000) {
          coverageMessage =
              'Search includes the surrounding area within ${result.searchRadiusMeters ~/ 1000} km. Regional stories describe their own locations, not necessarily where you are standing.';
        }
        status = result.status == 'failed'
            ? 'Area research could not finish. Try again shortly.'
            : result.stories.isEmpty
            ? 'No new verified stories found in this area.'
            : 'Neighbourhood stories ready';
      } catch (_) {
        if (!_disposed && generation == _generation) {
          status = 'Could not research this area. Check your connection.';
        }
      } finally {
        if (generation == _generation) busy = false;
        _notify();
      }
    }
    await playNext();
  }

  Future<void> playNext() async {
    if (_disposed ||
        questionOpen ||
        paused ||
        busy ||
        speaking ||
        reading == null ||
        !_fresh(reading!)) {
      return;
    }
    final now = _clock().toUtc();
    if (_lastPlayed != null &&
        now.difference(_lastPlayed!) < const Duration(seconds: 20)) {
      return;
    }
    for (final story in stories) {
      if (available(story) &&
          story.canAutoplay &&
          !heard.contains(story.storyId) &&
          !(_retryAfter[story.storyId]?.isAfter(now) ?? false)) {
        await play(story, userRequested: false);
        return;
      }
    }
    if (stories.any(available) &&
        stories.where(available).every((s) => heard.contains(s.storyId))) {
      status = 'You have heard all current stories here. More will be researched as you walk.';
      _notify();
    } else if (stories.any(
      (s) => available(s) && !s.canAutoplay && !heard.contains(s.storyId),
    )) {
      status = 'More stories are available to read or play on request.';
      _notify();
    }
  }

  Future<void> play(
    AdaptiveRouteStory story, {
    bool userRequested = true,
  }) async {
    if (!userRequested && !story.canAutoplay) return;
    if (_disposed ||
        paused ||
        speaking ||
        busy ||
        reading == null ||
        !_fresh(reading!) ||
        !available(story)) {
      return;
    }
    final generation = _generation;
    speaking = true;
    playingId = story.storyId;
    status = 'Playing: ${story.title}';
    _notify();
    try {
      final completed = await narrate(story);
      if (_disposed || generation != _generation) return;
      if (completed) {
        heard.add(story.storyId);
      } else {
        _retryAfter[story.storyId] = _clock().toUtc().add(
          const Duration(minutes: 5),
        );
      }
      status = completed
          ? 'Story finished'
          : 'Story not completed. You can retry it.';
    } catch (_) {
      if (generation == _generation) {
        _retryAfter[story.storyId] = _clock().toUtc().add(
          const Duration(minutes: 5),
        );
        status = 'Could not play this story.';
      }
    } finally {
      if (generation == _generation) {
        speaking = false;
        playingId = null;
        _lastPlayed = _clock().toUtc();
      }
      _notify();
    }
  }

  void setPaused(bool value) {
    _generation++;
    cancelResearch();
    paused = value;
    busy = false;
    speaking = false;
    playingId = null;
    if (!value) _lastResearch = null;
    status = value ? 'Paused' : 'Looking for area stories';
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    cancelResearch();
    super.dispose();
  }
}
