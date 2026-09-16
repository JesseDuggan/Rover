import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../api/adaptive_route_story_models.dart';

class QueuedRouteStoryEvent {
  const QueuedRouteStoryEvent({
    required this.walkSessionId,
    required this.request,
  });

  final String walkSessionId;
  final RouteStoryPlaybackEventRequest request;

  Map<String, Object?> toJson() => {
    'walkSessionId': walkSessionId,
    'request': request.toJson(),
  };

  factory QueuedRouteStoryEvent.fromJson(Map<String, dynamic> json) {
    final request = json['request'] as Map<String, dynamic>? ?? const {};
    return QueuedRouteStoryEvent(
      walkSessionId: json['walkSessionId'] as String? ?? '',
      request: RouteStoryPlaybackEventRequest(
        storyId: request['storyId'] as String? ?? '',
        kind: request['kind'] as String? ?? 'Started',
        occurredUtc:
            DateTime.tryParse(request['occurredUtc'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        positionSeconds: (request['positionSeconds'] as num?)?.toInt(),
      ),
    );
  }
}

class AdaptiveRouteStoryDeviceCache extends ChangeNotifier {
  AdaptiveRouteStoryDeviceCache({File? file, DateTime Function()? nowUtc})
    : _file = kIsWeb
          ? null
          : file ??
                File(
                  '${Directory.systemTemp.path}'
                  '${Platform.pathSeparator}rover_adaptive_route_stories.json',
                ),
      _nowUtc = nowUtc ?? (() => DateTime.now().toUtc());

  static final AdaptiveRouteStoryDeviceCache instance =
      AdaptiveRouteStoryDeviceCache();

  final File? _file;
  final DateTime Function() _nowUtc;
  final Map<String, AdaptiveRouteStoryPackState> _states = {};
  final List<QueuedRouteStoryEvent> _events = [];
  Future<void>? _loadFuture;

  int get packCount => _states.length;
  int get queuedEventCount => _events.length;
  int get storyCount => _states.values.fold(
    0,
    (total, state) => total + (state.pack?.stories.length ?? 0),
  );

  Future<void> load() => _loadFuture ??= _load();

  Future<AdaptiveRouteStoryPackState?> get(
    String walkSessionId,
    int routeRevision,
  ) async {
    await load();
    final state = _states[_key(walkSessionId, routeRevision)];
    if (state?.pack == null || state!.pack!.expiresUtc.isBefore(_nowUtc())) {
      if (state != null) {
        _states.remove(_key(walkSessionId, routeRevision));
        await _save();
      }
      return null;
    }
    return state;
  }

  Future<bool> store(AdaptiveRouteStoryPackState state) async {
    await load();
    final pack = state.pack;
    if (pack != null) {
      final permitted = pack.stories
          .where(
            (story) =>
                story.sources.isNotEmpty &&
                story.sources.every((source) => source.canCache),
          )
          .toList();
      if (permitted.length != pack.stories.length) {
        state = AdaptiveRouteStoryPackState.fromJson({
          ...state.toJson(),
          'pack': {
            ...pack.toJson(),
            // The online collection's coverage no longer describes this filtered pack.
            'collection': null,
            'stories': permitted.map((story) => story.toJson()).toList(),
            'warnings': [
              ...pack.warnings,
              'Online-only stories are not downloaded.',
            ],
          },
        });
      }
    }
    if (!_eligible(state)) {
      return false;
    }
    _states[_key(state.walkSessionId, state.routeRevision)] = state;
    while (_states.length > 12) {
      _states.remove(_states.keys.first);
    }
    return _save();
  }

  Future<AdaptiveRouteStorySelection?> select(
    String walkSessionId,
    int routeRevision,
    NextRouteStoryRequest request,
  ) async {
    final state = await get(walkSessionId, routeRevision);
    final excluded = {
      ...state?.heardStoryIds ?? const <String>[],
      ...request.excludedStoryIds,
    };
    final candidates =
        (state?.pack?.stories ?? const <AdaptiveRouteStory>[])
            .where((story) => !excluded.contains(story.storyId))
            .where(
              (story) =>
                  story.expiresUtc == null ||
                  story.expiresUtc!.isAfter(_nowUtc()),
            )
            .where(
              (story) =>
                  request.routeProgressMeters >= story.playbackWindowStart &&
                  request.routeProgressMeters <= story.playbackWindowEnd,
            )
            .toList()
          ..sort((left, right) {
            final window = left.playbackWindowEnd.compareTo(
              right.playbackWindowEnd,
            );
            return window != 0
                ? window
                : right.evidenceScore.compareTo(left.evidenceScore);
          });
    for (final story in candidates) {
      final variant = _variantFor(story, request);
      if (variant != null)
        return AdaptiveRouteStorySelection(
          story: story,
          variant: variant,
          reason: 'Selected from the downloaded route-story pack.',
        );
    }
    return null;
  }

  Future<void> applyEvent(
    String walkSessionId,
    int routeRevision,
    RouteStoryPlaybackEventRequest request, {
    required bool queueForSync,
  }) async {
    await load();
    final key = _key(walkSessionId, routeRevision);
    final state = _states[key];
    if (state != null) {
      final heard = state.heardStoryIds.toSet();
      final saved = state.savedStoryIds.toSet();
      if (const {'Completed', 'Skipped', 'Dismissed'}.contains(request.kind)) {
        heard.add(request.storyId);
      }
      if (request.kind == 'Saved') saved.add(request.storyId);
      _states[key] = AdaptiveRouteStoryPackState(
        walkSessionId: state.walkSessionId,
        routeRevision: state.routeRevision,
        status: state.status,
        updatedUtc: _nowUtc(),
        heardStoryIds: heard.toList(),
        savedStoryIds: saved.toList(),
        pack: state.pack,
        error: state.error,
        lastPlaybackEvent: request.kind,
      );
    }
    if (queueForSync) {
      _events.add(
        QueuedRouteStoryEvent(walkSessionId: walkSessionId, request: request),
      );
    }
    await _save();
  }

  Future<void> flushEvents(
    Future<void> Function(QueuedRouteStoryEvent event) send,
  ) async {
    await load();
    var sent = 0;
    try {
      for (final event in List<QueuedRouteStoryEvent>.from(_events)) {
        await send(event);
        sent++;
      }
    } finally {
      if (sent > 0) {
        _events.removeRange(0, sent);
        await _save();
      }
    }
  }

  bool _eligible(AdaptiveRouteStoryPackState state) {
    final pack = state.pack;
    return pack != null &&
        pack.stories.isNotEmpty &&
        pack.expiresUtc.isAfter(_nowUtc()) &&
        pack.stories.every(
          (story) =>
              story.sources.isNotEmpty &&
              story.sources.every((source) => source.canCache),
        );
  }

  RouteStoryNarrationVariant? _variantFor(
    AdaptiveRouteStory story,
    NextRouteStoryRequest request,
  ) {
    final availableSeconds = request.secondsUntilNextManeuver == null
        ? null
        : request.secondsUntilNextManeuver! - 15;
    final variants =
        story.variants
            .where(
              (variant) =>
                  availableSeconds == null ||
                  variant.estimatedDurationSeconds <= availableSeconds,
            )
            .toList()
          ..sort(
            (left, right) => right.estimatedDurationSeconds.compareTo(
              left.estimatedDurationSeconds,
            ),
          );
    if (variants.isEmpty) return null;
    final preferred = variants.where(
      (variant) => variant.length == request.preferredLength,
    );
    return preferred.isNotEmpty ? preferred.first : variants.first;
  }

  Future<void> _load() async {
    final file = _file;
    if (file == null || !await file.exists()) return;
    try {
      final json =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      for (final item in (json['states'] as List? ?? const [])) {
        final state = AdaptiveRouteStoryPackState.fromJson(
          Map<String, dynamic>.from(item as Map),
        );
        if (_eligible(state)) {
          _states[_key(state.walkSessionId, state.routeRevision)] = state;
        }
      }
      _events.addAll(
        (json['events'] as List? ?? const []).map(
          (item) => QueuedRouteStoryEvent.fromJson(
            Map<String, dynamic>.from(item as Map),
          ),
        ),
      );
    } on Object {
      _states.clear();
      _events.clear();
    }
    notifyListeners();
  }

  Future<bool> _save() async {
    final body = jsonEncode({
      'schemaVersion': 1,
      'states': _states.values.map((state) => state.toJson()).toList(),
      'events': _events.map((event) => event.toJson()).toList(),
    });
    final file = _file;
    if (file == null) {
      notifyListeners();
      return true;
    }
    try {
      await file.parent.create(recursive: true);
      await file.writeAsString(body, flush: true);
      notifyListeners();
      return true;
    } on FileSystemException {
      return false;
    }
  }

  static String _key(String walkSessionId, int routeRevision) =>
      '$walkSessionId:$routeRevision';
}
