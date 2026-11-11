import 'dart:async';

import 'package:flutter/material.dart';
import '../adventure/roam.dart';
import 'journey_coverage.dart';
import '../maps/rover_map_view.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../location/rover_location.dart';
import '../voice/rover_audio_services.dart';
import '../voice/spoken_location.dart';
import '../just_walking/story_images.dart';

class WalkAnswer {
  const WalkAnswer(this.text, this.sources);
  final String text;
  final Map<String, String> sources;
}

class TourPhoto {
  const TourPhoto({required this.asset, required this.caption, required this.author,
    required this.license, required this.source, required this.licenseUrl});
  final String asset, caption, author, license, source, licenseUrl;
  String get cue => 'On your phone, you can see $caption.';

  Future<void> open(BuildContext context) => showDialog<void>(
    context: context,
    builder: (ctx) => Dialog.fullscreen(child: Scaffold(
      appBar: AppBar(automaticallyImplyLeading: false, title: const Text('Story photo'),
        actions: [IconButton(tooltip: 'Close photo', icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(ctx))]),
      body: SafeArea(child: Column(children: [
        Expanded(child: InteractiveViewer(child: Center(child: Image.asset(asset,
          fit: BoxFit.contain, semanticLabel: caption)))),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(caption, textAlign: TextAlign.center)),
        Wrap(alignment: WrapAlignment.center, children: [
          TextButton(onPressed: () => launchUrl(Uri.parse(source)), child: Text(author)),
          TextButton(onPressed: () => launchUrl(Uri.parse(licenseUrl)), child: Text(license)),
        ]),
      ])),
    )),
  );
}

class PreparedStop {
  const PreparedStop(this.name, this.point, this.story, {this.optional = false, this.answer, this.photo, this.pictures = const []});
  final String name;
  final LatLng point;
  final WalkAnswer story;
  final WalkAnswer? answer;
  final bool optional;
  final TourPhoto? photo;
  final List<StoryPicture> pictures;
}

class PreparedWalk {
  const PreparedWalk(this.title, this.path, this.stops, {this.theme, this.orderedChapters = false});
  final String? theme;
  final bool orderedChapters;
  final String title;
  final List<LatLng> path;
  final List<PreparedStop> stops;
}

RoverRoam preparedRoute(PreparedWalk walk, {String summary = '', String id = 'stop'}) {
  RoverLatLng coordinate(LatLng point) =>
      RoverLatLng(latitude: point.latitude, longitude: point.longitude);
  final line = walk.path.map(coordinate).toList();
  var meters = 0.0;
  for (var i = 1; i < line.length; i++) {
    meters += line[i - 1].distanceTo(line[i]);
  }
  return RoverRoam(
      title: walk.title,
      summary: summary,
      walkingMinutes: (meters / 75).ceil(),
      distanceMiles: meters / 1609.344,
      startingPoint: walk.stops.first.name,
      routeGeometry: line,
      routeProvider: summary.isEmpty ? 'Prepared route' : 'OpenStreetMap contributors',
      accessibilityNotes: const [],
      warnings: const [],
      stops: [
        for (final (i, stop) in walk.stops.indexed)
          RoverStop(
            id: '$id-$i',
            name: stop.name,
            image: '',
            shortDescription: stop.story.text,
            estimatedVisitMinutes: 2,
            coordinates: coordinate(stop.point),
            category: 'Tour stop',
            whySelected: walk.title,
            narration: stop.story.text,
            sourceUrl: stop.story.sources.values.firstOrNull,
          ),
      ],
    );
}

// Fixed street-level rehearsal line. The trigger marks the theatre frontage.
const bloorRehearsal = PreparedWalk(
  'Bloor West rehearsal',
  [
    LatLng(43.65114, -79.47626),
    LatLng(43.65095, -79.47672),
    LatLng(43.65036, -79.47948),
    LatLng(43.64941, -79.48377),
    LatLng(43.64908, -79.48468),
    LatLng(43.64813, -79.48576),
    LatLng(43.64769, -79.48784),
    LatLng(43.64768, -79.48849),
    LatLng(43.6478, -79.48989),
    LatLng(43.64846, -79.49196),
  ],
  [
    PreparedStop(
      'Runnymede Theatre',
      LatLng(43.65095, -79.47672),
      WalkAnswer(
        'Look along the south side of Bloor at number 2223. In the late 1920s, people came to this building to see a show. Its architects, Chapman and Oxley, designed the Runnymede Theatre. Years later, the same building welcomed readers as a Chapters bookstore.',
        {
          'Toronto heritage register': 'https://secure.toronto.ca/HeritagePreservation/details.do?folderRsn=2433735&propertyRsn=143774',
          'Toronto heritage study': 'https://www.toronto.ca/legdocs/mmis/2025/pb/bgrd/backgroundfile-260565.pdf',
        },
      ),
      answer: WalkAnswer(
        'A Shoppers Drug Mart occupies the former theatre. Toronto’s heritage study dates the change from bookstore to pharmacy to 2014. The local business association still identifies it as the old Runnymede Theatre.',
        {
          'Bloor West Village BIA': 'https://www.bloorwestvillagebia.com/',
          'Toronto heritage study': 'https://www.toronto.ca/legdocs/mmis/2025/pb/bgrd/backgroundfile-260565.pdf',
        },
      ),
    ),
  ],
);

