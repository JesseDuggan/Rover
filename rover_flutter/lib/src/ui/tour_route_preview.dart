import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as google;
import 'package:latlong2/latlong.dart';

import '../api/rover_api_client.dart';
import '../maps/google_maps_config.dart';
import 'journey_coverage.dart';
import 'prepared_walk_screen.dart';
import 'tour_question.dart';
import 'walking_preview.dart';

class TourRoutePreview extends StatefulWidget {
  const TourRoutePreview({
    super.key,
    required this.initialWalk,
    this.rehearsalStart,
    this.researchApproach = true,
    required this.api,
    required this.onUse,
    required this.loadWalk,
    required this.profileInterests,
    required this.pace,
  });
  final PreparedWalk initialWalk;
  final LatLng? rehearsalStart;
  final bool researchApproach;
  final void Function(PreparedWalk) onUse;
  final RoverApiClient api;
  final Future<PreparedWalk> Function(List<String>) loadWalk;
  final List<String> profileInterests;
  final String pace;
  @override
  State<TourRoutePreview> createState() => _PreviewState();
}

class _PreviewState extends State<TourRoutePreview> {
  late LatLng origin = widget.initialWalk.stops.first.point;
  google.GoogleMapController? controller;
  String focus = 'Profile';
  int budget = 45;
  bool optional = true, busy = false;
  final omitted = <String>{};
  bool included(PreparedStop s) =>
      !omitted.contains(s.name) && (optional || !s.optional);
  String message = '';
  PreparedWalk? preview;
  PreparedStop? discovery;
  Map<String, dynamic>? plan;

  List<String> get interests =>
      focus == 'Profile' ? widget.profileInterests : [focus.toLowerCase()];
  google.LatLng googlePoint(LatLng p) => google.LatLng(p.latitude, p.longitude);
  Map<String, double> coordinates(LatLng p) => {
    'latitude': p.latitude,
    'longitude': p.longitude,
  };

  void edit(VoidCallback update) => setState(() {
    update();
    plan = null;
    preview = null;
    discovery = null;
    message = '';
  });

