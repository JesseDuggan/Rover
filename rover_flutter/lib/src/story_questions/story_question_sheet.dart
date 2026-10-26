import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../active_roam/active_roam_session.dart';
import '../api/adaptive_route_story_models.dart';
import '../voice/rover_voice_controller.dart';
import 'story_question_controller.dart';

Future<void> showStoryQuestionSheet(
  BuildContext context, {
  required String title,
  required StoryQuestionContext? Function() currentContext,
  required RoverVoiceController voice,
  RoamSession? Function()? currentSession,
  bool Function()? playbackAllowed,
}) async {
  final controller = StoryQuestionController(currentContext: currentContext);
  voice.setQuestionInteractionActive(true);
  try {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => FractionallySizedBox(
        heightFactor: 0.92,
        child: StoryQuestionSheet(
          title: title,
          controller: controller,
          play: (answer) async {
            if (playbackAllowed?.call() == false) return false;
            return voice.playQuestionAnswer(
              answer,
              session: currentSession?.call(),
            );
          },
          stop: voice.stopQuestionAnswer,
        ),
      ),
    );
  } finally {
    controller.dispose();
    await voice.stopQuestionAnswer();
    voice.setQuestionInteractionActive(false);
  }
}

class StoryQuestionSheet extends StatefulWidget {
  const StoryQuestionSheet({
    super.key,
    required this.title,
    required this.controller,
    required this.play,
    required this.stop,
  });
  final String title;
  final StoryQuestionController controller;
  final Future<bool> Function(AdaptiveRouteStorySelection) play;
  final Future<void> Function() stop;

  @override
  State<StoryQuestionSheet> createState() => _StoryQuestionSheetState();
}

class _StoryQuestionSheetState extends State<StoryQuestionSheet> {
  final _question = TextEditingController();
  String _scope = 'Auto', _format = 'Auto';
  int _count = 3;
  String? _playingId, _playbackMessage;
  int _playbackGeneration = 0;

  @override
  void dispose() {
    _playbackGeneration++;
    _question.dispose();
    unawaited(widget.stop());
    super.dispose();
  }

  Future<void> _play(AdaptiveRouteStorySelection answer) async {
    if (!widget.controller.answersAreCurrent) {
      setState(
        () => _playbackMessage =
            'Your location or route changed. Ask again before playing.',
      );
      return;
    }
    final generation = ++_playbackGeneration;
    setState(() {
      _playingId = answer.story.storyId;
      _playbackMessage = null;
    });
    try {
      final completed = await widget.play(answer);
      if (!mounted || generation != _playbackGeneration) return;
      setState(
        () => _playbackMessage = completed ? 'Answer finished.' : 'Playback was held or interrupted. Wait for navigation or other audio to finish, then try again.',
      );
    } catch (_) {
      if (mounted && generation == _playbackGeneration) {
        setState(
          () => _playbackMessage =
              'Could not play this answer. You can still read it.',
        );
      }
    } finally {
      if (mounted && generation == _playbackGeneration) {
        setState(() => _playingId = null);
      }
    }
  }

