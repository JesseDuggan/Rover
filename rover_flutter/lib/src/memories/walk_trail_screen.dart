import 'package:flutter/material.dart';

import '../location/rover_location.dart';
import '../maps/rover_map_view.dart';
import 'walk_trail_store.dart';

class WalkTrailScreen extends StatefulWidget {
  const WalkTrailScreen({
    super.key,
    required this.sessionId,
    required this.store,
    required this.beforeDelete,
  });
  final String sessionId;
  final WalkTrailStore store;
  final VoidCallback beforeDelete;
  @override
  State<WalkTrailScreen> createState() => _WalkTrailScreenState();
}

class _WalkTrailScreenState extends State<WalkTrailScreen> {
  List<Map<String, dynamic>> points = [];
  int? segment;
  bool busy = true;
  String? error;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final result = await widget.store.read(widget.sessionId);
      if (mounted) {
        setState(() {
          points = result;
          segment = points.isEmpty ? null : points.last['segment'] as int;
        });
      }
    } catch (_) {
      if (mounted) setState(() => error = 'Could not read this trail.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> remove() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Delete recorded GPS trail?'),
        content: const Text(
          'This removes the local trail and stops recording. Your walk and memories are kept.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    setState(() => busy = true);
    widget.beforeDelete();
    try {
      await widget.store.delete(widget.sessionId);
      if (mounted) {
        setState(() {
          points = [];
          segment = null;
        });
      }
    } catch (_) {
      if (mounted) setState(() => error = 'Could not delete this trail.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final segments = points.map((p) => p['segment'] as int).toSet().toList();
    final selected = points.where((p) => p['segment'] == segment).toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Recorded GPS trail'),
        actions: [
          IconButton(
            tooltip: 'Delete local trail',
            onPressed: busy || points.isEmpty ? null : remove,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: Column(
        children: [
          if (busy) const LinearProgressIndicator(),
          ListTile(
            title: const Text('Private on this device'),
            subtitle: Text(
              error ??
                  (points.isEmpty
                      ? 'No recorded GPS fixes for this walk'
                      : '${points.length} recorded GPS fixes'),
            ),
          ),
          if (segments.length > 1)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: DropdownButtonFormField<int>(
                initialValue: segment,
                decoration: const InputDecoration(
                  labelText: 'Recording segment',
                ),
                items: [
                  for (final s in segments)
                    DropdownMenuItem(value: s, child: Text('Segment ${s + 1}')),
                ],
                onChanged: (value) => setState(() => segment = value),
              ),
            ),
          if (selected.isNotEmpty)
            Expanded(
              child: LayoutBuilder(
                builder: (context, box) => RoverMapView(
                  key: ValueKey(segment),
                  currentLocation: RoverLatLng(
                    latitude: (selected.last['latitude'] as num).toDouble(),
                    longitude: (selected.last['longitude'] as num).toDouble(),
                  ),
                  routeGeometry: [
                    for (final p in selected)
                      RoverLatLng(
                        latitude: (p['latitude'] as num).toDouble(),
                        longitude: (p['longitude'] as num).toDouble(),
                      ),
                  ],
                  orderedStops: const [],
                  overview: true,
                  enableExpand: false,
                  height: box.maxHeight,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
