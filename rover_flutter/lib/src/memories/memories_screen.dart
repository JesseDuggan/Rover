import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:geolocator/geolocator.dart';

import '../adventure/roam.dart';
import '../location/rover_location.dart';
import '../maps/rover_map_view.dart';

import 'memory_store.dart';
import '../api/adaptive_route_story_models.dart';
import 'walk_replay_screen.dart';
import 'memory_thumbnail.dart';
import 'saved_memory_walk_picker.dart';
import '../sharing/shared_walks.dart';
import '../sharing/story_share_data.dart';

class MemoriesScreen extends StatefulWidget {
  const MemoriesScreen({
    super.key,
    this.store,
    this.journey,
    this.captureEnabled = true,
    this.showHistory = false,
    this.stories = const [],
  });
  final MemoryStore? store;
  final MemoryJourney? journey;
  final bool captureEnabled;
  final bool showHistory;
  final List<AdaptiveRouteStory> stories;
  @override
  State<MemoriesScreen> createState() => _MemoriesScreenState();
}

class _MemoriesScreenState extends State<MemoriesScreen>
    with SingleTickerProviderStateMixin {
  late final store = widget.store ?? MemoryStore();
  late bool history = widget.showHistory;
  late final tabs = TabController(
    length: 2,
    vsync: this,
    initialIndex: history ? 1 : 0,
  );
  late Future<List<WalkMemory>> items = load();
  Future<List<WalkMemory>> load() async {
    final all = await store.list();
    if (widget.journey == null) return all;
    final id = await store.journeyId(widget.journey!.id);
    return all.where((m) => m.details.journey?.id == id).toList();
  }

  void reload() => setState(() => items = load());
  Future<void> rename(MemoryJourney journey) async {
    final name = TextEditingController(text: journey.displayName);
    final value = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Name this walk'),
        content: TextField(controller: name, maxLength: 160, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (name.text.trim().isNotEmpty) {
                Navigator.pop(c, name.text.trim());
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    // The dialog finishes its dismissal animation before disposing its controller.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    name.dispose();
    if (value == null || !mounted) return;
    try {
      await store.renameJourney(journey, value);
      if (mounted) reload();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not save the walk name. Please retry.'),
          ),
        );
      }
    }
  }

  String journeyDate(MemoryJourney journey, List<WalkMemory> memories) {
    final dates =
        memories
            .where((m) => m.details.journey?.id == journey.id)
            .map((m) => m.details.capturedAt)
            .whereType<DateTime>()
            .toList()
          ..sort();
    if (dates.isEmpty) return '';
    final at = dates.first.toLocal();
    return '${MaterialLocalizations.of(context).formatMediumDate(at)} · ${MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(at))}\n';
  }

  Future<void> view(WalkMemory memory) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MemoryViewer(memory: memory, store: store),
      ),
    );
    if (mounted) reload();
  }

  Future<void> capture() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            MemoryCaptureScreen(store: store, journey: widget.journey),
      ),
    );
    if (mounted) reload();
  }

  @override
  void dispose() {
    tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.journey == null ? 'Memories' : 'Walk Memories'),
      bottom: widget.journey == null
          ? TabBar(
              controller: tabs,
              onTap: (index) => setState(() => history = index == 1),
              tabs: const [
                Tab(text: 'All memories'),
                Tab(text: 'By walk'),
              ],
            )
          : null,
      actions: [
        if (widget.journey != null)
          IconButton(
            tooltip: 'Replay walk',
            icon: const Icon(Icons.play_circle_outline),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => WalkReplayScreen(
                  journey: widget.journey!,
                  memoryStore: store,
                  stories: widget.stories,
                ),
              ),
            ),
          ),
        IconButton(
          tooltip: widget.journey == null ? 'Share memories' : 'Share walk',
          icon: const Icon(Icons.share_outlined),
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => ShareWalkScreen(
                journey: widget.journey,
                store: store,
                stories: widget.stories.map(storyShareData).toList(),
              ),
            ),
          ),
        ),
        IconButton(
          tooltip: 'Refresh memories',
          onPressed: reload,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    floatingActionButton: !widget.captureEnabled
        ? null
        : FloatingActionButton(
            tooltip: 'Capture a memory',
            onPressed: capture,
            child: const Icon(Icons.add_a_photo),
          ),
    body: FutureBuilder<List<WalkMemory>>(
      future: items,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: TextButton(
              onPressed: reload,
              child: const Text('Could not load memories. Retry'),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final memories = snapshot.data!;
        if (history && widget.journey == null) {
          final journeys = <String, MemoryJourney>{};
          for (final memory in memories) {
            final journey = memory.details.journey;
            if (journey != null) {
              journeys.putIfAbsent(journey.id, () => journey);
            }
          }
          if (journeys.isEmpty) {
            return const Center(child: Text('No walk memories yet'));
          }
          return ListView(
            children: [
              for (final journey in journeys.values)
                ListTile(
                  leading: const Icon(Icons.route),
                  title: Text(journey.displayName),
                  trailing: IconButton(
                    tooltip: 'Rename walk',
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: () => rename(journey),
                  ),
                  subtitle: Text(
                    '${journeyDate(journey, memories)}${memories.where((m) => m.details.journey?.id == journey.id).length} memories - Private on this device',
                  ),
                  onTap: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => MemoriesScreen(
                          store: store,
                          journey: journey,
                          captureEnabled: false,
                        ),
                      ),
                    );
                    if (mounted) reload();
                  },
                ),
            ],
          );
        }
        if (memories.isEmpty) {
          return const Center(child: Text('No memories yet'));
        }
        final located = memories
            .where((m) => m.details.location != null)
            .toList();
        return Column(
          children: [
            if (widget.journey != null &&
                (located.isNotEmpty ||
                    widget.journey!.route.routeGeometry.isNotEmpty))
              SizedBox(
                height: 260,
                child: RoverMapView(
                  currentLocation: null,
                  overview: true,
                  height: 260,
                  enableExpand: false,
                  routeGeometry: widget.journey!.route.routeGeometry,
                  orderedStops: [
                    for (var i = 0; i < located.length; i++)
                      OrderedRoverStop(
                        sequence: i + 1,
                        stop: RoverStop(
                          id: located[i].id,
                          name: located[i].details.caption.isNotEmpty
                              ? located[i].details.caption
                              : 'Memory ${i + 1}',
                          image: '',
                          shortDescription: '',
                          estimatedVisitMinutes: 0,
                          coordinates: located[i].details.location!,
                          category: 'Memory',
                          whySelected: '',
                        ),
                      ),
                  ],
                  onStopTap: (stop) =>
                      view(located.firstWhere((m) => m.id == stop.stop.id)),
                ),
              ),
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 240,
                  childAspectRatio: 0.85,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                ),
                itemCount: memories.length,
                itemBuilder: (context, index) {
                  final memory = memories[index];
                  return Semantics(
                    label: memory.isVideo ? 'Video memory' : 'Photo memory',
                    button: true,
                    child: InkWell(
                      onTap: () async {
                        await Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) =>
                                MemoryViewer(memory: memory, store: store),
                          ),
                        );
                        if (mounted) reload();
                      },
                      child: GridTile(
                        footer: ColoredBox(
                          color: Colors.black54,
                          child: Padding(
                            padding: const EdgeInsets.all(8),
                            child: Text(
                              memory.details.caption.isNotEmpty
                                  ? memory.details.caption
                                  : memory.details.poiName ??
                                        'Private on this device',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Colors.white),
                            ),
                          ),
                        ),
                        child: MemoryThumbnail(memory: memory),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    ),
  );
}

