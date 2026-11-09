import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../location/rover_location.dart';
import '../voice/rover_audio_services.dart';
import '../voice/spoken_location.dart';

class WalkAnswer {
  const WalkAnswer(this.text, this.sources);
  final String text;
  final Map<String, String> sources;
}

class PreparedStop {
  const PreparedStop(this.name, this.point, this.story, {this.answer});
  final String name;
  final LatLng point;
  final WalkAnswer story;
  final WalkAnswer? answer;
}

class PreparedWalk {
  const PreparedWalk(this.title, this.path, this.stops, {this.theme});
  final String? theme;
  final String title;
  final List<LatLng> path;
  final List<PreparedStop> stops;
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
    this.voice,
    this.location = const GeolocatorLocationProvider(),
  });
  final PreparedWalk walk;
  final Future<WalkAnswer?> Function(PreparedStop) research;
  final Future<WalkAnswer?> Function(PreparedStop, String)? followUp;
  final RoverTextToSpeech? voice;
  final RoverLocationProvider location;
  @override
  State<PreparedWalkScreen> createState() => _PreparedWalkState();
}

class _PreparedWalkState extends State<PreparedWalkScreen> {
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
  int sentence = 0, speechTurn = 0;
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
    if (phase != _Phase.walking) return;
    setState(() => point = position);
    if (distance(point, widget.walk.path.last) > 40) approachedFinish = true;
    final stop = widget.walk.stops
        .where((s) => !heard.contains(s) && distance(point, s.point) <= 40)
        .firstOrNull;
    if (stop != null) {
      heard.add(stop);
      sentence = 0;
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

  Future<void> tell(PreparedStop stop) async {
    final ticket = epoch;
    final turn = ++speechTurn;
    setState(() {
      subject = stop;
      transcript = stop.story;
      phase = _Phase.story;
      notice = '';
    });
    try {
      if (trail) {
        final parts = [
          if (completed.isNotEmpty)
            'From ${completed.last.name}, we move on to ${stop.name}.',
          ...stop.story.text.split(RegExp(r'(?<=[.!?])\s+')),
        ];
        while (sentence < parts.length) {
          await voice.speak(parts[sentence]);
          if (!valid(ticket) || turn != speechTurn) return;
          sentence++;
        }
        completed.add(stop);
      } else {
        await voice.speak(stop.story.text);
      }
    } catch (_) {
      if (valid(ticket) && phase == _Phase.story)
        setState(() => notice = 'Audio unavailable. The story is shown below.');
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
        if (interrupted) {
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
      if (valid(ticket)) resumeWalk();
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
      appBar: AppBar(title: Text(walk.title)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SizedBox(
            height: 245,
            child: FlutterMap(
              options: MapOptions(
                initialCameraFit: CameraFit.coordinates(
                  coordinates: walk.path,
                  padding: const EdgeInsets.all(30),
                  maxZoom: 17,
                ),
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'ai.myrover.rover',
                ),
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: walk.path,
                      strokeWidth: 5,
                      color: Colors.indigo,
                    ),
                  ],
                ),
                MarkerLayer(
                  markers: [
                    for (final s in walk.stops)
                      Marker(
                        point: s.point,
                        child: const Icon(Icons.headphones),
                      ),
                    Marker(
                      point: point,
                      child: const Icon(Icons.navigation, color: Colors.blue),
                    ),
                  ],
                ),
                const SimpleAttributionWidget(
                  source: Text('OpenStreetMap contributors'),
                ),
              ],
            ),
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
              child: const Text('Test on foot with GPS'),
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
            if (trail && (phase == _Phase.walking || asking))
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
