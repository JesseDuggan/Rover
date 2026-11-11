import '../voice/spoken_location.dart';

import 'dart:async';

import 'prepared_walk_screen.dart';
import 'king_street_trail.dart';
import 'fremont_tour.dart';
import 'tour_question.dart';
import 'tour_route_preview.dart';
import 'walking_preview.dart';
import 'journey_coverage.dart';

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data' show BytesBuilder;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as google;

import '../maps/google_maps_config.dart';
import '../voice/rover_audio_services.dart';
import '../api/story_question_models.dart';
import '../api/problem_details.dart';

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
import '../just_walking/story_images.dart';
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
  const JourneyLabScreen({super.key, this.client, this.useTestMap = false});
  final bool useTestMap;
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
  String? trailTheme;
  static const themes = [
    'Stage and screen',
    'Local history',
    'Architecture',
    'Art and culture',
    'Nature',
  ];
  final query = TextEditingController();
  _Tap mode = _Tap.start;
  LatLng? start, end;
  List<_Json> stops = [];
  List<LatLng> geometry = [];
  _Json? plan, area;
  Map<String, dynamic> stories = {};
  String? preparedFor;
  List<dynamic> plannerSkips = [];
  String? working;
  String status = '';
  int minutes = 60, next = 0;
  final speech = DeviceTextToSpeech();
  int playbackId = 0;
  Completer<void>? skipPreviewStory;
  String? playingTitle;
  String playingText = '';
  List<String> playingSources = const [];
  RoverLatLng? playingLocation;
  final _storyPictureLookup = WalkStoryPictures();
  List<StoryPicture>? playingPictures;
  LatLng? simulatedPosition;
  int? replacing;
  bool get busy => working != null;
  List<String> get interests => trailTheme == null
      ? PreferencesScope.of(context).preferences.interests
      : switch (trailTheme) {
          'Stage and screen' => ['film and television', 'movies', 'culture'],
          'Local history' => ['history', 'notable people'],
          'Art and culture' => ['art', 'culture'],
          _ => [trailTheme!.toLowerCase()],
        };

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
      if (mounted) {
        final interrupted =
            label == 'Generating stories' && researchInterrupted(e);
        setState(
          () => status = interrupted
              ? 'Story research was interrupted. Any stories already prepared are still here. Check your connection, then tap Generate journey stories to continue.'
              : '$label failed. $e',
        );
      }
    } finally {
      if (mounted) setState(() => working = null);
    }
  }

  void edit(VoidCallback change) => setState(() {
    change();
    plannerSkips = [];
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

  Future<void> route(bool suggest) => run(
    suggest ? 'Finding suggestions' : 'Building walking route',
    () async {
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
        pace: previewPace(PreferencesScope.of(context).preferences.walkingPace),
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
      final points = _rows(result, 'coordinates').map(_point).toList();
      if (points.length < 2) throw StateError('No walking geometry available');
      final skips = suggest ? (result['skipped'] as List? ?? []) : plannerSkips;
      final previousScan =
          !suggest &&
              jsonEncode(plan?['coordinates']) ==
                  jsonEncode(result['coordinates'])
          ? (plan?['gapSearches'])
          : null;
      edit(() => stops = ordered);
      setState(() {
        plannerSkips = skips;
        plan = {
          ...result,
          'skipped': skips,
          if (previousScan != null) 'gapSearches': previousScan,
        };
        geometry = points;
      });
      fit();
      if (suggest) {
        await scanCoverage(planning: true);
        if (mounted)
          setState(
            () => status = 'Gap check complete. Review the route, then generate journey stories.',
          );
      }
    },
  );

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
    } else if (widget.useTestMap) {
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
    if (!widget.useTestMap) return;
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

  String profileQuestion(String question, List<String> interests) {
    final prefix = interests.isEmpty
        ? ''
        : 'Walker interests: ${interests.join(', ')}. ';
    final words =
        '${prefix.length > 125 ? prefix.substring(0, 125) : prefix} $question'
            .trim();
    return words.length <= 500 ? words : words.substring(0, 500);
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
        (stops.isEmpty && plan?['coverage'] == null) ||
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
        Future<void> narrate(
          String title,
          String words, [
          List<String> sources = const [],
          dynamic pictures,
        ]) async {
          setState(() {
            playingTitle = title;
            playingText = spokenLocationText(words);
            playingSources = sources;
            playingPictures = parsePictures(pictures)
                ?.where(
                  (p) => illustratesStory(
                    p,
                    title.replaceFirst(
                      RegExp(r'^(Passing|Between stops) · '),
                      '',
                    ),
                  ),
                )
                .toList();
            final point = onlyStop == null
                ? simulatedPosition
                : _point(onlyStop);
            playingLocation = point == null
                ? null
                : RoverLatLng(
                    latitude: point.latitude,
                    longitude: point.longitude,
                  );
          });
          bool ready = false;
          final prepared = playingPictures;
          final location = playingLocation;
          unawaited(() async {
            final candidates =
                prepared ??
                (location == null || sources.isEmpty
                    ? <StoryPicture>[]
                    : await _storyPictureLookup.find(
                        title.replaceFirst(
                          RegExp(r'^(Passing|Between stops) · '),
                          '',
                        ),
                        sources,
                        location.latitude,
                        location.longitude,
                      ));
            for (final picture in candidates) {
              if (!active() || playingTitle != title) return;
              if (!await storyPhotoReady(picture)) continue;
              if (!active() || playingTitle != title) return;
              setState(
                () => playingPictures = [
                  picture,
                  ...candidates.where((p) => p.url != picture.url),
                ],
              );
              ready = true;
              return;
            }
          }());
          final skip = Completer<void>();
          skipPreviewStory = skip;
          try {
            await Future.any([speech.speak(words), skip.future]);
            if (active() && ready && !skip.isCompleted) {
              await Future.any([speech.speak(storyPictureCue), skip.future]);
            }
          } finally {
            if (identical(skipPreviewStory, skip)) skipPreviewStory = null;
          }
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
        if (onlyStop != null) {
          final words = verified(onlyStop)?.shortSpokenNarration;
          if (words != null)
            await narrate(
              onlyStop['name'],
              words,
              pictureSources(onlyStop),
              stories[onlyStop['id']]?['pictures'],
            );
          if (active())
            setState(
              () => status = words == null
                  ? 'No prepared story here. Tap Generate journey stories.'
                  : 'Story finished.',
            );
          return;
        }
        {
          final path = JourneyCoverage(geometry);
          final events =
              <
                  ({
                    double at,
                    String title,
                    String words,
                    bool passing,
                    List<String> sources,
                    dynamic pictures,
                  })
                >[
                  for (final stop in stops)
                    if (verified(stop)?.shortSpokenNarration
                        case final String words)
                      (
                        at: path.project(_point(stop)).along,
                        title: stop['name'] as String,
                        words: words,
                        pictures: stories[stop['id']]?['pictures'],
                        sources: pictureSources(stop),
                        passing: false,
                      ),
                  for (final place
                      in (plan?['coverage']?['passing'] as List? ?? [])
                          .cast<_Json>())
                    if (verified(place)?.shortSpokenNarration
                        case final String words)
                      (
                        at: (place['metres'] as num).toDouble(),
                        title: 'Passing · ${place['name']}',
                        words: shortPassage(words),
                        pictures: stories[place['id']]?['pictures'],
                        sources: pictureSources(place),
                        passing: true,
                      ),
                  for (final cue
                      in (plan?['between'] as List? ?? []).cast<_Json>())
                    if (DateTime.tryParse(cue['expiresUtc'] as String)
                            ?.isAfter(DateTime.now()) ==
                        true)
                      (
                        at: (cue['metres'] as num).toDouble(),
                        title: 'Between stops · ${cue['title']}',
                        words: cue['words'] as String,
                        pictures: cue['pictures'],
                        sources: (cue['sources'] as List? ?? [])
                            .whereType<Map>()
                            .map((s) => s['url'])
                            .whereType<String>()
                            .toList(),
                        passing: true,
                      ),
                ]
                ..sort((a, b) => a.at.compareTo(b.at));
          if (events.isEmpty && intro == null) {
            setState(
              () => status =
                  'No prepared stories. Tap Generate journey stories first.',
            );
            return;
          }
          var cursor = 0.0;
          Future<void> advance(double target) async {
            final steps = ((target - cursor) / 35).ceil().clamp(1, 40);
            final origin = cursor;
            for (var step = 1; step <= steps && active(); step++) {
              cursor = origin + (target - origin) * step / steps;
              final point = path.at(cursor);
              setState(() => simulatedPosition = point);
              move(point, 16);
              await Future<void>.delayed(const Duration(milliseconds: 140));
            }
          }

          for (final (index, event) in events.indexed) {
            if (!active()) return;
            setState(() {
              playingTitle = 'Walking';
              playingText = '';
            });
            await advance(event.at);
            if (!active()) return;
            final voice = narrate(
              event.title,
              event.words,
              event.sources,
              event.pictures,
            );
            if (event.passing) {
              final nextAt = index + 1 < events.length
                  ? events[index + 1].at
                  : path.total;
              await Future.wait([
                voice,
                advance(math.min(cursor + 35, nextAt)),
              ]);
            } else {
              await voice;
            }
          }
          if (active()) await advance(path.total);
          if (active()) setState(() => status = 'Test journey complete.');
          return;
        }
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
    await skipNarration();
  }

  Future<void> skipNarration() async {
    final skip = skipPreviewStory;
    await speech.stop();
    if (skip != null && !skip.isCompleted) skip.complete();
  }

  bool researchInterrupted(Object error) =>
      error is RoverApiConnectionException ||
      error is RoverApiTimeoutException ||
      error is SocketException ||
      error is HttpException ||
      error is TimeoutException ||
      (error is RoverApiException &&
          [502, 503, 504].contains(error.statusCode));

  Future<void> generate() => run('Generating stories', () async {
    final issues = <String>[];
    final selectedInterests = interests;
    final selectedDepth = PreferencesScope.of(context).preferences.contentDepth;
    final profileKey = jsonEncode({
      'interests': selectedInterests.map((s) => s.toLowerCase()).toList()
        ..sort(),
      'depth': selectedDepth,
      'policy': 'shared-preparation-v1',
    });
    if (preparedFor != profileKey) {
      stories.clear();
      area = null;
      plan?.remove("between");
      plan?.remove("coverage");
      plan?.remove("gapSearches");
      preparedFor = profileKey;
    }
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
        if (researchInterrupted(e)) rethrow;
        issues.add('Area research failed. $e');
      }
    }
    final pending = stops.where((stop) {
      final saved = verified(stop);
      return saved == null;
    }).toList();
    Future<String?> prepare(_Json stop) async {
      final name = subject(stop).name;
      try {
        await researchStop(stop, selectedInterests);
        if (mounted && verified(stop) == null)
          return 'No verified story for $name.';
        if (mounted) stories[stop['id']]['depthChecked'] = true;
      } catch (e) {
        if (researchInterrupted(e)) rethrow;
        return '$name: $e';
      }
      return null;
    }

    for (var index = 0; index < pending.length; index += 2) {
      if (!mounted) return;
      final batch = pending.skip(index).take(2).toList();
      final names = batch.map((stop) => subject(stop).name).join(' and ');
      setState(() => working = 'Researching $names');
      final results = await Future.wait(batch.map(prepare));
      issues.addAll(results.whereType<String>());
    }
    if (mounted && plan != null) await scanCoverage(duringGeneration: true);
    if (mounted && plan != null && plan!['between'] == null) {
      setState(() => working = 'Preparing between-stop stories');
      final path = JourneyCoverage(geometry);
      final cues = <_Json>[];
      final covered = {
        for (final stop in stops) stop['name'] as String,
        if (area != null && introduction(area!) != null)
          introduction(area!)!.title,
      };
      final nearby = <AdaptiveRouteStory>[];
      var eventQueries = 0;
      LatLng? searchedAt;
      var failed = false;
      final gaps = path.gaps([
        for (final stop in stops)
          if (verified(stop) != null) path.project(_point(stop)).along,
        for (final place in (plan?['coverage']?['passing'] as List? ?? []))
          (place['metres'] as num).toDouble(),
      ])..sort((a, b) => (b.end - b.start).compareTo(a.end - a.start));
      for (final gap in gaps) {
        if (gap.end - gap.start < 100) continue;
        final metres = (gap.start + gap.end) / 2;
        final point = path.at(metres);
        const distance = Distance();
        if (searchedAt == null || distance(searchedAt, point) >= 750) {
          searchedAt = point;
          setState(() => working = 'Looking for a neighbourhood story');
          if (eventQueries < 3) {
            eventQueries++;
            final nearest = [...stops]
              ..sort(
                (a, b) => distance(
                  point,
                  _point(a),
                ).compareTo(distance(point, _point(b))),
              );
            final landmark = nearest.isEmpty
                ? ''
                : ' The nearest planned stop is ${nearest.first["name"]}.';
            try {
              final response = await api.researchStoryQuestion(
                StoryQuestionRequest(
                  location: RoverLatLng(
                    latitude: point.latitude,
                    longitude: point.longitude,
                  ),
                  scope: 'Street',
                  format: 'Single',
                  storyCount: 1,
                  availableNarrationSeconds: 45,
                  question: profileQuestion(
                    'Research this block or landscape in local-language archives. What used to be here, who used it, or what shaped it? Find one sourced detail tied to this exact stretch and look for a cited illustrated record of its subject. Attribute recollections. Skip unrelated landmarks. $landmark',
                    selectedInterests,
                  ),
                ),
              );
              if (!mounted) return;
              nearby.addAll(
                response.answers
                    .map((answer) => answer.story)
                    .where(
                      (story) =>
                          distance(
                                point,
                                LatLng(
                                  story.relevanceLatitude,
                                  story.relevanceLongitude,
                                ),
                              ) <=
                              250 &&
                          path
                                  .project(
                                    LatLng(
                                      story.relevanceLatitude,
                                      story.relevanceLongitude,
                                    ),
                                  )
                                  .away <=
                              50,
                    ),
              );
            } catch (e) {
              if (researchInterrupted(e)) rethrow;
              failed = true;
            }
          }
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
            if (!mounted) return;
            nearby.addAll(AreaStoryCollection.fromJson(result).stories);
          } catch (e) {
            if (researchInterrupted(e)) rethrow;
            failed = true;
          }
        }
        if (!mounted) return;
        final candidates = nearby
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
            .toList();
        final story =
            candidates
                .where(
                  (candidate) => !needsDeeperResearch(
                    candidate.variants
                        .firstWhere((v) => v.narration.trim().isNotEmpty)
                        .narration,
                  ),
                )
                .firstOrNull ??
            candidates.firstOrNull;
        if (story == null) continue;
        covered.add(story.title);
        cues.add({
          'metres': metres,
          'title': story.title,
          'words': story.variants
              .firstWhere((v) => v.narration.trim().isNotEmpty)
              .narration,
          'expiresUtc': story.expiresUtc!.toIso8601String(),
          'sources': story.sources.map((source) => source.toJson()).toList(),
        });
      }
      if (!mounted) return;
      if (failed)
        issues.add('Some neighbourhood stories could not be prepared.');
      if (cues.isNotEmpty || !failed) plan = {...plan!, 'between': cues};
    }
    if (mounted && plan != null) {
      setState(() => working = 'Finding story pictures');
      final jobs = <Future<void> Function()>[];
      for (final place in [
        ...stops,
        ..._rows(plan?['coverage'] ?? {'passing': []}, 'passing'),
      ]) {
        final record = stories[place['id']];
        if (record is _Json && verified(place) != null) {
          jobs.add(
            () => preparePictures(
              record,
              pictureSources(place),
              _point(place),
              place['name'] as String,
            ),
          );
        }
      }
      final path = JourneyCoverage(geometry);
      for (final cue in (plan?['between'] as List? ?? []).whereType<_Json>()) {
        final urls = (cue['sources'] as List? ?? [])
            .whereType<Map>()
            .map((s) => s['url'])
            .whereType<String>()
            .toList();
        jobs.add(
          () => preparePictures(
            cue,
            urls,
            path.at((cue['metres'] as num).toDouble()),
            cue['title'] as String,
          ),
        );
      }
      for (var i = 0; mounted && i < jobs.length; i += 3) {
        await Future.wait(jobs.skip(i).take(3).map((job) => job()));
      }
    }
    if (mounted) {
      setState(
        () => status = issues.isEmpty ? 'Stories ready.' : issues.join('\n'),
      );
    }
  });

  Future<void> checkCoverage() =>
      run('Checking story gaps', () => scanCoverage());
  Future<void> scanCoverage({
    bool planning = false,
    bool duringGeneration = false,
  }) async {
    final searches = Map<String, dynamic>.from(
      plan?['gapSearches'] as Map? ?? {},
    );
    final findings = <_Json>[];
    void record(double at, String reason) {
      findings.add({'metres': at, 'reason': reason});
    }

    final path = JourneyCoverage(geometry);
    final selectedInterests = List<String>.of(interests);
    final passing = <_Json>[], notes = <String>[];
    final occupied = <double>[];
    for (final stop in stops) {
      final at = path.project(_point(stop)).along;
      if (planning || verified(stop) != null) {
        occupied.add(at);
      } else {
        final reason = "${stop['name']} — no verified stop narration ready.";
        notes.add(reason);
        record(at, reason);
      }
    }
    final seen = <String>{for (final stop in stops) stop['id'] as String};
    final probes = path.searchPoints(occupied);
    var attempts = 0;
    for (final at in probes) {
      if (!mounted) return;
      setState(() => working = 'Checking the route at ${at.round()} m');
      try {
        final key = at.round().toString();
        final result =
            searches[key] as _Json? ??
            await api.nearbyJourneyStops(
              location: _coordinates(path.at(at)),
              interests: coverageInterests(selectedInterests),
            );
        if (!mounted) return;
        searches[key] = result;
        final candidates =
            _rows(result, 'stops')
                .map(
                  (place) => (place: place, pos: path.project(_point(place))),
                )
                .toList()
              ..sort(
                (a, b) => (a.pos.along - at).abs().compareTo(
                  (b.pos.along - at).abs(),
                ),
              );
        for (final item in candidates) {
          final place = item.place;
          final name = place['name'] as String;
          if ((item.pos.along - at).abs() > 250 ||
              !seen.add(place['id'] as String))
            continue;
          final alreadyStop = stops.any(
            (s) =>
                s['id'] == place['id'] ||
                (s['name'].toString().toLowerCase() == name.toLowerCase() &&
                    JourneyCoverage.distance(_point(s), _point(place)) < 60),
          );
          if (alreadyStop) continue;
          String? reason;
          if (foodCategory(place['category'] as String) &&
              !coverageInterests(selectedInterests).any(foodCategory)) {
            reason = 'Outside the interests used for this gap search';
          } else if (item.pos.away > 50) {
            reason = 'More than 50 m from the walking path';
          } else if ([
            0.0,
            ...occupied,
            path.total,
          ].any((m) => (item.pos.along - m).abs() < 90)) {
            reason = 'Too close to another cue or route endpoint';
          } else if (planning) {
            passing.add({...place, 'metres': item.pos.along});
            occupied.add(item.pos.along);
            break;
          } else if (attempts >= 8) {
            reason = 'Research limit reached for this scan';
          } else {
            if (verified(place) == null) {
              attempts++;
              try {
                await researchStop(place, selectedInterests);
              } catch (e) {
                if (duringGeneration && researchInterrupted(e)) rethrow;
                reason = 'Story research unavailable';
              }
            }
            if (!mounted) return;
            final words = verified(place)?.shortSpokenNarration;
            if (words != null && shortPassage(words).isNotEmpty) {
              passing.add({...place, 'metres': item.pos.along});
              occupied.add(item.pos.along);
              break;
            }
            reason ??= 'No short, sourced narration available';
          }
          notes.add('$name — $reason.');
          record(item.pos.along, notes.last);
        }
        if (candidates.every((c) => (c.pos.along - at).abs() > 250)) {
          record(at, 'Nearby search returned no candidate on this stretch.');
        }
      } catch (e) {
        if (duringGeneration && researchInterrupted(e)) rethrow;
        record(at, 'Nearby place search was unavailable.');
        notes.add('Nearby search unavailable at ${at.round()} m.');
      }
    }
    if (!mounted) return;
    setState(() {
      plan = {
        ...plan!,
        'gapSearches': searches,
        if (planning) 'gapCandidateCount': passing.length,
        if (!planning)
          'coverage': {
            'findings': findings,
            'passing': passing,
            'notes': notes,
            'probes': probes.length,
          },
      };
      status = 'Coverage ready. Play the journey from home to hear it.';
    });
  }

  Widget coveragePanel() {
    final path = JourneyCoverage(geometry);
    final report = plan!['coverage'] as _Json;
    final passing = _rows(
      report,
      'passing',
    ).where((p) => verified(p) != null).toList();
    final cues = <WalkingCue>[
      for (final p in stops)
        if (verified(p) != null)
          (at: path.project(_point(p)).along, walkingSpeech: ''),
      for (final p in passing)
        if (shortPassage(verified(p)!.shortSpokenNarration).isNotEmpty)
          (
            at: (p['metres'] as num).toDouble(),
            walkingSpeech: shortPassage(verified(p)!.shortSpokenNarration),
          ),
      for (final c in (plan?['between'] as List? ?? []).cast<_Json>())
        if (DateTime.tryParse(c['expiresUtc'] as String)
                    ?.isAfter(DateTime.now()) ==
                true &&
            (c['words'] as String).trim().isNotEmpty)
          (
            at: (c['metres'] as num).toDouble(),
            walkingSpeech: c['words'] as String,
          ),
    ];
    final timing = quietWalking(
      path.total,
      (plan!['walkingMinutes'] as num).toDouble(),
      cues,
    );
    final gap = timing.longest;
    String duration(double m) {
      final seconds = (m * timing.secondsPerMetre).round();
      if (seconds < 60) return '$seconds sec';
      return '${seconds ~/ 60} min ${seconds % 60} sec';
    }

    final introReady = area != null && introduction(area!) != null;
    final reasons = <String>{
      for (final f in (report['findings'] as List? ?? []).cast<_Json>())
        if ((f['metres'] as num) >= gap.start &&
            (f['metres'] as num) <= gap.end)
          f['reason'] as String,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          introReady
              ? 'First story: at the start (area introduction).'
              : timing.first == null
              ? 'No playable story yet.'
              : 'First story: about ${duration(timing.first!)} from the start.',
        ),
        if (introReady && timing.first != null)
          Text(
            'First story along the path: about ${duration(timing.first!)} into the walk.',
          ),
        Text(
          'Longest quiet stretch: about ${duration(gap.end - gap.start)} · ${gap.start.round()}–${gap.end.round()} m from the start.',
        ),
        if (gap.end > gap.start)
          Text(
            reasons.isEmpty
                ? 'There is no prepared narration covering this part of the route.'
                : reasons.take(2).join(' '),
          ),
        ExpansionTile(
          title: const Text('Story gaps along the route'),
          children: [
            const Text(
              'Estimates use the planned walking time and about 150 spoken words per minute.',
            ),
            for (final reason in reasons) ListTile(title: Text(reason)),
          ],
        ),
        for (final place in passing)
          ListTile(
            title: Text(place['name']),
            subtitle: Text(
              "Pass-by story · ${(place['metres'] as num).round()} m",
            ),
            onTap: () => showStop(place),
          ),
        ExpansionTile(
          title: const Text('Why places were skipped'),
          children: [
            for (final row in plannerSkips)
              ListTile(title: Text(row['name']), subtitle: Text(row['reason'])),
            for (final note in report['notes']) ListTile(title: Text(note)),
            if (plannerSkips.isEmpty && (report['notes'] as List).isEmpty)
              const ListTile(
                title: Text('No skipped places reported for this route.'),
              ),
          ],
        ),
      ],
    );
  }

  Future<void> researchStop(_Json stop, List<String> selectedInterests) async {
    final place = subject(stop);
    final result =
        verified(stop) ??
        await api.createDriveStopStory(
          id: place.id,
          interests: selectedInterests,
          journeyStart: _coordinates(start!),
          journeyEnd: _coordinates(end ?? _point(stops.last)),
          name: place.name,
          latitude: place.location.latitude,
          longitude: place.location.longitude,
        );
    if (!mounted) return;
    final usable = usableDriveStory(result, place, DateTime.now().toUtc());
    if (usable && verified(stop) == null) {
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

  _Json snapshot() => {
    'preparedFor': preparedFor,
    'start': _coordinates(start!),
    'end': end == null ? null : _coordinates(end!),
    'minutes': minutes,
    'scope': scope,
    'trailTheme': trailTheme,
    'stops': stops,
    'plan': plan == null
        ? null
        : (Map<String, dynamic>.of(plan!)..remove('gapSearches')),
    'area': area,
    'stories': stories,
    'next': next,
  };

  Future<void> copyReplay() => run('Copying test replay', () async {
    final bytes = utf8.encode(jsonEncode(snapshot()));
    if (bytes.length > 450000)
      throw StateError('This route is too large to copy.');
    final packet = base64Url.encode(gzip.encode(bytes));
    await Clipboard.setData(ClipboardData(text: 'WalkaboutLab1.$packet'));
    if (mounted)
      setState(
        () => status = 'Replay copied. Send it to your tester, including route locations and stories.',
      );
  });

  Future<void> pasteReplay() => run('Opening copied replay', () async {
    final text =
        (await Clipboard.getData(Clipboard.kTextPlain))?.text?.trim() ?? '';
    if (!text.startsWith('WalkaboutLab1.') || text.length > 700000) {
      throw const FormatException('Copy a Walkabout test replay first.');
    }
    final buffer = BytesBuilder();
    await for (final chunk in gzip.decoder.bind(
      Stream.value(base64Url.decode(text.substring('WalkaboutLab1.'.length))),
    )) {
      if (buffer.length + chunk.length > 450000)
        throw const FormatException('Replay exceeds the size limit.');
      buffer.add(chunk);
    }
    restore(jsonDecode(utf8.decode(buffer.takeBytes())) as _Json);
  });

  Future<void> save() => run('Saving route', () async {
    final file = await savedFile();
    await file.parent.create(recursive: true);
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(jsonEncode(snapshot()), flush: true);
    await temp.rename(file.path);
    if (mounted) setState(() => status = 'Test route saved on this device.');
  });

  Future<void> reopen() => run('Reopening route', () async {
    final file = await savedFile();
    if (!await file.exists()) {
      if (mounted) setState(() => status = 'No saved test route yet.');
      return;
    }
    restore(jsonDecode(await file.readAsString()) as _Json);
  });

  void restore(_Json data) {
    final origin = _point(data['start']);
    final destination = data['end'] == null ? null : _point(data['end']);
    final ordered = _rows(data, 'stops').toList();
    final savedPlan = data['plan'] as _Json;
    final points = _rows(savedPlan, 'coordinates').map(_point).toList();
    if (points.length < 2 ||
        points.length > 30000 ||
        ordered.length > 20 ||
        ![
          'Neighbourhood',
          'City',
          'Region',
        ].contains(data['scope'] ?? 'Neighbourhood') ||
        data['minutes'] is! int ||
        data['minutes'] < 15 ||
        data['minutes'] > 240 ||
        data['stories'] is! _Json ||
        data['next'] is! int)
      throw const FormatException('Invalid test replay.');
    for (final row in [
      ...ordered,
      ...?savedPlan['coverage']?['passing'] as List?,
    ]) {
      _point(row);
      if (row['name'] is! String ||
          row['id'] is! String ||
          row['category'] is! String)
        throw const FormatException('Invalid replay place.');
      if (row['metres'] != null && row['metres'] is! num)
        throw const FormatException('Invalid cue position.');
      final raw = data['stories'][row['id']];
      if (raw != null) LocationStoryResponse.fromJson(raw);
    }
    if (data['area'] != null) introduction(data['area']);
    if (savedPlan['coverage'] != null) {
      _rows(savedPlan['coverage'], 'passing');
      (savedPlan['coverage']['notes'] as List).cast<String>().toList();
    }
    for (final row in savedPlan['skipped'] ?? []) {
      if (row['name'] is! String || row['reason'] is! String)
        throw const FormatException('Invalid skipped place.');
    }
    if (!mounted) return;
    setState(() {
      start = origin;
      end = destination;
      stops = ordered;
      plan = savedPlan;
      plannerSkips = savedPlan['skipped'] as List? ?? [];
      geometry = points;
      minutes = data['minutes'];
      scope = data['scope'] ?? 'Neighbourhood';
      trailTheme = themes.contains(data['trailTheme'])
          ? data['trailTheme'] as String
          : null;
      area = data['area'];
      stories = data['stories'];
      preparedFor = data['preparedFor'] as String?;
      next = data['next'];
      mode = _Tap.stop;
      replacing = null;
    });
    fit();
  }

  Future<void> chooseFremontStart() async {
    final prefs = PreferencesScope.of(context).preferences;
    final startName = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Start Fremont Past to Present'),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            child: Text(
              prefs.interests.isEmpty
                  ? 'Your tour uses the introductory stories.'
                  : 'Your interests: ${prefs.interests.join(', ')}',
            ),
          ),
          for (final name in ['Plaza', 'El Cortez'])
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, name),
              child: Text('Start at $name'),
            ),
        ],
      ),
    );
    if (!mounted || startName == null) return;
    await run('Opening Fremont tour', () async {
      final walk = await fremontTour(
        start: startName,
        interests: prefs.interests,
        depth: prefs.contentDepth,
      );
      if (!mounted) return;
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => TourRoutePreview(
            rehearsalStart: fremontRehearsalStart,
            initialWalk: walk,
            api: api,
            pace: prefs.walkingPace,
            onUse: openPrepared,
            profileInterests: prefs.interests,
            loadWalk: (interests) => fremontTour(
              start: startName,
              interests: interests,
              depth: prefs.contentDepth,
            ),
          ),
        ),
      );
    });
  }

  void openPrepared(PreparedWalk walk) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PreparedWalkScreen(
          walk: walk,
          research: (stop) => askAtStop(stop, 'What occupies this site today?'),
          followUp: askAtStop,
        ),
      ),
    );
  }

  Future<WalkAnswer?> askAtStop(PreparedStop stop, String question) =>
      askTourQuestion(api, stop, question);

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
          pictures: (parsePictures(stories[s['id']]?['pictures']) ?? [])
              .where((p) => illustratesStory(p, s['name']))
              .toList(),
        ),
  ];

  List<PreparedStop> get preparedWalkingStories {
    final path = JourneyCoverage(geometry);
    final itinerary = [...preparedStops];
    for (final place in _rows(
      plan?['coverage'] ?? {'passing': []},
      'passing',
    )) {
      final story = verified(place);
      if (story == null) continue;
      itinerary.add(
        PreparedStop(
          place['name'],
          path.at((place['metres'] as num).toDouble()),
          WalkAnswer(shortPassage(story.shortSpokenNarration), {
            for (final source in story.sourceReferences)
              if (source.sourceUrl != null)
                source.sourceTitle ?? source.providerName: source.sourceUrl!,
          }),
          pictures: parsePictures(stories[place['id']]?['pictures']) ?? [],
        ),
      );
    }
    for (final cue in (plan?['between'] as List? ?? []).whereType<_Json>()) {
      if (DateTime.tryParse(cue['expiresUtc'] as String? ?? '')
              ?.isAfter(DateTime.now()) !=
          true)
        continue;
      itinerary.add(
        PreparedStop(
          cue['title'],
          path.at((cue['metres'] as num).toDouble()),
          WalkAnswer(cue['words'], {
            for (final source
                in (cue['sources'] as List? ?? []).whereType<Map>())
              if (source['url'] is String)
                (source['title'] ?? source['url']).toString():
                    source['url'] as String,
          }),
          pictures: parsePictures(cue['pictures']) ?? [],
        ),
      );
    }
    return itinerary..sort(
      (a, b) =>
          path.project(a.point).along.compareTo(path.project(b.point).along),
    );
  }

  List<StoryPicture>? parsePictures(dynamic raw) => raw is List
      ? raw
            .whereType<_Json>()
            .map(StoryPicture.parse)
            .whereType<StoryPicture>()
            .take(3)
            .toList()
      : null;

  Future<void> preparePictures(
    _Json record,
    List<String> urls,
    LatLng point,
    String title,
  ) async {
    if (record['pictures'] is List) return;
    try {
      final result = await api.getStoryImages(
        urls.where(supportedPictureSource).toSet().take(6).toList(),
        latitude: point.latitude,
        longitude: point.longitude,
      );
      if (!mounted || result['status'] == 'unavailable') return;
      record['pictures'] = (result['images'] as List? ?? [])
          .whereType<_Json>()
          .where((row) {
            final picture = StoryPicture.parse(row);
            return picture != null && illustratesStory(picture, title);
          })
          .take(3)
          .toList();
    } on Exception {
      // A missing illustration must never prevent the chapter from playing.
    }
  }

  List<String> pictureSources(_Json stop) =>
      verified(stop)?.sourceReferences
          .map((s) => s.sourceUrl)
          .whereType<String>()
          .toList() ??
      const [];

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
              if (parsePictures(stories[stop['id']]?['pictures'])
                  case final pictures? when pictures.isNotEmpty)
                PictureCarousel(pictures: pictures)
              else
                StoryImages(
                  sourceUrls: story.sourceReferences
                      .map((s) => s.sourceUrl)
                      .whereType<String>()
                      .toList(),
                  nearbyLocation: subject(stop).location,
                ),
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
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (playingText.isNotEmpty &&
                            playingPictures?.isNotEmpty == true)
                          PictureCarousel(
                            pictures: playingPictures!,
                            compact: true,
                          ),
                        Text(playingText),
                      ],
                    ),
                  ),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (playingText.isNotEmpty)
                      IconButton(
                        tooltip: 'Skip this story',
                        icon: const Icon(Icons.skip_next),
                        onPressed: skipNarration,
                      ),
                    IconButton(
                      tooltip: 'Stop preview',
                      icon: const Icon(Icons.stop_circle),
                      onPressed: stopPreview,
                    ),
                  ],
                ),
              ),
            ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            OutlinedButton.icon(
              onPressed: busy ? null : chooseFremontStart,
              icon: const Icon(Icons.tour),
              label: const Text('Fremont Past to Present'),
            ),
            FilledButton.icon(
              onPressed: busy ? null : () => openPrepared(kingStreetTrail),
              icon: const Icon(Icons.theater_comedy),
              label: const Text('King Street Story Trail'),
            ),
            DropdownButtonFormField<String>(
              initialValue: trailTheme ?? 'Profile interests',
              key: ValueKey(trailTheme),
              decoration: const InputDecoration(
                labelText: 'Theme for your own route',
              ),
              items: [
                for (final theme in ['Profile interests', ...themes])
                  DropdownMenuItem(value: theme, child: Text(theme)),
              ],
              onChanged: busy
                  ? null
                  : (value) => edit(
                      () => trailTheme = value == 'Profile interests'
                          ? null
                          : value,
                    ),
            ),
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
            TextButton.icon(
              icon: const Icon(Icons.my_location),
              label: const Text('Use my current location as start'),
              onPressed: busy
                  ? null
                  : () => run('Finding your location', () async {
                      final point = await currentWalkStart();
                      if (!mounted) return;
                      edit(() {
                        start = point;
                        mode = end == null ? _Tap.end : _Tap.stop;
                      });
                      move(point, 15);
                    }),
            ),
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
                    : !widget.useTestMap
                    ? const Center(child: Text('Google Maps unavailable'))
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

              if (geometry.length >= 2)
                WalkingPreview(
                  plan: plan!,
                  geometry: geometry,
                  budget: minutes,
                  first: stops.isEmpty
                      ? end ?? geometry.last
                      : _point(stops.first),
                  firstName: stops.isEmpty
                      ? 'Destination'
                      : stops.first['name'],
                  names: [
                    for (final s in stops) s['name'] as String,
                    if (end != null &&
                        (stops.isEmpty || end != _point(stops.last)))
                      'Destination',
                  ],
                ),
              FilledButton(
                onPressed: busy ? null : generate,
                child: const Text('Generate journey stories'),
              ),
              OutlinedButton(
                onPressed: busy ? null : checkCoverage,
                child: const Text('Check story gaps'),
              ),
              if (plan?['gapCandidateCount'] != null &&
                  plan?['coverage'] == null)
                Text(
                  'Pass-by candidates found: ${plan!["gapCandidateCount"]}. Generate stories to verify them.',
                ),
              if (plan?['coverage'] != null) coveragePanel(),
              if (stops.isNotEmpty || plan?['coverage'] != null)
                FilledButton.icon(
                  onPressed: busy ? null : previewJourney,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Play journey from home'),
                ),
              if (trailTheme != null &&
                  stories.isNotEmpty &&
                  preparedStops.length < stops.length)
                Text(
                  'Missing verified chapters: ${stops.where((s) => verified(s) == null).map((s) => s["name"]).join(", ")}',
                ),
              if (preparedStops.isNotEmpty)
                OutlinedButton(
                  onPressed: busy
                      ? null
                      : () => openPrepared(
                          PreparedWalk(
                            trailTheme ?? 'Prepared walk',
                            List.of(geometry),
                            preparedWalkingStories,
                            theme: trailTheme,
                          ),
                        ),
                  child: Text(
                    trailTheme == null
                        ? 'Test prepared stories at home or on foot'
                        : 'Preview Story Trail',
                  ),
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
                if (plan?['coverage'] != null)
                  TextButton(
                    onPressed: busy ? null : copyReplay,
                    child: const Text('Copy replay for a tester'),
                  ),
                TextButton(
                  onPressed: busy ? null : pasteReplay,
                  child: const Text('Open copied replay'),
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
