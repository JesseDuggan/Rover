import 'dart:async';

import 'package:flutter/material.dart';

import '../api/location_story_models.dart';
import '../api/walk_repository.dart';
import '../location/location_controller.dart';
import '../voice/rover_voice_controller.dart';

class TellHereScreen extends StatefulWidget {
  const TellHereScreen({
    super.key,
    required this.voice,
    required this.repository,
    required this.location,
    this.interests = const [],
  });
  final RoverVoiceController voice;
  final WalkRepository repository;
  final LocationController location;
  final List<String> interests;
  @override
  State<TellHereScreen> createState() => _TellHereScreenState();
}

class _TellHereScreenState extends State<TellHereScreen>
    with WidgetsBindingObserver {
  LocationStoryResponse? story;
  String? error;
  bool busy = true, speaking = false, expanded = false, foreground = true;
  int epoch = 0;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    load();
  }

  Future<void> load() async {
    final token = ++epoch;
    setState(() {
      busy = true;
      error = null;
      story = null;
    });
    try {
      await widget.voice.stopAll();
      final fix = await widget.location.ensureDeviceLocation(
        forceRefresh: true,
      );
      if (!mounted || token != epoch) return;
      if (fix.location == null) throw StateError('Location unavailable');
      final response = await widget.repository.createLocationStory(
        LocationStoryRequest(
          location: fix.location!,
          radiusMeters: 300,
          routeGeometry: const [],
          interests: widget.interests,
          selectedPlaceIds: const [],
          narrationStyle: 'short-spoken',
        ),
      );
      if (!mounted || token != epoch) return;
      if (response.shortSpokenNarration.trim().isEmpty ||
          response.sourceReferences.isEmpty ||
          response.factIdsUsed.isEmpty ||
          response.researchStatus == 'failed' ||
          response.researchStatus == 'empty' ||
          (response.expiresUtc?.isBefore(DateTime.now().toUtc()) ?? false)) {
        setState(
          () => error =
              'No verified introduction was found here. Try again nearby.',
        );
        return;
      }
      setState(() {
        story = response;
        busy = false;
        expanded = false;
      });
      if (foreground) unawaited(speak(false));
    } catch (_) {
      if (mounted && token == epoch) {
        setState(
          () => error = 'Could not describe this location. Check location permission and your connection, then retry.',
        );
      }
    } finally {
      if (mounted && token == epoch) setState(() => busy = false);
    }
  }

  Future<void> speak(bool more) async {
    final response = story;
    if (response == null || !foreground) return;
    final token = ++epoch;
    await widget.voice.stopQuestionAnswer();
    if (!mounted || token != epoch || !foreground) return;
    setState(() {
      speaking = true;
      expanded = more;
    });
    try {
      await widget.voice.playHereNarration(
        [
          ...response.warnings,
          more ? response.tellMeMore! : response.shortSpokenNarration,
          if (response.requiredAttribution.isNotEmpty)
            'Sources: ${response.requiredAttribution.join(', ')}.',
        ].join('\n'),
      );
    } catch (_) {
      if (mounted) {
        setState(
          () =>
              error = 'Audio unavailable. You can read the introduction below.',
        );
      }
    } finally {
      if (mounted && token == epoch) setState(() => speaking = false);
    }
  }

  Future<void> stop() async {
    epoch++;
    await widget.voice.stopQuestionAnswer();
    if (mounted) setState(() => speaking = false);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
    if (!foreground && speaking) unawaited(stop());
  }

  @override
  void dispose() {
    epoch++;
    WidgetsBinding.instance.removeObserver(this);
    unawaited(widget.voice.stopQuestionAnswer());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Tell me about here')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        if (busy) const LinearProgressIndicator(),
        if (error != null) Text(error!),
        if (!busy && story == null)
          TextButton(onPressed: load, child: const Text('Try again')),
        if (story != null) ...[
          Text(
            story!.storyTitle,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 16),
          for (final warning in story!.warnings) Text(warning),
          SelectableText(
            expanded ? story!.tellMeMore! : story!.shortSpokenNarration,
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: speaking ? stop : () => speak(expanded),
                icon: Icon(speaking ? Icons.stop : Icons.volume_up_outlined),
                label: Text(speaking ? 'Stop' : 'Listen'),
              ),
              if (story!.tellMeMore?.trim().isNotEmpty == true)
                OutlinedButton.icon(
                  onPressed: () => speak(true),
                  icon: const Icon(Icons.headphones_outlined),
                  label: const Text('Hear more'),
                ),
            ],
          ),
          const SizedBox(height: 20),
          for (final source in story!.sourceReferences)
            SelectableText(source.sourceUrl ?? source.attribution),
        ],
      ],
    ),
  );
}
