import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../active_roam/active_roam_controller.dart';
import '../active_roam/active_roam_session.dart';
import '../api/adaptive_route_story_models.dart';
import '../maps/rover_map_view.dart';
import '../sharing/shared_video_player.dart';
import '../voice/rover_audio_services.dart';
import 'memory_store.dart';
import 'walk_replay.dart';
import 'walk_trail_store.dart';

class WalkReplayScreen extends StatefulWidget {
  const WalkReplayScreen({
    super.key,
    required this.journey,
    this.stories = const [],
    this.memoryStore,
    this.trailStore,
    this.sharedRows,
    this.sharedMemories,
    this.eventBuilder,
  });
  final MemoryJourney journey;
  final List<AdaptiveRouteStory> stories;
  final MemoryStore? memoryStore;
  final WalkTrailStore? trailStore;
  final List<Map<String, dynamic>>? sharedRows;
  final List<WalkMemory>? sharedMemories;
  final Widget Function(ReplayEvent event)? eventBuilder;
  @override
  State<WalkReplayScreen> createState() => _WalkReplayScreenState();
}

class _WalkReplayScreenState extends State<WalkReplayScreen>
    with WidgetsBindingObserver {
  List<ReplaySegment> segments = [];
  List<WalkMemory> memories = [];
  List<ReplayEvent> events = [];
  final Set<int> seen = {};
  final Set<String> replayedStories = {};
  int segmentIndex = 0;
  double seconds = 0;
  double speed = 5;
  bool loading = true;
  bool playing = false;
  bool foreground = true;
  bool showingMedia = false;
  String? error;
  Timer? timer;
  final elapsed = Stopwatch();
  ReplaySegment? get segment =>
      segments.isEmpty ? null : segments[segmentIndex];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    load();
  }

  Future<void> load() async {
    try {
      if (widget.sharedRows != null) {
        segments = replaySegments(widget.sharedRows!);
        memories = widget.sharedMemories ?? [];
        if (segments.isNotEmpty) selectSegment(0);
        return;
      }
      final store = widget.memoryStore ?? MemoryStore();
      final trail = widget.trailStore ?? WalkTrailStore(memoryStore: store);
      final id = await store.journeyId(widget.journey.id);
      final rows = await trail.readJourney(id);
      final all = await store.list();
      if (!mounted) return;
      segments = replaySegments(rows);
      memories = all.where((m) => m.details.journey?.id == id).toList();
      if (segments.isNotEmpty) selectSegment(0);
    } catch (_) {
      error = 'Could not load this replay. Please try again.';
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  void pause() {
    timer?.cancel();
    timer = null;
    elapsed.stop();
    if (mounted) setState(() => playing = false);
  }

  bool canPlay() {
    final active = context
        .getInheritedWidgetOfExactType<ActiveRoamScope>()
        ?.notifier;
    if (active?.session.status == RoamSessionStatus.active) {
      setState(() => error = 'Pause your live walk before starting replay.');
      return false;
    }
    return foreground && !showingMedia;
  }

  void play({bool restart = true}) {
    if (segment == null || !canPlay()) return;
    if (seconds >= segment!.duration && seen.length == events.length) {
      if (!restart) {
        finishSection();
        return;
      }
      selectSegment(0);
    }
    setState(() {
      playing = true;
      error = null;
    });
    elapsed
      ..reset()
      ..start();
    timer?.cancel();
    timer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      final delta = elapsed.elapsedMilliseconds / 1000 * speed;
      elapsed.reset();
      advance((seconds + delta).clamp(0.0, segment!.duration));
    });
  }

  void advance(double target) {
    for (var i = 0; i < events.length; i++) {
      if (!seen.contains(i) && events[i].seconds <= target) {
        setState(() => seconds = events[i].seconds);
        unawaited(openEvent(i));
        return;
      }
    }
    setState(() => seconds = target);
    if (seconds >= segment!.duration) finishSection();
  }

  void finishSection() {
    pause();
    if (segmentIndex + 1 < segments.length) {
      selectSegment(segmentIndex + 1, automatic: true);
      play();
    }
  }

  Future<void> openEvent(int index) async {
    if (!canPlay()) return;
    pause();
    seen.add(index);
    final story = events[index].story;
    if (story != null) replayedStories.add(story.storyId);
    showingMedia = true;
    // Commit the paused timeline and button state before opening another route.
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    if (!foreground) {
      showingMedia = false;
      seen.remove(index);
      if (story != null) replayedStories.remove(story.storyId);
      return;
    }
    final resume = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) =>
            widget.eventBuilder?.call(events[index]) ??
            ReplayMediaScreen(event: events[index]),
      ),
    );
    if (!mounted) return;
    showingMedia = false;
    if (resume == true && foreground) play(restart: false);
  }

  void selectSegment(int index, {bool automatic = false}) {
    pause();
    setState(() {
      if (!automatic) replayedStories.clear();
      segmentIndex = index;
      seconds = 0;
      seen.clear();
      events = replayEvents(
        segments[index],
        memories,
        widget.stories
            .where((s) => !replayedStories.contains(s.storyId))
            .toList(),
        sections: segments,
      );
    });
  }

  void seek(double value) {
    pause();
    setState(() {
      seconds = value;
      seen.clear();
      for (var i = 0; i < events.length; i++) {
        if (events[i].seconds < value) seen.add(i);
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
    if (!foreground) pause();
  }

  @override
  void dispose() {
    timer?.cancel();
    elapsed.stop();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  static String clock(double seconds) {
    final value = seconds.floor();
    return '${value ~/ 60}:${(value % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final current = segment;
    return Scaffold(
      appBar: AppBar(title: const Text('Walk replay')),
      body: SafeArea(
        child: Column(
          children: [
            if (loading) const LinearProgressIndicator(),
            ListTile(
              leading: const Icon(Icons.lock_outline),
              title: Text(
                current == null
                    ? 'Planned-route preview'
                    : 'Recorded GPS replay',
              ),
              subtitle: Text(
                error ??
                    (current == null
                        ? 'No GPS recording on this device. This is the planned route, not the path walked.'
                        : widget.sharedRows == null
                        ? 'Private on this device'
                        : 'GPS path shared by the walker'),
              ),
              trailing: error == null
                  ? null
                  : IconButton(
                      tooltip: 'Retry replay',
                      onPressed: () {
                        setState(() {
                          loading = true;
                          error = null;
                        });
                        load();
                      },
                      icon: const Icon(Icons.refresh),
                    ),
            ),
            if (segments.length > 1)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: DropdownButtonFormField<int>(
                  key: ValueKey(segmentIndex),
                  initialValue: segmentIndex,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Recorded section',
                  ),
                  items: [
                    for (var i = 0; i < segments.length; i++)
                      DropdownMenuItem(
                        value: i,
                        child: Text(
                          '${i + 1} - ${segments[i].fixes.first.at.toLocal().toString().substring(0, 16)}',
                        ),
                      ),
                  ],
                  onChanged: showingMedia
                      ? null
                      : (i) {
                          if (i != null) selectSegment(i);
                        },
                ),
              ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, box) => RoverMapView(
                  key: ValueKey(segmentIndex),
                  currentLocation: current?.position(seconds),
                  routeGeometry:
                      current?.fixes.map((p) => p.location).toList() ??
                      widget.journey.route.routeGeometry,
                  orderedStops: const [],
                  overview: true,
                  enableExpand: false,
                  height: box.maxHeight,
                ),
              ),
            ),
            if (current != null) ...[
              Slider(
                value: seconds.clamp(0, math.max(1, current.duration)),
                max: math.max(1, current.duration),
                label: clock(seconds),
                onChanged: showingMedia ? null : seek,
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Wrap(
                  alignment: WrapAlignment.spaceEvenly,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  children: [
                    Text('${clock(seconds)} / ${clock(current.duration)}'),
                    DropdownButton<double>(
                      value: speed,
                      items: [
                        for (final s in [1.0, 5.0, 20.0])
                          DropdownMenuItem(
                            value: s,
                            child: Text('${s.toInt()}x'),
                          ),
                      ],
                      onChanged: (value) {
                        if (value != null) setState(() => speed = value);
                      },
                    ),
                    IconButton(
                      tooltip: 'Restart replay',
                      onPressed: () => selectSegment(0),
                      icon: const Icon(Icons.replay),
                    ),
                    IconButton(
                      tooltip: playing ? 'Pause replay' : 'Play replay',
                      onPressed: playing ? pause : play,
                      icon: Icon(playing ? Icons.pause : Icons.play_arrow),
                    ),
                    IconButton(
                      tooltip: 'Next memory or story',
                      onPressed:
                          events.asMap().keys.any((i) => !seen.contains(i))
                          ? () {
                              final i = events.asMap().keys.firstWhere(
                                (i) => !seen.contains(i),
                              );
                              setState(() => seconds = events[i].seconds);
                              openEvent(i);
                            }
                          : null,
                      icon: const Icon(Icons.skip_next),
                    ),
                  ],
                ),
              ),
            ],
            if (memories.isNotEmpty || widget.stories.isNotEmpty)
              SizedBox(
                height: 110,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final memory in memories)
                        SizedBox(
                          width: 210,
                          child: ListTile(
                            leading: Icon(
                              memory.isVideo
                                  ? Icons.videocam_outlined
                                  : Icons.photo_outlined,
                            ),
                            title: Text(
                              memory.details.caption.isEmpty
                                  ? 'Memory'
                                  : memory.details.caption,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            onTap: () async {
                              if (!canPlay()) return;
                              pause();
                              showingMedia = true;
                              await WidgetsBinding.instance.endOfFrame;
                              if (!mounted || !context.mounted) return;
                              if (!foreground) {
                                showingMedia = false;
                                return;
                              }
                              await Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) =>
                                      widget.eventBuilder?.call(
                                        ReplayEvent(seconds: 0, memory: memory),
                                      ) ??
                                      ReplayMediaScreen(
                                        event: ReplayEvent(
                                          seconds: 0,
                                          memory: memory,
                                        ),
                                      ),
                                ),
                              );
                              if (mounted) setState(() => showingMedia = false);
                            },
                          ),
                        ),
                      for (final story in widget.stories)
                        SizedBox(
                          width: 210,
                          child: ListTile(
                            leading: const Icon(Icons.menu_book_outlined),
                            title: Text(
                              story.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            onTap: () async {
                              if (!canPlay()) return;
                              pause();
                              showingMedia = true;
                              await WidgetsBinding.instance.endOfFrame;
                              if (!mounted || !context.mounted) return;
                              if (!foreground) {
                                showingMedia = false;
                                return;
                              }
                              await Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) =>
                                      widget.eventBuilder?.call(
                                        ReplayEvent(seconds: 0, story: story),
                                      ) ??
                                      ReplayMediaScreen(
                                        event: ReplayEvent(
                                          seconds: 0,
                                          story: story,
                                        ),
                                      ),
                                ),
                              );
                              if (mounted) setState(() => showingMedia = false);
                            },
                          ),
                        ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class ReplayMediaScreen extends StatefulWidget {
  const ReplayMediaScreen({super.key, required this.event, this.speech});
  final ReplayEvent event;
  final RoverTextToSpeech? speech;
  @override
  State<ReplayMediaScreen> createState() => _ReplayMediaScreenState();
}

class _ReplayMediaScreenState extends State<ReplayMediaScreen>
    with WidgetsBindingObserver {
  VideoPlayerController? video;
  late final speech = widget.speech ?? DeviceTextToSpeech();
  bool foreground = true;
  bool speaking = false;
  bool usedSpeech = false;
  int generation = 0;
  String? error;
  String get narration {
    final story = widget.event.story;
    if (story == null || story.variants.isEmpty) return '';
    final standard = story.variants.where((v) => v.length == 'Standard');
    return story.spokenNarration(
      standard.isEmpty ? story.variants.first : standard.first,
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    initialize();
  }

  Future<void> initialize() async {
    final memory = widget.event.memory;
    if (memory?.isVideo == true) {
      final controller = VideoPlayerController.file(memory!.file);
      video = controller;
      try {
        await controller.initialize();
        if (!mounted) return;
        setState(() {});
        if (foreground) await controller.play();
      } catch (_) {
        if (mounted) {
          setState(
            () => error = 'This video could not be opened. You can skip it.',
          );
        }
      }
    } else if (widget.event.story?.canAutoplay == true) {
      await speak();
    }
  }

  Future<void> stop() async {
    generation++;
    if (usedSpeech) {
      try {
        await speech.stop();
      } catch (_) {}
    }
    if (mounted) setState(() => speaking = false);
  }

  Future<void> toggleVideo() async {
    final controller = video;
    if (controller == null || !foreground) return;
    try {
      if (controller.value.isPlaying) {
        await controller.pause();
      } else {
        if (controller.value.position >= controller.value.duration) {
          await controller.seekTo(Duration.zero);
        }
        if (mounted && foreground) await controller.play();
      }
    } catch (_) {
      if (mounted) {
        setState(() => error = 'Video playback failed. You can skip it.');
      }
    }
  }

  Future<void> speak() async {
    await stop();
    if (!mounted || !foreground || narration.isEmpty) return;
    final token = ++generation;
    usedSpeech = true;
    setState(() {
      speaking = true;
      error = null;
    });
    try {
      await speech.configure(rate: 0.48);
      var text = narration;
      while (text.isNotEmpty && mounted && foreground && token == generation) {
        var end = math.min(3000, text.length);
        if (end < text.length) {
          final space = text.lastIndexOf(' ', end);
          if (space > 0) end = space;
        }
        await speech.speak(text.substring(0, end));
        text = text.substring(end).trimLeft();
      }
    } catch (_) {
      if (mounted && token == generation) {
        setState(
          () => error = 'Narration unavailable. You can read the story below.',
        );
      }
    } finally {
      if (mounted && token == generation) setState(() => speaking = false);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
    if (!foreground) {
      video?.pause();
      unawaited(stop());
    }
  }

  @override
  void dispose() {
    generation++;
    WidgetsBinding.instance.removeObserver(this);
    video?.dispose();
    if (usedSpeech) unawaited(speech.stop().catchError((Object _) {}));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final memory = widget.event.memory;
    final story = widget.event.story;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.event.title),
        actions: [
          IconButton(
            tooltip: 'Close replay media',
            onPressed: () => Navigator.pop(context, false),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (error != null)
              Padding(padding: const EdgeInsets.all(16), child: Text(error!)),
            Expanded(
              child: story != null
                  ? ListView(
                      padding: const EdgeInsets.all(20),
                      children: [
                        const Text('Saved story'),
                        if (story.sensitivityNotice?.isNotEmpty == true)
                          Text(story.sensitivityNotice!),
                        IconButton(
                          tooltip: speaking
                              ? 'Stop narration'
                              : 'Play narration',
                          onPressed: speaking ? stop : speak,
                          icon: Icon(speaking ? Icons.stop : Icons.volume_up),
                        ),
                        Text(
                          narration.isEmpty
                              ? 'No saved narration available.'
                              : narration,
                        ),
                        for (final source in story.sources)
                          ListTile(
                            title: Text(source.title ?? source.providerName),
                            subtitle: Text(
                              [
                                source.attribution,
                                source.url ?? '',
                              ].where((s) => s.isNotEmpty).join('\n'),
                            ),
                          ),
                      ],
                    )
                  : memory!.isVideo
                  ? video?.value.isInitialized == true
                        ? SharedVideoPlayer(
                            controller: video!,
                            enabled: foreground,
                            onToggle: toggleVideo,
                          )
                        : Center(
                            child: error == null
                                ? const CircularProgressIndicator()
                                : const Icon(Icons.broken_image_outlined),
                          )
                  : Image.file(
                      memory.file,
                      fit: BoxFit.contain,
                      errorBuilder: (_, _, _) =>
                          const Center(child: Text('Photo unavailable.')),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: FilledButton.icon(
                onPressed: () async {
                  try {
                    await video?.pause();
                  } catch (_) {}
                  await stop();
                  usedSpeech = false;
                  if (context.mounted) Navigator.pop(context, true);
                },
                icon: const Icon(Icons.skip_next),
                label: const Text('Continue replay'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