  Future<void> locate() async {
    setState(() => busy = true);
    try {
      final point = await currentWalkStart();
      if (!mounted) return;
      edit(() => origin = point);
      await controller?.moveCamera(
        google.CameraUpdate.newLatLng(googlePoint(point)),
      );
    } catch (e) {
      if (mounted)
        setState(
          () => message =
              'Could not set current location. Tap the map to choose a start.',
        );
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<PreparedStop?> approachStory(
    JourneyCoverage path,
    List<PreparedStop> stops,
  ) async {
    if (!widget.researchApproach) return null;
    final length = path.project(stops.first.point).along;
    if (length < 180) return null;
    final target = length / 2;
    final response = await widget.api.nearbyJourneyStops(
      location: coordinates(path.at(target)),
      interests: coverageInterests(interests),
    );
    final candidates = <({String name, double along})>[];
    for (final row in (response['stops'] as List).whereType<Map>()) {
      final name = row['name'] as String;
      if (stops.any((s) => s.name.toLowerCase() == name.toLowerCase()))
        continue;
      if (foodCategory(row['category'] as String? ?? '') &&
          !interests.any(foodCategory))
        continue;
      final pos = path.project(
        LatLng(
          (row['latitude'] as num).toDouble(),
          (row['longitude'] as num).toDouble(),
        ),
      );
      if (pos.away <= 50 && pos.along > 60 && pos.along < length - 60)
        candidates.add((name: name, along: pos.along));
    }
    candidates.sort(
      (a, b) => (a.along - target).abs().compareTo((b.along - target).abs()),
    );
    for (final candidate in candidates.take(2)) {
      if (!mounted) return null;
      final anchor = path.at(candidate.along);
      final subject = PreparedStop(
        candidate.name,
        anchor,
        const WalkAnswer('', {}),
      );
      final answer = await askTourQuestion(
        widget.api,
        subject,
        'Tell one short, sourced local story about this place for someone passing nearby. Walking interests: ${interests.join(", ")}.',
      );
      if (answer != null && answer.sources.isNotEmpty)
        return PreparedStop(candidate.name, anchor, answer);
    }
    return null;
  }

  Future<void> buildPreview() async {
    if (busy) return;
    setState(() {
      busy = true;
      message = 'Finding walking directions…';
    });
    try {
      final walk = await widget.loadWalk(interests);
      final stops = walk.stops.where(included).toList();
      final result = await widget.api.planJourney(
        start: coordinates(origin),
        end: null,
        stops: [
          for (final (i, s) in stops.indexed)
            {
              'id': 'chapter-$i',
              'name': s.name,
              'category': 'Tour stop',
              ...coordinates(s.point),
            },
        ],
        suggest: false,
        minutes: budget,
        interests: interests,
        pace: previewPace(widget.pace),
      );
      if (!mounted) return;
      final path = [
        for (final p in result['coordinates'] as List)
          LatLng(
            (p['latitude'] as num).toDouble(),
            (p['longitude'] as num).toDouble(),
          ),
      ];
      if (path.length < 2) throw StateError('No pedestrian route returned');
      setState(() {
        plan = result;
        preview = PreparedWalk(
          walk.title,
          path,
          stops,
          theme: walk.theme,
          orderedChapters: true,
        );
        message = 'Checking for a story on the way to the first stop…';
      });
      final coverage = JourneyCoverage(path);
      try {
        final story = await approachStory(coverage, stops);
        if (mounted)
          setState(() {
            discovery = story;
            message = story != null
                ? 'On the way: ${story.name}'
                : 'No additional story on this approach.';
          });
      } catch (_) {
        if (mounted)
          setState(
            () => message =
                'Approach research unavailable. Your tour chapters are ready.',
          );
      }
    } catch (_) {
      if (mounted)
        setState(
          () => message = 'Walking directions unavailable. Choose a reachable start and try again.',
        );
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final walk = preview;
    final stops =
        walk?.stops ?? widget.initialWalk.stops.where(included).toList();
    return Scaffold(
      appBar: AppBar(title: Text(widget.initialWalk.title)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'Tap the map where you want to begin, or use your current location.',
            ),
            if (Platform.isAndroid && const GoogleMapsConfig().hasApiKey)
              SizedBox(
                height: 290,
                child: google.GoogleMap(
                  initialCameraPosition: google.CameraPosition(
                    target: googlePoint(origin),
                    zoom: 15,
                  ),
                  onMapCreated: (c) => controller = c,
                  onTap: busy
                      ? null
                      : (p) => edit(
                          () => origin = LatLng(p.latitude, p.longitude),
                        ),
                  markers: {
                    google.Marker(
                      markerId: const google.MarkerId('start'),
                      position: googlePoint(origin),
                      icon: google.BitmapDescriptor.defaultMarkerWithHue(120),
                      infoWindow: const google.InfoWindow(title: 'Your start'),
                    ),
                    for (final s in stops)
                      google.Marker(
                        markerId: google.MarkerId(s.name),
                        position: googlePoint(s.point),
                        infoWindow: google.InfoWindow(title: s.name),
                      ),
                  },
                  polylines: {
                    if (walk != null)
                      google.Polyline(
                        polylineId: const google.PolylineId('route'),
                        points: walk.path.map(googlePoint).toList(),
                        color: Colors.indigo,
                        width: 5,
                      ),
                  },
                ),
              ),
            TextButton.icon(
              onPressed: busy ? null : locate,
              icon: const Icon(Icons.my_location),
              label: const Text('Use my current location'),
            ),
            if (widget.rehearsalStart case final testStart?)
              TextButton.icon(
                icon: const Icon(Icons.pin_drop_outlined),
                label: const Text('Use shared test start'),
                onPressed: busy
                    ? null
                    : () {
                        edit(() => origin = testStart);
                        controller?.moveCamera(
                          google.CameraUpdate.newLatLng(googlePoint(testStart)),
                        );
                      },
              ),
            DropdownButtonFormField<int>(
              initialValue: budget,
              decoration: const InputDecoration(labelText: 'Time budget'),
              items: [
                for (int n = 15; n <= 240; n += 5)
                  DropdownMenuItem(value: n, child: Text('$n min')),
              ],
              onChanged: busy ? null : (n) => edit(() => budget = n!),
            ),
            Wrap(
              spacing: 8,
              children: [
                for (final value in ['Profile', 'History', 'Architecture'])
                  ChoiceChip(
                    label: Text(value),
                    selected: focus == value,
                    onSelected: busy ? null : (_) => edit(() => focus = value),
                  ),
              ],
            ),
            if (widget.initialWalk.stops.any((s) => s.optional))
              SwitchListTile(
                value: optional,
                title: Text(
                  'Include ${widget.initialWalk.stops.where((s) => s.optional).map((s) => s.name).join(", ")}',
                ),
                onChanged: busy ? null : (v) => edit(() => optional = v),
              ),
            ExpansionTile(
              title: const Text('Choose featured stops'),
              children: [
                for (final s in widget.initialWalk.stops.where(
                  (s) => !s.optional,
                ))
                  CheckboxListTile(
                    title: Text(s.name),
                    value: !omitted.contains(s.name),
                    onChanged: busy
                        ? null
                        : (checked) => edit(() {
                            if (checked == true) {
                              omitted.remove(s.name);
                            } else {
                              omitted.add(s.name);
                            }
                          }),
                  ),
              ],
            ),
            FilledButton(
              onPressed: busy || stops.isEmpty ? null : buildPreview,
              child: const Text('Preview walking route'),
            ),
            if (message.isNotEmpty) Text(message),
            if (plan != null && walk != null) ...[
              WalkingPreview(
                plan: plan!,
                geometry: walk.path,
                budget: budget,
                first: stops.first.point,
                firstName: stops.first.name,
                names: stops.map((s) => s.name).toList(),
              ),
              ExpansionTile(
                title: Text('First story · ${stops.first.name}'),
                children: [Text(stops.first.story.text)],
              ),
              FilledButton(
                onPressed: busy
                    ? null
                    : () => widget.onUse(
                        PreparedWalk(
                          walk.title,
                          walk.path,
                          [if (discovery case final story?) story, ...stops],
                          theme: walk.theme,
                          orderedChapters: true,
                        ),
                      ),
                child: const Text('Use this walk'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
