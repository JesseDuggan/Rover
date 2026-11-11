import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as google;

import '../maps/google_maps_config.dart';

/// A catalogue entry is not necessarily an independent route waypoint.
List<Map> tourDestinations(List<Map> locations) => locations
    .where(
      (r) =>
          r['destinationId'] == r['id'] &&
          r['latitude'] != null &&
          r['longitude'] != null,
    )
    .toList();

Uri? tourLocationDirections(Map location) {
  if (location['destinationId'] == null || location['latitude'] == null) {
    return null;
  }
  return Uri.https('www.google.com', '/maps/dir/', {
    'api': '1',
    'destination': '${location['latitude']},${location['longitude']}',
    if (location['placeId'] != null && location['type'] != 'historic_marker')
      'destination_place_id': location['placeId'] as String,
    'travelmode': location['visit_mode'] == 'walk' ? 'walking' : 'driving',
  });
}

class TourLocations extends StatefulWidget {
  const TourLocations({
    super.key,
    required this.data,
    required this.openLink,
    required this.play,
    required this.stop,
  });
  final Map<String, dynamic> data;
  final Future<void> Function(String) openLink;
  final Future<void> Function(String, String) play;
  final Future<void> Function() stop;
  @override
  State<TourLocations> createState() => _TourLocationsState();
}

class _TourLocationsState extends State<TourLocations> {
  String? selected;
  @override
  Widget build(BuildContext context) {
    final rows = (widget.data['locations'] as List).cast<Map>();
    final destinations = tourDestinations(rows);
    final selectedRow = rows.where((r) => r['id'] == selected).firstOrNull;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          '16 records · 13 destinations · 4 core walking stops',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        const Text(
          'Choose a pin or a card to see its story and visiting options. Optional visits and nightlife are separate outings and do not change your core walk.',
        ),
        const SizedBox(height: 12),
        if (Platform.isAndroid && const GoogleMapsConfig().hasApiKey)
          SizedBox(
            height: 300,
            child: google.GoogleMap(
              initialCameraPosition: const google.CameraPosition(
                target: google.LatLng(36.139, -115.156),
                zoom: 11,
              ),
              myLocationButtonEnabled: false,
              markers: {
                for (final r in destinations)
                  google.Marker(
                    markerId: google.MarkerId(r['id'] as String),
                    position: google.LatLng(
                      (r['latitude'] as num).toDouble(),
                      (r['longitude'] as num).toDouble(),
                    ),
                    icon: google.BitmapDescriptor.defaultMarkerWithHue(
                      r['group'] == 'core'
                          ? 210
                          : r['group'] == 'nightlife'
                          ? 300
                          : 30,
                    ),
                    infoWindow: google.InfoWindow(title: r['name'] as String),
                    onTap: () => setState(() => selected = r['id'] as String),
                  ),
              },
            ),
          )
        else
          const Text(
            'The Google map is available in the configured Android app. All locations are listed below.',
          ),
        if (selectedRow != null) details(selectedRow),
        for (final group in const {
          'core': 'Core walking route (4)',
          'story_only': 'Historical story chapters (2)',
          'optional': 'Optional visits (5, including The Underground)',
          'nightlife': 'Optional nightlife · rideshare (5)',
        }.entries) ...[
          Padding(
            padding: const EdgeInsets.only(top: 20, bottom: 8),
            child: Text(
              group.value,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          for (final r in rows.where((r) => r['group'] == group.key))
            Card(
              child: ListTile(
                key: ValueKey('location-${r['id']}'),
                selected: selected == r['id'],
                title: Text(r['name'] as String),
                subtitle: Text('${r['id']} · ${label(r)}'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  setState(() => selected = r['id'] as String);
                  await showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    builder: (_) => SafeArea(
                      child: SingleChildScrollView(child: details(r)),
                    ),
                  );
                },
              ),
            ),
        ],
      ],
    );
  }

  String label(Map r) => switch (r['visit_mode']) {
    'walk' => 'Core walk',
    'inside_LVAD005' => 'Inside Mob Museum · optional',
    'shared_geofence_LVAD003' => 'Shares Block 16 · separate story',
    'audio_only_no_map_pin' => 'Audio only · no verified pin',
    'public_view_only' => 'Historic site · public exterior only',
    _ => 'Separate visit · rideshare',
  };

  Widget details(Map r) {
    final stories = (widget.data['storyChapters'] as List)
        .cast<Map>()
        .where((s) => (r['storyIds'] as List).contains(s['storyId']))
        .toList();
    final destination = r['parentId'] == null
        ? r
        : (widget.data['locations'] as List).cast<Map>().firstWhere(
            (p) => p['id'] == r['parentId'],
          );
    final directions = tourLocationDirections(destination);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            r['name'] as String,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          Text(label(r)),
          if ((r['address'] as String).isNotEmpty) Text(r['address'] as String),
          if (r['note'] != null) Text(r['note'] as String),
          if (stories.isEmpty && r['bonusStory'] == null)
            const Text('No curated narration attached yet.'),
          for (final s in stories) ...[
            TextButton.icon(
              onPressed: () =>
                  widget.play(s['title'] as String, s['text'] as String),
              icon: const Icon(Icons.volume_up),
              label: Text('Play: ${s['title']}'),
            ),
            ExpansionTile(
              title: const Text('Read story'),
              children: [SelectableText(s['text'] as String)],
            ),
          ],
          if (r['bonusStory'] != null) ...[
            TextButton.icon(
              onPressed: () =>
                  widget.play(r['name'] as String, r['bonusStory'] as String),
              icon: const Icon(Icons.volume_up),
              label: const Text('Play bonus story'),
            ),
            ExpansionTile(
              title: const Text('Read bonus story'),
              children: [SelectableText(r['bonusStory'] as String)],
            ),
          ],
          if (stories.isNotEmpty || r['bonusStory'] != null)
            TextButton(onPressed: widget.stop, child: const Text('Stop audio')),
          if (directions != null)
            TextButton.icon(
              onPressed: () => widget.openLink(directions.toString()),
              icon: const Icon(Icons.directions),
              label: Text(
                r['visit_mode'] == 'rideshare'
                    ? 'Driving directions for a rideshare visit'
                    : 'Directions on Google Maps',
              ),
            ),
          if (r['sourceUrl'] != null)
            TextButton(
              onPressed: () => widget.openLink(r['sourceUrl'] as String),
              child: const Text('Location source'),
            ),
          if (r['officialUrl'] != null)
            TextButton(
              onPressed: () => widget.openLink(r['officialUrl'] as String),
              child: const Text('Official venue information'),
            ),
        ],
      ),
    );
  }
}
