import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api/adaptive_route_story_models.dart';
import 'story_images.dart';

class AreaStoryDetails extends StatefulWidget {
  const AreaStoryDetails({super.key, required this.story, this.coverageLabel});
  final AdaptiveRouteStory story;
  final String? coverageLabel;
  @override
  State<AreaStoryDetails> createState() => _AreaStoryDetailsState();
}

class _AreaStoryDetailsState extends State<AreaStoryDetails> {
  String _length = 'Standard';
  AdaptiveRouteStory get story => widget.story;
  String? get coverageLabel => widget.coverageLabel;
  @override
  Widget build(BuildContext context) {
    final variants = [...story.variants]
      ..sort(
        (a, b) =>
            b.estimatedDurationSeconds.compareTo(a.estimatedDurationSeconds),
      );
    final selected =
        variants.where((v) => v.length == _length).firstOrNull ??
        variants.firstOrNull;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    story.title,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  tooltip: 'Close story',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (coverageLabel != null) Text(coverageLabel!),
            if (story.sensitivityNotice case final notice?)
              Text(notice, style: const TextStyle(fontWeight: FontWeight.w600)),
            if (story.uncertainClaims.isNotEmpty)
              Text('Source uncertainty: ${story.uncertainClaims.join(' ')}'),
            StoryImages(
              sourceUrls: story.sources
                  .map((s) => s.url)
                  .whereType<String>()
                  .toList(),
            ),
            if (variants.length > 1)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: DropdownButtonFormField<String>(
                  initialValue: selected?.length,
                  decoration: const InputDecoration(labelText: 'Story length'),
                  items: variants
                      .map(
                        (v) => DropdownMenuItem(
                          value: v.length,
                          child: Text(
                            '${v.length == 'Deep' ? 'Extended' : v.length} - ${v.estimatedDurationSeconds} sec',
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (value) =>
                      setState(() => _length = value ?? 'Standard'),
                ),
              ),
            SelectableText(
              selected == null ? 'No narration available.' : selected.narration,
            ),
            const Divider(),
            Text('Sources', style: Theme.of(context).textTheme.titleSmall),
            for (final source in story.sources)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(source.title ?? source.providerName),
                subtitle: Text(source.attribution),
                trailing: const Icon(Icons.open_in_new),
                onTap: () async {
                  final uri = Uri.tryParse(source.url ?? '');
                  var opened = false;
                  if (uri != null && ['https', 'http'].contains(uri.scheme)) {
                    try {
                      opened = await launchUrl(
                        uri,
                        mode: LaunchMode.externalApplication,
                      );
                    } catch (_) {
                      opened = false;
                    }
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
      ),
    );
  }
}