const perthFieldTest = PreparedWalk(
  'Perth field test',
  [
    LatLng(44.89905, -76.24898),
    LatLng(44.89920, -76.24912),
    LatLng(44.90104, -76.25059),
    LatLng(44.90128, -76.25114),
  ],
  [
    PreparedStop(
      'Matheson House',
      LatLng(44.90104, -76.25059),
      WalkAnswer(
        'Look for the stone house at number eleven on Gore Street East. Built for Roderick Matheson in 1840, it stayed in his family for nearly a century. Later, people came here for tea, and the local Legion used the building too.',
        {
          'Town of Perth heritage walking tour': 'https://www.perth.ca/media/sq2hmfhl/heritage-perth-walking-tour-2014.pdf',
        },
      ),
      answer: WalkAnswer(
        'Matheson House is home to Perth Museum. The town moved the collection here in 1967. Inside, restored rooms show how the family lived.',
        {'Town of Perth Museum': 'https://www.perth.ca/museum'},
      ),
    ),
  ],
);

enum _Phase { ready, locating, walking, story, question, answer, done }

class PreparedWalkScreen extends StatefulWidget {
  const PreparedWalkScreen({
    super.key,
    required this.walk,
    required this.research,
    this.followUp,
    this.onMemories,
    this.onCapture,
    this.voice,
    this.location = const GeolocatorLocationProvider(),
  });
  final PreparedWalk walk;
  final VoidCallback? onMemories;
  final VoidCallback? onCapture;
  final Future<WalkAnswer?> Function(PreparedStop) research;
  final Future<WalkAnswer?> Function(PreparedStop, String)? followUp;
  final RoverTextToSpeech? voice;
  final RoverLocationProvider location;
  @override
  State<PreparedWalkScreen> createState() => _PreparedWalkState();
}

class _PreparedWalkState extends State<PreparedWalkScreen> {
  late final mappedRoute = preparedRoute(widget.walk);
  late final voice = widget.voice ?? DeviceTextToSpeech();
  final distance = const Distance();
  _Phase phase = _Phase.ready;
  StreamSubscription<RoverLocationReading>? gps;
  Timer? clock, questionWindow;
  late LatLng point = widget.walk.path.first;
  LatLng? lastFix;
  bool approachedFinish = false;
  final heard = <PreparedStop>{};
  final completed = <PreparedStop>[];
  final skipped = <PreparedStop>{};
  final checkpoints = <PreparedStop, int>{};
  final passages = <PreparedStop, List<String>>{};
  late final coverage = JourneyCoverage(widget.walk.path);
  int speechTurn = 0;
  bool get trail => widget.walk.theme != null;
  int segment = 0, epoch = 0;
  PreparedStop? subject;
  WalkAnswer? transcript;
  bool live = false;
  String notice = '';
  bool valid(int ticket) => mounted && ticket == epoch;
  void cancel() {
    epoch++;
    clock?.cancel();
    questionWindow?.cancel();
    gps?.cancel();
    gps = null;
  }

  @override
  void dispose() {
    cancel();
    unawaited(voice.stop());
    super.dispose();
  }

