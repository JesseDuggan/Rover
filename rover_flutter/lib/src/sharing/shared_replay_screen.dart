import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../accounts/account_library.dart';
import '../adventure/roam.dart';
import '../api/adaptive_route_story_models.dart';
import '../location/rover_location.dart';
import '../memories/memory_store.dart';
import '../memories/walk_replay_screen.dart';
import 'shared_walks.dart';

/// Revalidate the grant while replay is open, including any pushed media screen.
class SharedReplayScreen extends StatefulWidget {
  const SharedReplayScreen({
    super.key,
    required this.shareId,
    required this.library,
  });
  final String shareId;
  final AccountLibrary library;
  @override
  State<SharedReplayScreen> createState() => _SharedReplayScreenState();
}

class _SharedReplayScreenState extends State<SharedReplayScreen>
    with WidgetsBindingObserver {
  Map<String, dynamic>? data;
  String? error;
  Timer? timer;
  bool checking = false;
  bool denied = false;
  late final generation = widget.library.sessionGeneration;
  bool get valid =>
      mounted &&
      !denied &&
      widget.library.signedIn &&
      generation == widget.library.sessionGeneration;

  @override
  void initState() {
    super.initState();
    widget.library.addListener(changed);
    WidgetsBinding.instance.addObserver(this);
    verify();
    timer = Timer.periodic(const Duration(seconds: 15), (_) => verify());
  }

  void changed() {
    if (!valid && mounted) deny();
  }

  void deny() {
    if (!mounted || denied) return;
    denied = true;
    final route = ModalRoute.of(context);
    Navigator.of(context).popUntil((r) => r == route);
    setState(() {
      data = null;
      error = 'Replay unavailable. Sign-in or sharing access may have changed.';
    });
  }

  Future<void> verify() async {
    if (!valid || checking) return;
    checking = true;
    try {
      final result = await widget.library.request(
        'GET',
        '/api/shared-walks/${widget.shareId}',
      );
      if (valid && data == null) {
        setState(() => data = result as Map<String, dynamic>);
      }
    } catch (_) {
      deny();
    } finally {
      checking = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) verify();
  }

  @override
  void dispose() {
    timer?.cancel();
    widget.library.removeListener(changed);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  RoverLatLng point(Map p) => RoverLatLng(
    latitude: (p['latitude'] as num).toDouble(),
    longitude: (p['longitude'] as num).toDouble(),
  );

  @override
  Widget build(BuildContext context) {
    final walk = data;
    if (walk == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Shared replay')),
        body: Center(
          child: error == null
              ? const CircularProgressIndicator()
              : Text(error!),
        ),
      );
    }
    final media = (walk['media'] as List).cast<Map<String, dynamic>>();
    final stories = [
      for (final s
          in (walk['stories'] as List? ?? []).cast<Map<String, dynamic>>())
        AdaptiveRouteStory.fromJson({
          'storyId': s['id'], 'title': s['title'],
          'anchor': s['location'] ?? {'latitude': 0, 'longitude': 0},
          'sensitivityNotice': s['notice'],
          // Shared text is not reclassified as family-safe.
          'audienceSuitability': 'unreviewed',
          'variants': [
            {'length': 'Standard', 'narration': s['narration']},
          ],
          'sources': [
            for (final url in s['sources'] as List) {'url': url},
          ],
        }),
    ];
    return WalkReplayScreen(
      journey: MemoryJourney(
        id: widget.shareId,
        route: RoverRoam(
          title: walk['title'] as String,
          summary: '',
          stops: const [],
          walkingMinutes: 0,
          distanceMiles: 0,
          startingPoint: '',
          accessibilityNotes: const [],
          warnings: const [],
          routeGeometry: (walk['route'] as List)
              .map((p) => point(p as Map))
              .toList(),
        ),
      ),
      sharedRows: (walk['trail'] as List).cast<Map<String, dynamic>>(),
      sharedMemories: [
        for (final m in media)
          WalkMemory(
            File('${m['id']}.${m['kind'] == 'video' ? 'mp4' : 'jpg'}'),
            details: MemoryDetails(
              caption: m['caption'] as String,
              capturedAt: DateTime.tryParse(m['capturedAt'] as String? ?? ''),
              location: m['location'] == null
                  ? null
                  : point(m['location'] as Map),
            ),
          ),
      ],
      stories: stories,
      eventBuilder: (event) => event.memory == null
          ? ReplayMediaScreen(event: event)
          : SharedMediaScreen(
              shareId: widget.shareId,
              library: widget.library,
              replay: true,
              media: media.firstWhere(
                (m) => event.memory!.id.startsWith('${m['id']}.'),
              ),
            ),
    );
  }
}
