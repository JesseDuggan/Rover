import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../voice/rover_audio_services.dart';

/// Chapter browsing is separate from geographic stops: demolished places and
/// regional stories must not acquire invented entrances or duplicate geofences.
class TourDetailsScreen extends StatefulWidget {
  const TourDetailsScreen({super.key, required this.data, this.voice});
  final Map<String, dynamic> data;
  final RoverTextToSpeech? voice;
  @override
  State<TourDetailsScreen> createState() => _TourDetailsState();
}

class _TourDetailsState extends State<TourDetailsScreen> {
  late final voice = widget.voice ?? DeviceTextToSpeech();
  int turn = 0;
  String? playing;
  String message = '';

  Future<void> stop() async {
    turn++;
    if (mounted) setState(() => playing = null);
    await voice.stop();
  }

  Future<void> play(String title, String text) async {
    final ticket = ++turn;
    setState(() {
      playing = title;
      message = '';
    });
    try {
      await voice.stop();
      if (!mounted || turn != ticket) return;
      await voice.configure(rate: 0.5);
      if (!mounted || turn != ticket) return;
      await voice.speak(text);
    } catch (_) {
      if (mounted && turn == ticket) {
        setState(
          () => message =
              'Audio could not play. The story text is available below.',
        );
      }
    } finally {
      if (mounted && turn == ticket) setState(() => playing = null);
    }
  }

  Future<void> openLink(String value) async {
    final uri = Uri.tryParse(value);
    if (uri == null || uri.scheme != 'https') return;
    await stop();
    try {
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        throw StateError('Could not open link');
      }
    } catch (_) {
      if (mounted)
        setState(() => message = 'Could not open the link. Please try again.');
    }
  }

  @override
  void dispose() {
    turn++;
    unawaited(voice.stop().catchError((Object _) {}));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chapters = (widget.data['storyChapters'] as List).cast<Map>();
    final visits = (widget.data['optionalVisits'] as List).cast<Map>();
    return Scaffold(
      appBar: AppBar(title: const Text('Tour stories and visits')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            widget.data['title'] as String,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 12),
          Text(
            '${chapters.length} stories · ${(widget.data['chapters'] as List).length} outdoor stops · 21+ · Draft',
          ),
          const Text(
            'Several stories share a location. Listen to each here, or preview the walking route to hear them together as you arrive. Optional visits below are separate outings.',
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () async {
              await stop();
              if (context.mounted) Navigator.pop(context, true);
            },
            child: const Text('Preview walking route'),
          ),
          if (playing != null)
            ListTile(
              title: Text('Playing: $playing'),
              trailing: IconButton(
                tooltip: 'Stop story',
                onPressed: stop,
                icon: const Icon(Icons.stop),
              ),
            ),
          if (message.isNotEmpty) Text(message),
          for (final chapter in chapters)
            Card(
              child: ExpansionTile(
                key: ValueKey('chapter-${chapter['id']}'),
                title: Text('${chapter['id']}. ${chapter['title']}'),
                subtitle: Text(chapter['location'] as String),
                childrenPadding: const EdgeInsets.all(16),
                children: [
                  Text(chapter['locationNote'] as String),
                  TextButton.icon(
                    onPressed: () => play(
                      chapter['title'] as String,
                      chapter['text'] as String,
                    ),
                    icon: const Icon(Icons.volume_up),
                    label: const Text('Play this story'),
                  ),
                  SelectableText(chapter['text'] as String),
                  for (final source in (chapter['sources'] as Map).entries)
                    TextButton(
                      onPressed: () => openLink(source.value as String),
                      child: Text(source.key as String),
                    ),
                ],
              ),
            ),
          const SizedBox(height: 20),
          Text(
            'Optional cultural visits',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const Text(
            'These are not added to your walking route. Museum admission, travel and visiting time are extra. Confirm current access with the venue.',
          ),
          for (final visit in visits)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      visit['name'] as String,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(visit['kind'] as String),
                    Text(visit['address'] as String),
                    Text(visit['text'] as String),
                    if (visit['story'] case final String story) ...[
                      TextButton.icon(
                        onPressed: () => play(visit['name'] as String, story),
                        icon: const Icon(Icons.volume_up),
                        label: const Text('Play bonus story'),
                      ),
                      ExpansionTile(
                        title: const Text('Read bonus story'),
                        children: [SelectableText(story)],
                      ),
                    ],
                    Wrap(
                      children: [
                        TextButton(
                          onPressed: () => openLink(visit['url'] as String),
                          child: const Text('Official information'),
                        ),
                        TextButton(
                          onPressed: () => openLink(
                            Uri.https('www.google.com', '/maps/search/', {
                              'api': '1',
                              'query': '${visit['name']}, ${visit['address']}',
                            }).toString(),
                          ),
                          child: const Text('View on Google Maps'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