class MemoryViewer extends StatefulWidget {
  const MemoryViewer({
    super.key,
    required this.memory,
    required this.store,
    this.draft = false,
  });
  final WalkMemory memory;
  final MemoryStore store;
  final bool draft;
  @override
  State<MemoryViewer> createState() => _MemoryViewerState();
}

class _MemoryViewerState extends State<MemoryViewer>
    with WidgetsBindingObserver {
  VideoPlayerController? player;
  String? error;
  bool busy = false;
  late final caption = TextEditingController(
    text: widget.memory.details.caption,
  );
  late String? selectedPoi = widget.memory.details.poiName;
  late MemoryDetails details = widget.memory.details;
  MemoryDetails get editedDetails =>
      details.withCaption(caption.text).withPlace(selectedPoi);

  Future<void> attach() async {
    await player?.pause();
    if (!mounted) return;
    final journey = await Navigator.of(context).push<MemoryJourney>(
      MaterialPageRoute(builder: (_) => const SavedMemoryWalkPicker()),
    );
    if (!mounted || journey == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Attach to ${journey.route.title}?'),
        content: const Text(
          'This changes the local walk association only. The original capture location stays unchanged, and nothing is uploaded.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Attach'),
          ),
        ],
      ),
    );
    if (!mounted || confirm != true) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final updated = await widget.store.attachToWalk(
        WalkMemory(widget.memory.file, details: editedDetails),
        journey,
      );
      if (mounted) {
        setState(() {
          details = updated;
          selectedPoi = updated.poiName;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => error = 'Could not attach this memory. Please retry.');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.memory.isVideo) {
      player = VideoPlayerController.file(widget.memory.file);
      player!
          .initialize()
          .then((_) {
            if (mounted) setState(() {});
          })
          .catchError((Object _) {
            if (mounted) {
              setState(() => error = 'This video could not be opened.');
            }
          });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) unawaited(player?.pause());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    player?.dispose();
    caption.dispose();
    super.dispose();
  }

  Future<void> act() async {
    if (busy) return;
    if (!widget.draft) {
      final yes = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Delete this memory?'),
          content: const Text('This cannot be undone.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete'),
            ),
          ],
        ),
      );
      if (yes != true || !mounted) return;
    }
    setState(() => busy = true);
    try {
      await player?.pause();
      if (widget.draft) {
        await widget.store.save(
          widget.memory.file,
          video: widget.memory.isVideo,
          details: editedDetails,
        );
      } else {
        await player?.dispose();
        player = null;
        await widget.store.delete(widget.memory);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        setState(() {
          busy = false;
          error = 'Could not save or delete this memory. Please retry.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Close',
          icon: const Icon(Icons.close),
          onPressed: busy ? null : () => Navigator.pop(context),
        ),
        title: Text(widget.draft ? 'Preview' : 'Memory'),
        actions: [
          if (!widget.draft)
            IconButton(
              tooltip: 'Share memory',
              icon: const Icon(Icons.share_outlined),
              onPressed: busy || details.sharingLocked
                  ? null
                  : () async {
                      await player?.pause();
                      if (!context.mounted) return;
                      await Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => ShareWalkScreen(
                            store: widget.store,
                            initialMemoryIds: {widget.memory.id},
                          ),
                        ),
                      );
                    },
            ),
          if (!widget.draft)
            IconButton(
              tooltip: 'Save caption',
              icon: const Icon(Icons.save_outlined),
              onPressed: busy
                  ? null
                  : () async {
                      setState(() => busy = true);
                      try {
                        await widget.store.updateDetails(
                          widget.memory,
                          editedDetails,
                        );
                        if (context.mounted) Navigator.pop(context);
                      } catch (_) {
                        if (mounted) {
                          setState(() {
                            busy = false;
                            error = 'Could not save caption. Please retry.';
                          });
                        }
                      }
                    },
            ),
          IconButton(
            tooltip: widget.draft ? 'Save memory' : 'Delete memory',
            onPressed: busy ? null : act,
            icon: Icon(
              widget.draft ? Icons.save_outlined : Icons.delete_outline,
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          if (busy) const LinearProgressIndicator(),
          if (!widget.draft)
            SwitchListTile(
              title: const Text('Keep this memory private'),
              value: details.sharingLocked,
              onChanged: busy
                  ? null
                  : (value) async {
                      if (value) {
                        final yes = await showDialog<bool>(
                          context: context,
                          builder: (c) => AlertDialog(
                            title: const Text('Keep this memory private?'),
                            content: const Text(
                              'This excludes it from future shares. Existing shared copies are unchanged; make those walks private from Shared walks > Sent.',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(c, false),
                                child: const Text('Cancel'),
                              ),
                              FilledButton(
                                onPressed: () => Navigator.pop(c, true),
                                child: const Text('Keep private'),
                              ),
                            ],
                          ),
                        );
                        if (yes != true || !mounted) return;
                      }
                      setState(() => busy = true);
                      try {
                        final next = editedDetails.withSharingLocked(value);
                        await widget.store.updateDetails(widget.memory, next);
                        if (mounted) setState(() => details = next);
                      } catch (_) {
                        if (mounted) {
                          setState(
                            () =>
                                error = 'Could not save privacy. Please retry.',
                          );
                        }
                      } finally {
                        if (mounted) setState(() => busy = false);
                      }
                    },
            ),
          if (error != null)
            Padding(padding: const EdgeInsets.all(16), child: Text(error!)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: caption,
              enabled: !busy,
              maxLength: 300,
              decoration: const InputDecoration(labelText: 'Caption'),
            ),
          ),
          if (!widget.draft)
            ListTile(
              leading: const Icon(Icons.add_road_outlined),
              title: Text(
                details.journey?.route.title ?? 'Attach to saved walk',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: busy ? null : attach,
            ),
          if (details.journey != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: DropdownButtonFormField<String>(
                key: ValueKey(details.journey!.id),
                initialValue: selectedPoi ?? '',
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Place (optional)',
                ),
                items: [
                  const DropdownMenuItem(
                    value: '',
                    child: Text('No place selected'),
                  ),
                  for (final name in {
                    ?selectedPoi,
                    ...details.journey!.route.stops.map((s) => s.name),
                  })
                    DropdownMenuItem(
                      value: name,
                      child: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: busy
                    ? null
                    : (value) => setState(
                        () => selectedPoi = value == '' ? null : value,
                      ),
              ),
            ),
          Text(
            widget.memory.details.location == null
                ? 'Location not recorded'
                : '${widget.memory.details.poiName ?? 'Captured at'} ${widget.memory.details.location}',
          ),
          Expanded(
            child: Center(
              child: widget.memory.isVideo
                  ? player?.value.isInitialized == true
                        ? AspectRatio(
                            aspectRatio: player!.value.aspectRatio,
                            child: VideoPlayer(player!),
                          )
                        : error == null
                        ? const CircularProgressIndicator()
                        : const Icon(Icons.error_outline)
                  : InteractiveViewer(
                      child: Image.file(
                        widget.memory.file,
                        errorBuilder: (_, _, _) =>
                            const Text('Photo unavailable'),
                      ),
                    ),
            ),
          ),
          if (player?.value.isInitialized == true)
            ValueListenableBuilder<VideoPlayerValue>(
              valueListenable: player!,
              builder: (context, value, _) => SafeArea(
                child: Column(
                  children: [
                    VideoProgressIndicator(
                      player!,
                      allowScrubbing: !busy,
                      padding: const EdgeInsets.all(16),
                    ),
                    IconButton(
                      tooltip: value.isPlaying ? 'Pause' : 'Play',
                      icon: Icon(
                        value.isPlaying ? Icons.pause : Icons.play_arrow,
                      ),
                      onPressed: busy
                          ? null
                          : () async {
                              if (value.isPlaying) {
                                await player!.pause();
                              } else {
                                if (value.position >= value.duration) {
                                  await player!.seekTo(Duration.zero);
                                }
                                await player!.play();
                              }
                            },
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

class MemoryCaptureScreen extends StatefulWidget {
  const MemoryCaptureScreen({super.key, required this.store, this.journey});
  final MemoryStore store;
  final MemoryJourney? journey;
  @override
  State<MemoryCaptureScreen> createState() => _MemoryCaptureScreenState();
}

class _MemoryCaptureScreenState extends State<MemoryCaptureScreen>
    with WidgetsBindingObserver {
  CameraController? camera;
  Timer? limit;
  Timer? ticker;
  DateTime? started;
  bool video = false, busy = false, recording = false, reviewing = false;
  String? error;
  int generation = 0;
  bool opening = false;
  MemoryDetails capturedDetails = const MemoryDetails();

  Future<MemoryDetails> captureDetails() async {
    final journey = widget.journey;
    final linked = journey == null
        ? null
        : MemoryJourney(
            id: await widget.store.journeyId(journey.id),
            route: journey.route,
          );
    final timestamp = DateTime.now().toUtc();
    RoverLatLng? point;
    double? accuracy;
    String? poi;
    // Never invent a position from a route stop or simulated navigation.
    try {
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.always ||
          permission == LocationPermission.whileInUse) {
        final position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 3),
          ),
        );
        if (position.accuracy <= 100 &&
            DateTime.now().difference(position.timestamp).abs() <=
                const Duration(seconds: 15)) {
          point = RoverLatLng(
            latitude: position.latitude,
            longitude: position.longitude,
          );
          accuracy = position.accuracy;
          final stops = [...?journey?.route.stops];
          stops.sort(
            (a, b) => point!
                .distanceTo(a.coordinates)
                .compareTo(point.distanceTo(b.coordinates)),
          );
          if (stops.isNotEmpty &&
              point.distanceTo(stops.first.coordinates) <= 50) {
            poi = stops.first.name;
          }
        }
      }
    } catch (_) {
      /* A missing GPS fix must not prevent a memory. */
    }
    return MemoryDetails(
      journey: linked,
      capturedAt: timestamp,
      location: point,
      accuracyMeters: accuracy,
      poiName: poi,
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(open());
  }

  Future<void> open() async {
    if (opening) return;
    setState(() => opening = true);
    final epoch = ++generation;
    try {
      final cameras = await availableCameras();
      if (!mounted || epoch != generation) return;
      final selected = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        selected,
        ResolutionPreset.high,
        enableAudio: video,
      );
      camera = controller;
      await controller.initialize();
      if (!mounted || epoch != generation) {
        await controller.dispose();
        return;
      }
      setState(() => error = null);
    } catch (_) {
      if (mounted && epoch == generation) {
        setState(
          () => error =
              'Camera unavailable. Check camera and microphone permissions.',
        );
      }
    } finally {
      if (mounted) setState(() => opening = false);
      if (mounted &&
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.paused) {
        await closeCamera();
      }
    }
  }

  Future<void> closeCamera() async {
    generation++;
    final controller = camera;
    camera = null;
    await controller?.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive && !reviewing) {
      unawaited(suspend());
    } else if (state == AppLifecycleState.resumed &&
        camera == null &&
        !busy &&
        !reviewing) {
      unawaited(open());
    }
  }

  Future<void> suspend() async {
    if (opening || busy) return;
    if (recording) await capture(showPreview: false);
    if (!busy) await closeCamera();
  }

  Future<void> capture({bool showPreview = true}) async {
    final controller = camera;
    if (busy || controller == null || !controller.value.isInitialized) return;
    setState(() => busy = true);
    try {
      if (!recording) capturedDetails = await captureDetails();
      if (!mounted) return;
      if (video && !recording) {
        await controller.startVideoRecording();
        if (!mounted) return;
        started = DateTime.now();
        recording = true;
        limit = Timer(const Duration(seconds: 60), () => unawaited(capture()));
        ticker = Timer.periodic(const Duration(seconds: 1), (_) {
          if (mounted) setState(() {});
        });
      } else {
        limit?.cancel();
        ticker?.cancel();
        final file = recording
            ? await controller.stopVideoRecording()
            : await controller.takePicture();
        recording = false;
        reviewing = true;
        await closeCamera();
        // Preserve an interrupted recording locally without starting playback in the background.
        if (!showPreview) {
          await widget.store.save(
            File(file.path),
            video: video,
            details: capturedDetails,
          );
        } else if (mounted) {
          await Navigator.of(context).push<bool>(
            MaterialPageRoute(
              builder: (_) => MemoryViewer(
                memory: WalkMemory(File(file.path), details: capturedDetails),
                store: widget.store,
                draft: true,
              ),
            ),
          );
        }
        await File(file.path).delete();
        reviewing = false;
        if (mounted &&
            WidgetsBinding.instance.lifecycleState ==
                AppLifecycleState.resumed) {
          await open();
        }
      }
    } catch (_) {
      limit?.cancel();
      ticker?.cancel();
      recording = false;
      reviewing = false;
      await closeCamera();
      if (mounted) error = 'Capture failed. Please try again.';
    } finally {
      if (mounted) setState(() => busy = false);
      if (mounted &&
          WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
        unawaited(suspend());
      }
    }
  }

  @override
  void dispose() {
    generation++;
    limit?.cancel();
    ticker?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    camera?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !recording && !busy,
    child: Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(
          recording
              ? 'Recording ${60 - DateTime.now().difference(started!).inSeconds.clamp(0, 60)}s'
              : 'Capture memory',
        ),
        leading: IconButton(
          tooltip: 'Close',
          icon: const Icon(Icons.close),
          onPressed: recording || busy ? null : () => Navigator.pop(context),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: Center(
              child: error != null
                  ? Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        error!,
                        style: const TextStyle(color: Colors.white),
                      ),
                    )
                  : camera?.value.isInitialized == true
                  ? CameraPreview(camera!)
                  : const CircularProgressIndicator(),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(
                        value: false,
                        label: Text('Photo'),
                        icon: Icon(Icons.photo_camera),
                      ),
                      ButtonSegment(
                        value: true,
                        label: Text('Video'),
                        icon: Icon(Icons.videocam),
                      ),
                    ],
                    selected: {video},
                    onSelectionChanged: recording || busy || opening
                        ? null
                        : (values) async {
                            setState(() {
                              busy = true;
                              video = values.single;
                            });
                            await closeCamera();
                            await open();
                            if (mounted) setState(() => busy = false);
                          },
                  ),
                  const SizedBox(height: 12),
                  IconButton.filled(
                    tooltip: recording
                        ? 'Stop recording'
                        : video
                        ? 'Record video'
                        : 'Take photo',
                    iconSize: 36,
                    onPressed: busy || camera?.value.isInitialized != true
                        ? null
                        : capture,
                    icon: Icon(
                      recording
                          ? Icons.stop
                          : video
                          ? Icons.fiber_manual_record
                          : Icons.camera_alt,
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
