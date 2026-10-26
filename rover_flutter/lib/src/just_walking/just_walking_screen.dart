import 'dart:async';

import 'package:flutter/material.dart';

import '../active_roam/active_roam_controller.dart';
import '../active_roam/active_roam_session.dart';
import '../api/walk_repository.dart';
import '../api/adaptive_route_story_models.dart';
import '../api/rover_api_client.dart';
import '../location/rover_location.dart';
import '../location/background_walk_policy.dart';
import '../maps/rover_map_view.dart';
import '../preferences/preferences_controller.dart';
import '../story_questions/story_question_controller.dart';
import '../story_questions/story_question_sheet.dart';
import '../voice/rover_premium_voice.dart';
import '../voice/rover_voice_controller.dart';
import '../voice/rover_voice_state.dart';
import 'area_walking_controller.dart';
import 'area_story_details.dart';
import 'story_images.dart';

class JustWalkingScreen extends StatefulWidget {
  const JustWalkingScreen({super.key});

  @override
  State<JustWalkingScreen> createState() => _JustWalkingScreenState();
}

class _JustWalkingScreenState extends State<JustWalkingScreen>
    with WidgetsBindingObserver {
  final _provider = const GeolocatorLocationProvider(backgroundWalking: true);
  final _repository = HttpWalkRepository();
  late final RoverVoiceController _voice;
  late final AreaWalkingController _walk;
  RoverApiClient? _researchClient;
  Timer? _ticker;
  StreamSubscription<RoverLocationReading>? _subscription;
  bool _starting = false;
  bool _started = false;
  String? _error;
  AdaptiveRouteStory? _picturedStory;
  int _startGeneration = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _voice = RoverVoiceController(
      walkRepository: _repository,
      premiumVoice: RoverPremiumVoiceCoordinator(walkRepository: _repository),
    );
    _walk = AreaWalkingController(
      cancelResearch: () => _researchClient?.close(force: true),
      research: (location, excluded) async {
        final client = RoverApiClient();
        _researchClient = client;
        try {
          return AreaStoryCollection.fromJson(
            await client.researchAreaStories(
              latitude: location.latitude,
              longitude: location.longitude,
              interests: PreferencesScope.of(context).preferences.interests,
              excludedTitles: excluded,
              searchRadiusMeters: _walk.searchRadiusMeters,
            ),
          );
        } finally {
          client.close(force: true);
          if (identical(_researchClient, client)) _researchClient = null;
        }
      },
      narrate: (story) {
        if (mounted) setState(() => _picturedStory = story);
        return _voice.playAreaStory(
          story,
          regionalContext: _walk.isRegional(story),
        );
      },
    );
    _ticker = Timer.periodic(const Duration(seconds: 10), (_) {
      final reading = _walk.reading;
      if (reading != null) unawaited(_walk.update(reading));
    });
  }

  Future<void> _start() async {
    if (_starting) return;
    final session = ActiveRoamScope.of(context).session;
    if (session.status == RoamSessionStatus.active ||
        session.status == RoamSessionStatus.paused) {
      setState(
        () => _error = 'Finish your current walk before starting Just walking.',
      );
      return;
    }
    final generation = ++_startGeneration;
    setState(() {
      _starting = true;
      _error = null;
    });
    try {
      final result = await _provider.getCurrentLocation();
      if (!mounted || generation != _startGeneration) return;
      if (!result.isSuccess) {
        setState(
          () => _error = result.failure?.message ?? 'Location unavailable',
        );
        return;
      }
      await _subscription?.cancel();
      if (!mounted || generation != _startGeneration) return;
      _walk.setPaused(false);
      _subscription = _provider.watchLocation().listen(
        (reading) => unawaited(_walk.update(reading)),
        onError: (Object error) {
          if (!mounted) return;
          _pause();
          setState(
            () => _error = 'Location updates stopped. Check location access and try again.',
          );
        },
      );
      setState(() => _started = true);
    } catch (_) {
      if (mounted && generation == _startGeneration) {
        setState(
          () => _error = 'Could not start location updates. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  void _pause() {
    _startGeneration++;
    _walk.setPaused(true);
    unawaited(_subscription?.cancel());
    _subscription = null;
    unawaited(_voice.stopAll());
  }

  Future<void> _askAboutArea() async {
    _walk.questionOpen = true;
    try {
      await showStoryQuestionSheet(
        context,
        title: 'Ask about this area',
        voice: _voice,
        playbackAllowed: () => mounted && !_walk.paused && !_walk.speaking,
        currentContext: () {
          final reading = _walk.reading;
          if (!mounted || _walk.paused || reading == null) return null;
          return StoryQuestionContext(reading: reading);
        },
      );
    } finally {
      _walk.questionOpen = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (shouldPauseWalking(state)) {
      _pause();
    }
  }

  @override
  void dispose() {
    _startGeneration++;
    _ticker?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_subscription?.cancel());
    _walk.dispose();
    unawaited(_voice.stopAll());
    _voice.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Just walking')),
    body: AnimatedBuilder(
      animation: Listenable.merge([_walk, _voice]),
      builder: (context, _) => ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (_walk.reading != null)
            RoverMapView(
              currentLocation: _walk.reading!.location,
              currentHeadingDegrees: _walk.reading!.headingDegrees,
              orderedStops: const [],
              routeGeometry: const [],
              height: 300,
            ),
          const SizedBox(height: 16),
          Semantics(
            liveRegion: true,
            child: Text(
              _error ??
                  (_voice.state == RoverAudioState.thinking
                      ? 'Researching a nearby story...'
                      : _walk.status),
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _starting
                ? null
                : !_started || _walk.paused
                ? _start
                : _pause,
            icon: Icon(
              !_started || _walk.paused ? Icons.play_arrow : Icons.pause,
            ),
            label: Text(
              _starting
                  ? 'Locating...'
                  : !_started
                  ? 'Start listening'
                  : _walk.paused
                  ? 'Resume walking'
                  : 'Pause',
            ),
          ),
          if (_walk.busy || _voice.state == RoverAudioState.thinking)
            const LinearProgressIndicator(),
          OutlinedButton.icon(
            onPressed: _askAboutArea,
            icon: const Icon(Icons.question_answer_outlined),
            label: const Text('Ask about this area'),
          ),
          if (_walk.coverageMessage != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(_walk.coverageMessage!),
            ),
          if (_voice.captionText.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text(_voice.captionText),
          ],
          if (_picturedStory case final story?)
            StoryImages(
              key: ValueKey('images-${story.storyId}'),
              sourceUrls: story.sources
                  .map((s) => s.url)
                  .whereType<String>()
                  .toList(),
            ),
          if (_voice.errorMessage != null) Text(_voice.errorMessage!),
          const SizedBox(height: 20),
          for (final story in _walk.stories)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('${_walk.coverageLabel(story)}\n${story.title}'),
              onTap: () => showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * 0.8,
                ),
                builder: (_) => AreaStoryDetails(
                  story: story,
                  coverageLabel: _walk.coverageLabel(story),
                ),
              ),
              subtitle: Text(
                _walk.heard.contains(story.storyId)
                    ? 'Heard'
                    : _walk.playingId == story.storyId
                    ? 'Playing'
                    : _walk.available(story)
                    ? story.canAutoplay
                          ? 'Ready to listen'
                          : story.sensitivityNotice ?? 'Listen on request'
                    : 'Outside current area or expired',
              ),
              trailing: IconButton(
                tooltip: _walk.heard.contains(story.storyId)
                    ? 'Replay story'
                    : 'Play story',
                icon: Icon(
                  _walk.heard.contains(story.storyId)
                      ? Icons.replay
                      : Icons.play_arrow,
                ),
                onPressed:
                    _walk.paused ||
                        _walk.busy ||
                        _walk.speaking ||
                        !_walk.available(story)
                    ? null
                    : () => _walk.play(story),
              ),
            ),
        ],
      ),
    ),
  );
}
