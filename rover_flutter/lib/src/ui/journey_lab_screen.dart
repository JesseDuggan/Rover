import '../voice/spoken_location.dart';

import 'dart:async';

import 'prepared_walk_screen.dart';

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as google;

import '../maps/google_maps_config.dart';
import '../voice/rover_audio_services.dart';
import '../api/story_question_models.dart';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:path_provider/path_provider.dart';

import '../api/adaptive_route_story_models.dart';
import '../api/location_story_models.dart';
import '../api/rover_api_client.dart';
import '../drives/drive_narration.dart';
import '../drives/scenic_drive.dart';
import '../just_walking/area_story_details.dart';
import '../just_walking/area_walking_controller.dart';
import '../location/rover_location.dart';
import '../preferences/preferences_controller.dart';

typedef _Json = Map<String, dynamic>;

LatLng _point(_Json json) {
  final lat = (json['latitude'] as num).toDouble();
  final lng = (json['longitude'] as num).toDouble();
  if (!lat.isFinite || !lng.isFinite || lat.abs() > 90 || lng.abs() > 180) {
    throw const FormatException('Invalid route coordinate');
  }
  return LatLng(lat, lng);
}

Map<String, double> _coordinates(LatLng point) => {
  'latitude': point.latitude,
  'longitude': point.longitude,
};

List<_Json> _rows(_Json json, String key) => (json[key] as List).cast<_Json>();

enum _Tap { start, end, stop }

class JourneyLabScreen extends StatefulWidget {
  const JourneyLabScreen({super.key, this.client});
  final RoverApiClient? client;

  @override
  State<JourneyLabScreen> createState() => _JourneyLabState();
}

class _JourneyLabState extends State<JourneyLabScreen> {
  late final api = widget.client ?? RoverApiClient();
  final mapKey = GlobalKey();
  final map = MapController();
  static const initialCenter = LatLng(43.65, -79.38);
  google.GoogleMapController? googleController;
  bool get googleEnabled =>
      Platform.isAndroid && const GoogleMapsConfig().hasApiKey;
  String scope = 'Neighbourhood';
  final query = TextEditingController();
  _Tap mode = _Tap.start;
  LatLng? start, end;
  List<_Json> stops = [];
  List<LatLng> geometry = [];
  _Json? plan, area;
  Map<String, dynamic> stories = {};
  String? working;
  String status = '';
  int minutes = 60, next = 0;
  final speech = DeviceTextToSpeech();
  int playbackId = 0;
  String? playingTitle;
  String playingText = '';
  LatLng? simulatedPosition;
  int? replacing;
  bool get busy => working != null;
  List<String> get interests =>
      PreferencesScope.of(context).preferences.interests;

  @override
  void dispose() {
    playbackId++;
    if (playingTitle != null) unawaited(speech.stop());
    if (widget.client == null) api.close(force: true);
    googleController = null;
    map.dispose();
    query.dispose();
    super.dispose();
  }

  Future<void> run(String label, Future<void> Function() action) async {
    if (busy) return;
    setState(() {
      working = label;
      status = '';
    });
    try {
      await action();
    } catch (e) {
      if (mounted) setState(() => status = '$label failed. $e');
    } finally {
      if (mounted) setState(() => working = null);
    }
  }

  void edit(VoidCallback change) => setState(() {
    change();
    plan = null;
    geometry = [];
    area = null;
    stories = {};
    next = 0;
    status = '';
    replacing = null;
  });