  Future<void> start(bool useGps) async {
    cancel();
    final ticket = epoch;
    setState(() {
      live = useGps;
      point = widget.walk.path.first;
      lastFix = null;
      segment = 0;
      approachedFinish = false;
      heard.clear();
      checkpoints.clear();
      passages.clear();
      completed.clear();
      skipped.clear();
      subject = null;
      transcript = null;
      notice = '';
      phase = _Phase.locating;
    });
    try {
      await voice.stop();
      if (!valid(ticket)) return;
      await voice.configure(rate: 0.5);
      if (!valid(ticket)) return;
      if (useGps) {
        final failure = await widget.location.requestForegroundPermission();
        if (!valid(ticket)) return;
        if (failure != null) {
          unavailable(failure.recovery);
          return;
        }
      }
      if (trail) {
        final opening =
            'On this walk, explore ${widget.walk.theme}. Our first chapter is at ${widget.walk.stops.first.name}.';
        setState(() => transcript = WalkAnswer(opening, {}));
        await voice.speak(opening);
        if (!valid(ticket)) return;
      }
      setState(() => phase = _Phase.walking);
      if (useGps) {
        gps = widget.location.watchLocation().listen(
          (r) {
            if (!valid(ticket) ||
                r.accuracyMeters == null ||
                !r.accuracyMeters!.isFinite ||
                r.accuracyMeters! < 0 ||
                r.accuracyMeters! > 40 ||
                r.recordedAtUtc
                        .toUtc()
                        .difference(DateTime.now().toUtc())
                        .abs() >
                    const Duration(minutes: 1))
              return;
            lastFix = LatLng(r.location.latitude, r.location.longitude);
            advance(lastFix!);
          },
          onError: (Object _) {
            if (valid(ticket))
              unavailable(
                'Location is unavailable. Check permission and try again.',
              );
          },
        );
      } else {
        clock = Timer.periodic(
          const Duration(milliseconds: 250),
          (_) => tick(),
        );
      }
    } catch (_) {
      if (valid(ticket)) unavailable('Could not start playback. Try again.');
    }
  }

  void unavailable(String message) {
    cancel();
    unawaited(voice.stop());
    setState(() {
      phase = _Phase.ready;
      notice = message;
    });
  }

  void tick() {
    if (phase != _Phase.walking) return;
    final path = widget.walk.path;
    if (segment >= path.length - 1) {
      advance(path.last);
      return;
    }
    final target = path[segment + 1];
    final meters = distance(point, target);
    if (meters <= 12) {
      segment++;
      advance(target);
      return;
    }
    final f = 12 / meters;
    advance(
      LatLng(
        point.latitude + (target.latitude - point.latitude) * f,
        point.longitude + (target.longitude - point.longitude) * f,
      ),
    );
  }

  void advance(LatLng position) {
    if (phase != _Phase.walking && phase != _Phase.story && phase != _Phase.question) return;
    setState(() => point = position);
    if (distance(point, widget.walk.path.last) > 40) approachedFinish = true;
    final remaining = widget.walk.stops.where((s) => !heard.contains(s));
    final eligible = widget.walk.orderedChapters ? remaining.take(1) : remaining;
    final arrival = eligible.where((s) => distance(point, s.point) <= 40).firstOrNull;
    if (phase != _Phase.walking) {
      if (!live || subject == null) return;
      if (phase == _Phase.question && approachedFinish && distance(point, widget.walk.path.last) <= 25) {
        resumeWalk();
        return;
      }
      if (distance(point, subject!.point) <= 55) return;
      if (arrival != null || phase == _Phase.question) unawaited(changeStop());
      return;
    }
    final interrupted = checkpoints.keys.where((s) =>
        !skipped.contains(s) && distance(point, s.point) <= 250).lastOrNull;
    PreparedStop? stop = arrival ?? interrupted;
    if (stop == null && live && coverage.project(point).away >= 50) {
      final nearby = eligible.where((s) => distance(point, s.point) <= 250).toList()
        ..sort((a, b) => distance(point, a.point).compareTo(distance(point, b.point)));
      stop = nearby.firstOrNull;
    }
    if (stop != null) {
      heard.add(stop);
      unawaited(tell(stop));
    } else if (live
        ? approachedFinish && distance(point, widget.walk.path.last) <= 25
        : segment >= widget.walk.path.length - 1) {
      cancel();
      final recap = completed.isEmpty
          ? 'You reached the end without finishing a chapter.'
          : 'You reached the end of ${widget.walk.theme}. You heard the stories of ${completed.map((s) => s.name).join(", ")}.';
      setState(() {
        phase = _Phase.done;
        if (trail) transcript = WalkAnswer(recap, {});
      });
      if (trail) unawaited(voice.speak(recap).catchError((Object _) {}));
    }
  }

  Future<void> changeStop() async {
    final ticket = epoch;
    speechTurn++;
    questionWindow?.cancel();
    setState(() => phase = _Phase.locating);
    await voice.stop();
    if (valid(ticket)) resumeWalk();
  }