  Future<void> _stop() async {
    _playbackGeneration++;
    await widget.stop();
    if (mounted) {
      setState(() {
        _playingId = null;
        _playbackMessage = 'Playback stopped.';
      });
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      final controller = widget.controller;
      final locked = controller.busy || _playingId != null;
      return SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.title,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close questions',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _question,
                enabled: !locked,
                minLines: 2,
                maxLines: 4,
                maxLength: 1200,
                decoration: const InputDecoration(
                  labelText: 'Your question',
                  hintText: 'How has this neighbourhood changed?',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _scope,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Search area'),
                items: const [
                  DropdownMenuItem(
                    value: 'Auto',
                    child: Text('From my question'),
                  ),
                  DropdownMenuItem(value: 'Street', child: Text('This street')),
                  DropdownMenuItem(
                    value: 'Neighbourhood',
                    child: Text('This neighbourhood'),
                  ),
                  DropdownMenuItem(value: 'City', child: Text('This city')),
                  DropdownMenuItem(value: 'Route', child: Text('My route')),
                ],
                onChanged: locked
                    ? null
                    : (value) => setState(() => _scope = value!),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _format,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Answer format'),
                items: const [
                  DropdownMenuItem(
                    value: 'Auto',
                    child: Text('From my question'),
                  ),
                  DropdownMenuItem(value: 'Single', child: Text('One story')),
                  DropdownMenuItem(
                    value: 'ThenAndNow',
                    child: Text('Then and now'),
                  ),
                  DropdownMenuItem(
                    value: 'Collection',
                    child: Text('Story collection'),
                  ),
                ],
                onChanged: locked
                    ? null
                    : (value) => setState(() => _format = value!),
              ),
              if (_format == 'Collection')
                DropdownButtonFormField<int>(
                  initialValue: _count,
                  decoration: const InputDecoration(
                    labelText: 'Number of stories',
                  ),
                  items: [
                    for (var i = 2; i <= 5; i++)
                      DropdownMenuItem(value: i, child: Text('$i')),
                  ],
                  onChanged: locked
                      ? null
                      : (value) => setState(() => _count = value!),
                ),
              const SizedBox(height: 16),
              if (controller.busy) ...[
                const LinearProgressIndicator(),
                TextButton.icon(
                  onPressed: controller.cancel,
                  icon: const Icon(Icons.close),
                  label: const Text('Cancel research'),
                ),
              ] else
                FilledButton.icon(
                  onPressed: _playingId != null
                      ? null
                      : () {
                          FocusScope.of(context).unfocus();
                          setState(() => _playbackMessage = null);
                          unawaited(
                            controller.ask(
                              _question.text,
                              scope: _scope,
                              format: _format,
                              storyCount: _format == 'Collection'
                                  ? _count
                                  : null,
                            ),
                          );
                        },
                  icon: const Icon(Icons.search),
                  label: Text(
                    controller.message == null && controller.response == null
                        ? 'Ask'
                        : 'Ask again',
                  ),
                ),
              if (controller.message case final message?)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Semantics(liveRegion: true, child: Text(message)),
                ),
              if (_playbackMessage case final message?)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Semantics(liveRegion: true, child: Text(message)),
                ),
              for (final answer
                  in controller.response?.answers ??
                      <AdaptiveRouteStorySelection>[])
                ExpansionTile(
                  key: ValueKey(answer.story.storyId),
                  initiallyExpanded: true,
                  tilePadding: EdgeInsets.zero,
                  title: Text(answer.story.title),
                  subtitle: Text(
                    '${answer.variant.estimatedDurationSeconds} sec',
                  ),
                  children: [
                    if (answer.story.sensitivityNotice case final notice?)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          notice,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    if (answer.story.uncertainClaims.isNotEmpty)
                      Text(
                        'Source uncertainty: ${answer.story.uncertainClaims.join(' ')}',
                      ),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: SelectableText(answer.variant.narration),
                    ),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: _playingId == answer.story.storyId
                          ? OutlinedButton.icon(
                              onPressed: _stop,
                              icon: const Icon(Icons.stop),
                              label: const Text('Stop answer'),
                            )
                          : OutlinedButton.icon(
                              onPressed: _playingId != null
                                  ? null
                                  : () => _play(answer),
                              icon: const Icon(Icons.play_arrow),
                              label: const Text('Play answer'),
                            ),
                    ),
                    for (final source in answer.story.sources)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(source.title ?? source.providerName),
                        subtitle: Text(source.attribution),
                        trailing: const Icon(Icons.open_in_new),
                        onTap: () async {
                          final uri = Uri.tryParse(source.url ?? '');
                          var opened = false;
                          if (uri != null &&
                              ['https', 'http'].contains(uri.scheme)) {
                            try {
                              opened = await launchUrl(
                                uri,
                                mode: LaunchMode.externalApplication,
                              );
                            } catch (_) {}
                          }
                          if (!opened && context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Could not open this source.'),
                              ),
                            );
                          }
                        },
                      ),
                  ],
                ),
            ],
          ),
        ),
      );
    },
  );
}