  Future<_Json?> choose(String title, List<_Json> rows) {
    return showModalBottomSheet<_Json>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              title: Text(title, style: Theme.of(context).textTheme.titleLarge),
            ),
            if (rows.isEmpty) const ListTile(title: Text('No places found')),
            for (final row in rows)
              ListTile(
                title: Text(row['name'] as String),
                subtitle: Text(
                  [
                    row['address'],
                    row['category'],
                    row['attribution'],
                    row['sourceUrl'],
                  ].whereType<String>().join('\n'),
                ),
                onTap: () => Navigator.pop(context, row),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> search() => run('Searching places', () async {
    final result = await api.searchJourneyPlaces(query.text.trim());
    if (!mounted) return;
    final place = await choose('Move map to a place', _rows(result, 'stops'));
    if (mounted && place != null) move(_point(place), 15);
  });

  void tap(LatLng location) {
    if (busy) return;
    if (mode == _Tap.start) {
      edit(() {
        start = location;
        mode = _Tap.end;
      });
    } else if (mode == _Tap.end) {
      edit(() {
        end = location;
        mode = _Tap.stop;
      });
    } else {
      run('Finding nearby places', () async {
        if (replacing == null && stops.length >= 20) {
          throw StateError('Maximum 20 stops');
        }
        final result = await api.nearbyJourneyStops(
          location: _coordinates(location),
          interests: interests,
        );
        if (!mounted) return;
        final place = await choose(
          'Choose a named stop',
          _rows(result, 'stops'),
        );
        if (!mounted || place == null) return;
        if (stops.indexed.any(
          (entry) => entry.$1 != replacing && entry.$2['id'] == place['id'],
        )) {
          throw StateError('This place is already a stop');
        }
        edit(() {
          if (replacing case final index?) {
            stops[index] = place;
          } else {
            stops.add(place);
          }
        });
      });
    }
  }

  Future<void> route(bool suggest) =>
      run(suggest ? 'Finding suggestions' : 'Building walking route', () async {
        if (suggest && stops.isNotEmpty) {
          final replace = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Replace current stops?'),
              content: const Text(
                'Suggestions will replace the ordered stops. You can edit the new list before building.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Replace stops'),
                ),
              ],
            ),
          );
          if (!mounted || replace != true) return;
        }
        final result = await api.planJourney(
          start: _coordinates(start!),
          end: end == null ? null : _coordinates(end!),
          stops: suggest ? [] : stops,
          suggest: suggest,
          minutes: minutes,
          interests: interests,
        );
        if (!mounted) return;
        final ordered = _rows(result, 'stops')
            .map(
              (s) => <String, dynamic>{
                ...?stops.where((p) => p['id'] == s['id']).firstOrNull,
                ...s,
              },
            )
            .toList();
        if (ordered.length > 20) {
          throw StateError('Planner returned more than 20 stops');
        }
        if (suggest) {
          edit(() => stops = ordered);
          status = 'Review the stops, then build the walking route.';
        } else {
          final points = _rows(result, 'coordinates').map(_point).toList();
          if (points.length < 2) {
            throw StateError('No walking geometry available');
          }
          edit(() => stops = ordered);
          setState(() {
            plan = result;
            geometry = points;
          });
          fit();
        }
      });

  google.LatLng googlePoint(LatLng p) => google.LatLng(p.latitude, p.longitude);

  Future<void> moveCamera(google.CameraUpdate update) async {
    final controller = googleController;
    if (controller == null || !mounted) return;
    try {
      await controller.moveCamera(update);
    } on StateError {
      // The platform view was detached while a camera update was in flight.
      if (identical(controller, googleController)) googleController = null;
    } on PlatformException catch (error) {
      debugPrint('Journey Lab map unavailable: ${error.code}');
    }
  }

  void move(LatLng target, double zoom) {
    if (googleEnabled) {
      unawaited(
        moveCamera(
          google.CameraUpdate.newLatLngZoom(googlePoint(target), zoom),
        ),
      );
    } else {
      map.move(target, zoom);
    }
  }

  Widget googleMap() {
    google.Marker pin(String id, String label, LatLng point, double hue) =>
        google.Marker(
          markerId: google.MarkerId(id),
          position: googlePoint(point),
          infoWindow: google.InfoWindow(title: label),
          icon: google.BitmapDescriptor.defaultMarkerWithHue(hue),
        );
    return google.GoogleMap(
      initialCameraPosition: google.CameraPosition(
        target: googlePoint(initialCenter),
        zoom: 11,
      ),
      onMapCreated: (controller) {
        if (!mounted) return;
        googleController = controller;
        if (geometry.isNotEmpty) fit();
      },
      gestureRecognizers: {
        Factory<OneSequenceGestureRecognizer>(EagerGestureRecognizer.new),
      },
      onTap: (p) => tap(LatLng(p.latitude, p.longitude)),
      markers: {
        if (simulatedPosition case final p?)
          pin('simulation', 'Simulated walker', p, 210),
        if (start case final p?) pin('start', 'Start', p, 120),
        if (end case final p?) pin('end', 'End', p, 0),
        for (final (i, s) in stops.indexed)
          pin('poi-${s['id']}', '${i + 1}. ${s['name']}', _point(s), 240),
      },
      polylines: {
        if (geometry.isNotEmpty)
          google.Polyline(
            polylineId: const google.PolylineId('walk'),
            points: geometry.map(googlePoint).toList(),
            width: 5,
            color: Colors.indigo,
          ),
      },
    );
  }

  void fit() {
    if (geometry.isEmpty) return;
    if (googleEnabled) {
      final lats = geometry.map((p) => p.latitude);
      final lons = geometry.map((p) => p.longitude);
      final bounds = google.LatLngBounds(
        southwest: google.LatLng(lats.reduce(math.min), lons.reduce(math.min)),
        northeast: google.LatLng(lats.reduce(math.max), lons.reduce(math.max)),
      );
      unawaited(moveCamera(google.CameraUpdate.newLatLngBounds(bounds, 40)));
      return;
    }
    map.fitCamera(
      CameraFit.coordinates(
        coordinates: geometry,
        padding: const EdgeInsets.all(35),
        maxZoom: 17,
      ),
    );
  }

  DrivePlace subject(_Json stop) {
    final point = _point(stop);
    return DrivePlace(
      id: stop['id'],
      name: stop['name'],
      location: RoverLatLng(
        latitude: point.latitude,
        longitude: point.longitude,
      ),
    );
  }

  String journeyQuestion(List<String> selectedInterests) {
    String pin(LatLng p) =>
        '${p.latitude.toStringAsFixed(4)}, ${p.longitude.toStringAsFixed(4)}';
    final finish = end ?? (stops.isEmpty ? start! : _point(stops.last));
    final prompt =
        'Introduce this ${scope.toLowerCase()} walk from ${pin(start!)} to ${pin(finish)}. '
        'Use place names in narration; omit coordinates. Include sourced local history, former landmarks or neighbourhood festivals where relevant. Interests: ${selectedInterests.join(', ')}. '
        'Stops in walking order: ${stops.map((s) => s['name']).join(', ')}.';
    return prompt.length <= 500 ? prompt : prompt.substring(0, 500);
  }

  Future<void> previewJourney({_Json? onlyStop}) async {
    if (busy ||
        stops.isEmpty ||
        start == null ||
        (onlyStop == null && plan == null))
      return;
    final id = ++playbackId;
    bool active() => mounted && id == playbackId;
    await run('Playing test journey', () async {
      try {
        setState(() {
          playingTitle = 'Starting your journey';
          playingText = 'Preparing narration…';
          simulatedPosition = start;
        });
        final mapContext = mapKey.currentContext;
        if (onlyStop == null && mapContext != null) {
          await Scrollable.ensureVisible(mapContext, alignment: 0.1);
        }
        if (!active()) return;
        await speech.configure(rate: 0.5);
        if (!active()) return;
        Future<void> narrate(String title, String words) async {
          setState(() {
            playingTitle = title;
            playingText = spokenLocationText(words);
          });
          await speech.speak(words);
        }

        final intro = area == null ? null : introduction(area!);
        if (onlyStop == null && intro != null) {
          await narrate(
            intro.title,
            intro.variants
                .firstWhere((v) => v.narration.trim().isNotEmpty)
                .narration,
          );
        }
        final nearby = <AdaptiveRouteStory>[];
        final covered = <String>{
          for (final stop in stops) stop['name'] as String,
          if (intro != null) intro.title,
        };
        LatLng? searchedAt;
        Future<void> betweenStops(LatLng point) async {
          const distance = Distance();
          if (searchedAt == null || distance(searchedAt!, point) >= 750) {
            searchedAt = point;
            setState(() {
              playingTitle = 'Between stops';
              playingText = 'Looking for a neighbourhood story…';
            });
            try {
              final result = await api.researchAreaStories(
                latitude: point.latitude,
                longitude: point.longitude,
                interests: interests,
                excludedTitles: covered
                    .where((t) => t.length <= 160)
                    .take(120)
                    .toList(),
              );
              if (!active()) return;
              nearby.addAll(AreaStoryCollection.fromJson(result).stories);
            } catch (_) {
              // An unavailable neighbourhood story must not interrupt arrivals.
            }
          }
          if (!active()) return;
          final story = nearby
              .where(
                (s) =>
                    s.canAutoplay &&
                    s.sources.isNotEmpty &&
                    s.claims.isNotEmpty &&
                    s.expiresUtc?.isAfter(DateTime.now().toUtc()) == true &&
                    s.variants.any((v) => v.narration.trim().isNotEmpty) &&
                    !covered.any(
                      (title) =>
                          title.trim().toLowerCase() ==
                          s.title.trim().toLowerCase(),
                    ) &&
                    distance(
                          point,
                          LatLng(s.relevanceLatitude, s.relevanceLongitude),
                        ) <=
                        1000,
              )
              .firstOrNull;
          if (story == null) return;
          covered.add(story.title);
          await narrate(
            'Between stops · ${story.title}',
            story.variants
                .firstWhere((v) => v.narration.trim().isNotEmpty)
                .narration,
          );
        }

        var cursor = 0;
        Future<void> travel(int target) async {
          const distance = Distance();
          var length = 0.0;
          for (var j = cursor; j < target; j++) {
            length += distance(geometry[j], geometry[j + 1]);
          }
          var travelled = 0.0;
          var playedMidpoint = false;
          final stride = math.max(1, ((target - cursor) / 10).ceil());
          while (cursor < target && active()) {
            final nextIndex = math.min(target, cursor + stride);
            for (var j = cursor; j < nextIndex; j++) {
              final from = geometry[j], to = geometry[j + 1];
              final segment = distance(from, to);
              if (!playedMidpoint &&
                  length >= 100 &&
                  travelled + segment >= length / 2 &&
                  segment > 0) {
                playedMidpoint = true;
                final fraction = (length / 2 - travelled) / segment;
                final midpoint = LatLng(
                  from.latitude + (to.latitude - from.latitude) * fraction,
                  from.longitude + (to.longitude - from.longitude) * fraction,
                );
                setState(() => simulatedPosition = midpoint);
                move(midpoint, 16);
                await betweenStops(midpoint);
                if (!active()) return;
              }
              travelled += segment;
            }
            cursor = nextIndex;
            final point = geometry[cursor];
            setState(() {
              simulatedPosition = point;
            });
            move(point, 16);
            await Future<void>.delayed(const Duration(milliseconds: 160));
          }
        }

        for (var i = 0; i < stops.length && active(); i++) {
          final stop = stops[i];
          if (onlyStop != null && onlyStop != stop) continue;
          final point = _point(stop);
          var nearest = cursor;
          for (var j = cursor; j < geometry.length; j++) {
            if (const Distance()(geometry[j], point) <
                const Distance()(geometry[nearest], point))
              nearest = j;
          }
          setState(() {
            playingTitle = 'Walking to ${stop['name']}';
            playingText = '';
          });
          if (onlyStop == null) await travel(nearest);
          if (!active()) return;
          setState(() => next = i + 1);
          if (verified(stop) == null) {
            setState(() {
              playingTitle = 'Preparing story ${i + 1} of ${stops.length}';
              playingText = 'Researching ${stop['name']}…';
            });
            await narrate(
              'Preparing story',
              'Finding a story about ${stop['name']}.',
            );
            if (!active()) return;
            await researchStop(stop, interests);
            if (!active()) return;
          }
          final story = verified(stop);
          await narrate(
            '${i + 1}. ${stop['name']}',
            story?.shortSpokenNarration ??
                'No verified story is available for ${stop['name']}.',
          );
        }
        if (active() && onlyStop == null) await travel(geometry.length - 1);
        if (active())
          setState(
            () => status = onlyStop == null
                ? 'Test journey complete.'
                : 'Story finished.',
          );
      } catch (error) {
        if (active()) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Playback stopped: $error')));
          rethrow;
        }
      } finally {
        if (mounted)
          setState(() {
            playingTitle = null;
            simulatedPosition = null;
          });
      }
    });
  }

  Future<void> stopPreview() async {
    playbackId++;
    await speech.stop();
  }

  Future<void> generate() => run('Generating stories', () async {
    final issues = <String>[];
    final selectedInterests = interests;
    if (area == null) {
      try {
        final _Json result;
        if (scope == 'Region') {
          result = await api.researchAreaStories(
            latitude: start!.latitude,
            longitude: start!.longitude,
            interests: selectedInterests,
            excludedTitles: [],
            searchRadiusMeters: 20000,
          );
        } else {
          final response = await api.researchStoryQuestion(
            StoryQuestionRequest(
              question: journeyQuestion(selectedInterests),
              location: RoverLatLng(
                latitude: start!.latitude,
                longitude: start!.longitude,
              ),
              scope: scope,
              format: 'Single',
              storyCount: 1,
            ),
          );
          result = {
            'status': response.status,
            'stories': [
              for (final answer in response.answers)
                {
                  ...answer.story.toJson(),
                  'variants': [answer.variant.toJson()],
                },
            ],
          };
        }
        if (!mounted) return;
        if (introduction(result) == null) {
          issues.add('No sourced area introduction available.');
        } else {
          setState(() => area = result);
        }
      } catch (e) {
        issues.add('Area research failed. $e');
      }
    }
    for (final stop in stops) {
      if (!mounted) return;
      final place = subject(stop);
      if (verified(stop) != null) continue;
      setState(() => working = 'Researching ${place.name}');
      try {
        await researchStop(stop, selectedInterests);
        if (!mounted) return;
        if (verified(stop) == null) {
          issues.add('No verified story for ${place.name}.');
        }
      } catch (e) {
        issues.add('${place.name}: $e');
      }
    }
    if (mounted) {
      setState(
        () => status = issues.isEmpty ? 'Stories ready.' : issues.join('\n'),
      );
    }
  });

  Future<void> researchStop(_Json stop, List<String> selectedInterests) async {
    final place = subject(stop);
    final result = await api.createDriveStopStory(
      id: place.id,
      interests: selectedInterests,
      journeyStart: _coordinates(start!),
      journeyEnd: _coordinates(end ?? _point(stops.last)),
      name: place.name,
      latitude: place.location.latitude,
      longitude: place.location.longitude,
    );
    if (mounted && usableDriveStory(result, place, DateTime.now().toUtc())) {
      setState(() => stories[place.id] = result.toJson());
    }
  }

  static AdaptiveRouteStory? introduction(_Json result) =>
      AreaStoryCollection.fromJson(result).stories
          .where(
            (s) =>
                s.sources.isNotEmpty &&
                s.variants.any((v) => v.narration.trim().isNotEmpty),
          )
          .firstOrNull;

  LocationStoryResponse? verified(_Json stop) {
    final raw = stories[stop['id']];
    if (raw == null) return null;
    final result = LocationStoryResponse.fromJson(
      Map<String, dynamic>.from(raw as Map),
    );
    return usableDriveStory(result, subject(stop), DateTime.now().toUtc())
        ? result
        : null;
  }

  Future<File> savedFile() async => File(
    '${(await getApplicationSupportDirectory()).path}/journey-lab-v1.json',
  );

  Future<void> save() => run('Saving route', () async {
    final file = await savedFile();
    await file.parent.create(recursive: true);
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(
      jsonEncode({
        'start': _coordinates(start!),
        'end': end == null ? null : _coordinates(end!),
        'minutes': minutes,
        'scope': scope,
        'stops': stops,
        'plan': plan,
        'area': area,
        'stories': stories,
        'next': next,
      }),
      flush: true,
    );
    await temp.rename(file.path);
    if (mounted) setState(() => status = 'Test route saved on this device.');
  });

  Future<void> reopen() => run('Reopening route', () async {
    final file = await savedFile();
    if (!await file.exists()) {
      if (mounted) setState(() => status = 'No saved test route yet.');
      return;
    }
    final data = jsonDecode(await file.readAsString()) as _Json;
    final origin = _point(data['start']);
    final destination = data['end'] == null ? null : _point(data['end']);
    final ordered = _rows(data, 'stops').toList();
    final savedPlan = data['plan'] as _Json;
    final points = _rows(savedPlan, 'coordinates').map(_point).toList();
    if (!mounted) return;
    setState(() {
      start = origin;
      end = destination;
      stops = ordered;
      plan = savedPlan;
      geometry = points;
      minutes = data['minutes'];
      scope = data['scope'] ?? 'Neighbourhood';
      area = data['area'];
      stories = data['stories'];
      next = data['next'];
      mode = _Tap.stop;
      replacing = null;
    });
    fit();
  });

  void openPrepared(PreparedWalk walk) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PreparedWalkScreen(
          walk: walk,
          research: (stop) async {
            final result = await api.researchStoryQuestion(
              StoryQuestionRequest(
                location: RoverLatLng(
                  latitude: stop.point.latitude,
                  longitude: stop.point.longitude,
                ),
                question:
                    'What occupies the site of ${stop.name} today? Use a dated or current source for this specific place. If the current use cannot be verified, say so.',
                scope: 'Street',
                format: 'Single',
                storyCount: 1,
              ),
            );
            final answer = result.answers
                .where(
                  (a) =>
                      a.story.canAutoplay &&
                      a.story.sources.isNotEmpty &&
                      a.variant.narration.trim().isNotEmpty,
                )
                .firstOrNull;
            if (answer == null) return null;
            return WalkAnswer(answer.variant.narration, {
              for (final source in answer.story.sources)
                if (source.url != null)
                  source.title ?? source.providerName: source.url!,
            });
          },
        ),
      ),
    );
  }

  List<PreparedStop> get preparedStops => [
    for (final s in stops)
      if (verified(s) case final story?)
        PreparedStop(
          s['name'],
          _point(s),
          WalkAnswer(story.shortSpokenNarration, {
            for (final source in story.sourceReferences)
              if (source.sourceUrl != null)
                source.sourceTitle ?? source.providerName: source.sourceUrl!,
          }),
        ),
  ];

  void showStop(_Json stop) {
    final story = verified(stop);
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.all(20),
          children: [
            Text(stop['name'], style: Theme.of(context).textTheme.titleLarge),
            if (story == null)
              const Text('No verified story available.')
            else ...[
              Text(story.storyTitle),
              SelectableText(story.shortSpokenNarration),
              if (story.tellMeMore case final more?) SelectableText(more),
              const Divider(),
              const Text('Sources'),
              for (final source in story.sourceReferences)
                ListTile(
                  title: Text(source.sourceTitle ?? source.providerName),
                  subtitle: SelectableText(
                    [
                      source.attribution,
                      source.sourceUrl,
                    ].whereType<String>().join('\n'),
                  ),
                ),
              for (final credit in story.requiredAttribution) Text(credit),
            ],
          ],
        ),
      ),
    );
  }

  Marker marker(LatLng point, String label, Color color) => Marker(
    point: point,
    width: 36,
    height: 36,
    child: CircleAvatar(
      backgroundColor: color,
      foregroundColor: Colors.white,
      child: Text(label),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final categories = <String, int>{};
    for (final stop in stops) {
      categories.update(
        stop['category'] as String? ?? 'Other',
        (count) => count + 1,
        ifAbsent: () => 1,
      );
    }
    final intro = area == null ? null : introduction(area!);
    return Scaffold(
      appBar: AppBar(title: const Text('Journey Lab')),
      bottomNavigationBar: playingTitle == null
          ? null
          : SafeArea(
              child: ListTile(
                title: Text(playingTitle!),
                subtitle: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 135),
                  child: SingleChildScrollView(child: Text(playingText)),
                ),
                trailing: IconButton(
                  tooltip: 'Stop preview',
                  icon: const Icon(Icons.stop_circle),
                  onPressed: stopPreview,
                ),
              ),
            ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            OutlinedButton.icon(
              onPressed: busy ? null : () => openPrepared(bloorRehearsal),
              icon: const Icon(Icons.headphones),
              label: const Text('Bloor West rehearsal'),
            ),
            OutlinedButton.icon(
              onPressed: busy ? null : () => openPrepared(perthFieldTest),
              icon: const Icon(Icons.directions_walk),
              label: const Text('Perth field test'),
            ),
            TextField(
              controller: query,
              enabled: !busy,
              textInputAction: TextInputAction.search,
              onSubmitted: (s) {
                if (s.trim().isNotEmpty) search();
              },
              decoration: InputDecoration(
                labelText: 'Find a town or place',
                suffixIcon: IconButton(
                  tooltip: 'Search',
                  onPressed: busy
                      ? null
                      : () {
                          if (query.text.trim().isNotEmpty) search();
                        },
                  icon: const Icon(Icons.search),
                ),
              ),
            ),
            const SizedBox(height: 8),
            SegmentedButton<_Tap>(
              segments: const [
                ButtonSegment(value: _Tap.start, label: Text('Start')),
                ButtonSegment(value: _Tap.end, label: Text('End')),
                ButtonSegment(value: _Tap.stop, label: Text('Stop')),
              ],
              selected: {mode},
              onSelectionChanged: busy
                  ? null
                  : (values) => setState(() {
                      mode = values.single;
                      replacing = null;
                    }),
            ),
            Text(
              replacing != null
                  ? 'Tap near the replacement for ${stops[replacing!]['name']}.'
                  : switch (mode) {
                      _Tap.start => 'Tap the map to set the start.',
                      _Tap.end => 'Tap the map to set an optional endpoint.',
                      _Tap.stop => 'Tap near a named place to choose a stop.',
                    },
            ),
            _KeptMap(
              child: SizedBox(
                key: mapKey,
                height: 300,
                child: googleEnabled
                    ? googleMap()
                    : FlutterMap(
                        mapController: map,
                        options: MapOptions(
                          initialCenter: initialCenter,
                          initialZoom: 11,
                          onTap: (_, p) => tap(p),
                        ),
                        children: [
                          TileLayer(
                            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                            userAgentPackageName: 'ai.myrover.rover',
                          ),
                          if (geometry.isNotEmpty)
                            PolylineLayer(
                              polylines: [
                                Polyline(
                                  points: geometry,
                                  strokeWidth: 5,
                                  color: Colors.indigo,
                                ),
                              ],
                            ),
                          MarkerLayer(
                            markers: [
                              if (start case final p?)
                                marker(p, 'S', Colors.green.shade800),
                              if (end case final p?)
                                marker(p, 'E', Colors.red.shade800),
                              for (final (i, s) in stops.indexed)
                                marker(_point(s), '${i + 1}', Colors.indigo),
                            ],
                          ),
                          const SimpleAttributionWidget(
                            source: Text('OpenStreetMap contributors'),
                          ),
                        ],
                      ),
              ),
            ),
            if (end != null)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: busy ? null : () => edit(() => end = null),
                  child: const Text('Clear endpoint'),
                ),
              ),
            Row(
              children: [
                const Text('Time budget'),
                Expanded(
                  child: Slider(
                    min: 15,
                    max: 240,
                    divisions: 45,
                    value: minutes.toDouble(),
                    onChanged: busy
                        ? null
                        : (v) => edit(() => minutes = v.round()),
                  ),
                ),
                Text('$minutes min'),
              ],
            ),
            if (categories.isNotEmpty)
              Text(
                categories.entries
                    .map((entry) => '${entry.key} (${entry.value})')
                    .join(' · '),
              ),
            for (final (i, s) in stops.indexed)
              ListTile(
                leading: Text('${i + 1}'),
                title: Text(s['name']),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      [
                        s['category'],
                        s['attribution'],
                      ].whereType<String>().join(' · '),
                    ),
                    TextButton.icon(
                      onPressed: busy
                          ? null
                          : () => previewJourney(onlyStop: s),
                      icon: const Icon(Icons.volume_up_outlined),
                      label: const Text('Play story'),
                    ),
                  ],
                ),
                onTap: verified(s) == null ? null : () => showStop(s),
                trailing: PopupMenuButton<String>(
                  enabled: !busy,
                  tooltip: 'Edit ${s['name']}',
                  itemBuilder: (_) => [
                    const PopupMenuItem(
                      value: 'replace',
                      child: Text('Replace from map'),
                    ),
                    if (i > 0)
                      const PopupMenuItem(value: 'up', child: Text('Move up')),
                    if (i + 1 < stops.length)
                      const PopupMenuItem(
                        value: 'down',
                        child: Text('Move down'),
                      ),
                    const PopupMenuItem(value: 'remove', child: Text('Remove')),
                  ],
                  onSelected: (action) {
                    if (action == 'replace') {
                      setState(() {
                        mode = _Tap.stop;
                        replacing = i;
                      });
                      return;
                    }
                    edit(() {
                      final item = stops.removeAt(i);
                      if (action != 'remove') {
                        stops.insert(action == 'up' ? i - 1 : i + 1, item);
                      }
                    });
                  },
                ),
              ),
            Wrap(
              spacing: 8,
              children: [
                OutlinedButton(
                  onPressed: busy || start == null || end == null
                      ? null
                      : () => route(true),
                  child: const Text('Suggest stops'),
                ),
                FilledButton(
                  onPressed:
                      busy || start == null || (end == null && stops.isEmpty)
                      ? null
                      : () => route(false),
                  child: const Text('Build walking route'),
                ),
              ],
            ),
            if (plan != null) ...[
              DropdownButtonFormField<String>(
                key: ValueKey(scope),
                initialValue: scope,
                decoration: const InputDecoration(
                  labelText: 'Introduction area',
                ),
                items: [
                  for (final item in ['Neighbourhood', 'City', 'Region'])
                    DropdownMenuItem(
                      value: item,
                      child: Text(item == 'Region' ? 'Region (20 km)' : item),
                    ),
                ],
                onChanged: busy
                    ? null
                    : (value) => setState(() {
                        scope = value!;
                        area = null;
                        status = '';
                      }),
              ),

              Text(
                "${plan!['distanceMeters']} m · ${plan!['walkingMinutes']} min walking · ${plan!['visitMinutes']} min visiting",
              ),
              FilledButton(
                onPressed: busy ? null : generate,
                child: const Text('Generate journey stories'),
              ),
              if (stops.isNotEmpty)
                FilledButton.icon(
                  onPressed: busy ? null : previewJourney,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Play journey from home'),
                ),
              if (preparedStops.isNotEmpty)
                OutlinedButton(
                  onPressed: busy
                      ? null
                      : () => openPrepared(
                          PreparedWalk(
                            'Prepared walk',
                            List.of(geometry),
                            preparedStops,
                          ),
                        ),
                  child: const Text('Test prepared stories at home or on foot'),
                ),
              if (intro != null)
                ListTile(
                  title: const Text('Area introduction'),
                  subtitle: Text(intro.title),
                  onTap: () => showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    builder: (_) => AreaStoryDetails(story: intro),
                  ),
                ),
              if (stops.isNotEmpty)
                OutlinedButton(
                  onPressed: busy
                      ? null
                      : () {
                          final index = next % stops.length;
                          move(_point(stops[index]), 16);
                          setState(() => next = index + 1);
                          previewJourney(onlyStop: stops[index]);
                        },
                  child: Text('Simulate stop ${next % stops.length + 1}'),
                ),
            ],
            Wrap(
              spacing: 8,
              children: [
                TextButton(
                  onPressed: busy || plan == null ? null : save,
                  child: const Text('Save test route'),
                ),
                TextButton(
                  onPressed: busy ? null : reopen,
                  child: const Text('Reopen test route'),
                ),
              ],
            ),
            if (busy) const LinearProgressIndicator(),
            if (busy || status.isNotEmpty) Text(working ?? status),
          ],
        ),
      ),
    );
  }
}

class _KeptMap extends StatefulWidget {
  const _KeptMap({required this.child});
  final Widget child;
  @override
  State<_KeptMap> createState() => _KeptMapState();
}

class _KeptMapState extends State<_KeptMap> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