  Future<void> tell(PreparedStop stop) async {
    final ticket = epoch;
    final turn = ++speechTurn;
    setState(() {
      subject = stop;
      transcript = stop.story;
      phase = _Phase.story;
      notice = '';
    });
    bool ready = false;
    if (stop.pictures.isNotEmpty) {
      unawaited(storyPhotoReady(stop.pictures.first).then((value) { ready = value; }));
    }
    try {
      final parts = passages.putIfAbsent(stop, () => [
        if (distance(point, stop.point) > 40)
          'Nearby on your planned walk is ${stop.name}.'
        else if (trail && completed.isNotEmpty)
          'From ${completed.last.name}, we move on to ${stop.name}.',
        if (stop.photo case final photo?) photo.cue,
        ...stop.story.text.split(RegExp(r'(?<=[.!?])\s+')),
      ]);
      var sentence = checkpoints[stop] ?? 0;
      checkpoints[stop] = sentence;
      while (sentence < parts.length) {
        await voice.speak(parts[sentence]);
        if (!valid(ticket) || turn != speechTurn) return;
        checkpoints[stop] = ++sentence;
      }
      checkpoints.remove(stop);
      completed.add(stop);
      if (ready && valid(ticket) && turn == speechTurn) await voice.speak(storyPictureCue);
    } catch (_) {
      if (valid(ticket) && turn == speechTurn && phase == _Phase.story) {
        checkpoints.remove(stop);
        setState(() => notice = 'Audio unavailable. The story is shown below.');
      }
    }
    if (!valid(ticket) || turn != speechTurn || phase != _Phase.story) return;
    setState(() => phase = _Phase.question);
    questionWindow = Timer(const Duration(seconds: 12), resumeWalk);
  }

  Future<void> skipChapter() async {
    final active = phase == _Phase.story || phase == _Phase.question;
    final stop = active
        ? subject
        : widget.walk.stops.where((s) => !heard.contains(s)).firstOrNull;
    if (stop == null) return;
    final ticket = epoch;
    speechTurn++;
    questionWindow?.cancel();
    heard.add(stop);
    checkpoints.remove(stop);
    if (!completed.contains(stop)) skipped.add(stop);
    setState(() => phase = _Phase.locating);
    await voice.stop();
    if (!valid(ticket)) return;
    setState(() {
      notice = 'Continuing past ${stop.name}.';
      transcript = null;
    });
    resumeWalk();
  }

