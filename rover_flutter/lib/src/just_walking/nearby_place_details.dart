import 'package:flutter/material.dart';

import '../api/location_story_models.dart';

class NearbyPlaceDetails extends StatelessWidget {
  const NearbyPlaceDetails({super.key, required this.place});

  final LocationPlaceSummary place;

  @override
  Widget build(BuildContext context) {
    final details = <String>{
      if (place.shortDescription?.trim().isNotEmpty ?? false)
        place.shortDescription!.trim(),
      ...place.facts
          .map((f) => f.factText.trim())
          .where((text) => text.isNotEmpty),
    };
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    place.name,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  tooltip: 'Close details',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            if (place.address?.isNotEmpty ?? false) Text(place.address!),
            if (place.categories.isNotEmpty) Text(place.categories.join(', ')),
            const SizedBox(height: 16),
            if (details.isEmpty)
              const Text(
                'No detailed information is available for this place yet.',
              ),
            for (final detail in details)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: SelectableText(detail),
              ),
            if (place.sourceReferences.isNotEmpty) ...[
              const Divider(),
              Text('Sources', style: Theme.of(context).textTheme.titleSmall),
              for (final source in place.sourceReferences)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: SelectableText(
                    [
                      source.attribution,
                      if (source.sourceUrl?.isNotEmpty ?? false)
                        source.sourceUrl!,
                    ].join('\n'),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