  Future<void> askChapter() async {
    final stop = subject;
    if (stop == null) return;
    final ticket = epoch;
    final interrupted = phase == _Phase.story;
    speechTurn++;
    questionWindow?.cancel();
    setState(() => phase = _Phase.answer);
    try {
      await voice.stop();
      if (!valid(ticket)) return;
      var typed = '';
      final question = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Ask about ${stop.name}'),
          content: TextField(
            autofocus: true,
            maxLength: 400,
            onChanged: (v) => typed = v,
            onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, typed.trim()),
              child: const Text('Ask'),
            ),
          ],
        ),
      );
      if (!valid(ticket) || question == null || question.isEmpty) return;
      setState(() => notice = 'Looking up your question…');
      final answer = await widget.followUp!(stop, question);
      if (!valid(ticket)) return;
      final reply =
          answer ??
          const WalkAnswer('I couldn’t verify an answer for this place.', {});
      setState(() {
        transcript = reply;
        notice = '';
      });
      await voice.speak(reply.text);
    } catch (_) {
      if (valid(ticket))
        setState(() => notice = 'Question lookup was unavailable.');
    } finally {
      if (valid(ticket)) {
        if (interrupted && (!live || distance(lastFix ?? point, stop.point) <= 250)) {
          unawaited(tell(stop));
        } else {
          resumeWalk();
        }
      }
    }
  }

  Future<void> ask() async {
    final stop = subject;
    if (stop == null || !(phase == _Phase.story || phase == _Phase.question))
      return;
    final ticket = epoch;
    final interrupted = phase == _Phase.story;
    speechTurn++;
    questionWindow?.cancel();
    setState(() {
      phase = _Phase.answer;
      notice = 'Checking the current use…';
    });
    try {
      await voice.stop();
      if (!valid(ticket)) return;
      final answer = stop.answer ?? await widget.research(stop);
      if (!valid(ticket)) return;
      final reply =
          answer ?? const WalkAnswer('I couldn’t verify what’s there now.', {});
      setState(() {
        transcript = reply;
        notice = '';
      });
      await voice.speak(reply.text);
    } catch (_) {
      if (valid(ticket))
        setState(() => notice = 'The answer could not finish.');
    } finally {
      if (valid(ticket)) {
        if (interrupted && (!live || distance(lastFix ?? point, stop.point) <= 250)) {
          unawaited(tell(stop));
        } else {
          resumeWalk();
        }
      }
    }
  }

  void resumeWalk() {
    questionWindow?.cancel();
    setState(() => phase = _Phase.walking);
    if (live && lastFix != null) advance(lastFix!);
  }

  @override
  Widget build(BuildContext context) {
    final walk = widget.walk;
    final choosing = phase == _Phase.ready || phase == _Phase.done;
    final asking = phase == _Phase.story || phase == _Phase.question;
    return Scaffold(
      appBar: AppBar(title: Text(walk.title), actions: [
        if (widget.onMemories != null)
          IconButton(onPressed: widget.onMemories, tooltip: 'Walk Memories',
            icon: const Icon(Icons.photo_library_outlined)),
      ]),
      bottomNavigationBar: widget.onCapture == null ? null : SafeArea(
        child: Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: FilledButton.icon(onPressed: widget.onCapture, icon: const Icon(Icons.add_a_photo_outlined),
            label: const Text('Take photo or video')))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (subject != null && subject!.pictures.isNotEmpty)
            PictureCarousel(pictures: subject!.pictures, compact: true),
          if ((asking || phase == _Phase.answer) && subject?.photo != null)
            TextButton.icon(
              icon: SizedBox(width: 110, height: 72, child: Image.asset(subject!.photo!.asset, fit: BoxFit.cover)),
              label: Text('View photo · ${subject!.photo!.caption}'),
              onPressed: () => subject!.photo!.open(context),
            ),
          RoverMapView(
            height: 245,
            overview: choosing,
            currentLocation: RoverLatLng(latitude: point.latitude, longitude: point.longitude),
            routeGeometry: mappedRoute.routeGeometry, orderedStops: mappedRoute.orderedStops,
          ),
          if (identical(walk, bloorRehearsal))
            const ListTile(
              title: Text('Runnymede Road to the Humber bridge'),
              subtitle: Text('Shared rehearsal · 8 November 2026'),
            ),
          if (identical(walk, perthFieldTest))
            const ListTile(
              title: Text('Town Hall to Foster Street'),
              subtitle: Text(
                'Follow Gore Street East past Perth Museum · 8 November 2026',
              ),
            ),
          if (trail) ...[
            if (choosing)
              for (final (i, s) in walk.stops.indexed)
                ListTile(
                  leading: Text('${i + 1}'),
                  title: Text(s.name),
                  trailing: s.photo == null ? null : IconButton(
                    tooltip: 'View photo of ${s.name}', icon: const Icon(Icons.image_outlined),
                    onPressed: () => s.photo!.open(context)),

                  subtitle: Text(
                    s.story.text,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            Text(
              '${completed.length} of ${walk.stops.length} chapters heard · ${skipped.length} skipped',
            ),
          ],
          if (choosing) ...[
            if (phase == _Phase.done) const Text('Walk complete'),
            FilledButton.icon(
              onPressed: () => start(false),
              icon: const Icon(Icons.play_arrow),
              label: const Text('Play from home'),
            ),
            OutlinedButton(
              onPressed: () => start(true),
              child: Text(widget.onMemories == null ? 'Test on foot with GPS' : 'Start walking with GPS'),
            ),
          ] else ...[
            Text(switch (phase) {
              _Phase.locating => 'Starting…',
              _Phase.walking =>
                live
                    ? 'Walking · waiting for the next arrival'
                    : 'Simulating the walk',
              _Phase.answer => 'Follow-up · ${subject?.name}',
              _ => 'Story · ${subject?.name}',
            }),
            if (phase == _Phase.walking || asking)
              TextButton(
                onPressed: skipChapter,
                child: Text(
                  phase == _Phase.walking
                      ? 'Skip next stop'
                      : 'Continue to next stop',
                ),
              ),
            if (asking && trail && widget.followUp != null)
              FilledButton(
                onPressed: askChapter,
                child: const Text('Ask a question'),
              ),
            if (asking && !trail)
              FilledButton(
                onPressed: ask,
                child: const Text('What’s there now?'),
              ),
            if (phase == _Phase.question)
              TextButton(
                onPressed: resumeWalk,
                child: const Text('Continue walking'),
              ),
            TextButton(
              onPressed: () => unavailable('Walk stopped.'),
              child: const Text('Stop walk'),
            ),
          ],
          if (notice.isNotEmpty) Text(notice),
          if (transcript case final entry?) ...[
            SelectableText(spokenLocationText(entry.text)),
            for (final source in entry.sources.entries)
              TextButton(
                onPressed: () async {
                  final uri = Uri.tryParse(source.value);
                  if (uri != null && ['https', 'http'].contains(uri.scheme))
                    await launchUrl(uri);
                },
                child: Text(source.key),
              ),
          ],
        ],
      ),
    );
  }
}
